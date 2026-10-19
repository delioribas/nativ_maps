// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// Reference proxy for nativ_maps' `ProxyCredentials`: the phone calls this
// server, this server authenticates with Amazon Location and forwards.
// The same contract as proxies/node/proxy.mjs, line for line.
//
// Framework-agnostic on purpose: Main.java plugs it into the JDK's own
// HttpServer, and the same handle() fits a Spring Boot controller, a plain
// Servlet, Micronaut or Quarkus. See the README.

package io.github.delioribas.nativmaps.proxy;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.GZIPInputStream;
import java.util.zip.InflaterInputStream;

import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.http.SdkHttpMethod;
import software.amazon.awssdk.http.SdkHttpRequest;
import software.amazon.awssdk.http.auth.aws.signer.AwsV4HttpSigner;
import software.amazon.awssdk.identity.spi.AwsCredentialsIdentity;

/** The request handler. Thread-safe: build one and share it. */
public final class Proxy {

  /** The only hosts this proxy will ever forward to. */
  private static final Pattern AWS_HOST = Pattern.compile(
      "^(places|routes|maps|geofencing|tracking|cp\\.geofencing|cp\\.tracking)"
          + "\\.geo\\.([a-z0-9-]+)\\.amazonaws\\.com$");

  /** What the map renderer asks for: it sends no X-Nativ headers. */
  private static final Pattern MAP_ASSET =
      Pattern.compile("^/v2/(styles|tiles|glyphs|static)/");

  /** The style descriptor, whose URLs have to be rewritten. */
  private static final Pattern DESCRIPTOR =
      Pattern.compile("^/v2/styles/[^/]+/descriptor$");

  /** SigV4 signing name per host prefix; geofencing and tracking sign as `geo`. */
  private static final Map<String, String> SIGNING_NAME = Map.of(
      "places", "geo-places",
      "routes", "geo-routes",
      "maps", "geo-maps");

  /** Response headers worth passing back; the rest are AWS internals. */
  private static final List<String> PASS_BACK =
      List.of("content-type", "cache-control", "etag", "x-amzn-requestid");

  /** A `key=` parameter inside a URL, and the `&` after it, if any. */
  private static final Pattern KEY_PARAM =
      Pattern.compile("([?&])key=[^&\"\\s]*(&)?");

  private static final Pattern TEXT = Pattern.compile("json|text|xml");

  /** Headers java.net.http sets itself and refuses to take. */
  private static final Set<String> SET_BY_CLIENT =
      Set.of("host", "content-length", "connection", "expect", "upgrade");

  /**
   * Your user check. Return false and nothing is forwarded.
   *
   * <p>It receives the request headers, with case-insensitive names. In
   * production, check your own session here: your JWT, your cookie, whatever
   * your backend already uses.
   */
  @FunctionalInterface
  public interface Authorizer {
    boolean authorize(Map<String, String> headers) throws Exception;
  }

  /** What to send back to the client: status, headers and the body bytes. */
  public record Result(int status, Map<String, String> headers, byte[] body) {}

  private final String region;
  private final Authorizer authorize;
  private final String apiKey;
  private final String publicUrl;
  private final AwsCredentialsProvider credentials;
  private final HttpClient http;
  private final Duration timeout;
  private final AwsV4HttpSigner signer = AwsV4HttpSigner.create();

  private Proxy(Builder b) {
    this.region = requireText(b.region, "region");
    this.authorize = Objects.requireNonNull(b.authorize, "authorize");
    this.apiKey = emptyToNull(b.apiKey);
    this.publicUrl = emptyToNull(b.publicUrl);
    this.credentials = b.credentials != null
        ? b.credentials
        : DefaultCredentialsProvider.builder().build();
    this.http = b.httpClient != null
        ? b.httpClient
        : HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .followRedirects(HttpClient.Redirect.NEVER)
            .connectTimeout(Duration.ofSeconds(10))
            .build();
    this.timeout = b.timeout;
  }

  /**
   * Creates the handler.
   *
   * <ul>
   *   <li>{@code region}: region for map requests, which carry no X-Nativ
   *       headers. Required.
   *   <li>{@code authorize}: your user check. Required.
   *   <li>{@code apiKey}: an Amazon Location API key. If set, Places, Routes
   *       and Maps use it instead of SigV4; it never reaches the phone.
   *       Geofencing and tracking always need SigV4.
   *   <li>{@code publicUrl}: the proxy's public base URL, for the style
   *       descriptor. Without it, it's taken from each request.
   *   <li>{@code credentials}: AWS credentials; default: the standard chain
   *       (env vars, profile, ECS/EKS/EC2 role).
   * </ul>
   */
  public static Builder builder() {
    return new Builder();
  }

  /**
   * Handles one request.
   *
   * @param method the HTTP method
   * @param path the AWS path, without the proxy's base, still percent-encoded
   * @param query the raw query string, with or without {@code ?}; may be null
   * @param headers the request headers; names in any case
   * @param body the request body; may be null or empty
   * @param origin this proxy's base URL as the client saw it, e.g.
   *     {@code https://api.example.com/geo}
   */
  public Result handle(String method, String path, String query,
      Map<String, String> headers, byte[] body, String origin) {
    path = path == null ? "" : path;
    body = body == null ? new byte[0] : body;
    Map<String, String> in = new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
    if (headers != null) {
      headers.forEach((name, value) -> {
        if (name != null && value != null) in.put(name, value);
      });
    }

    // 1 · Your user, before anything else: an unauthenticated request must
    //     not cost a cent.
    try {
      if (!authorize.authorize(Collections.unmodifiableMap(in))) {
        return error(401, "Unauthorized");
      }
    } catch (Exception e) {
      System.err.println("nativ_maps proxy: the user check threw "
          + e.getClass().getSimpleName());
      return error(500, "Authorization check failed");
    }

    // 2 · Where it's going. The package says it; the map renderer doesn't,
    //     and everything it asks for lives on the Maps host.
    String host = in.get("x-nativ-host");
    if (host == null || host.isEmpty()) {
      if (!MAP_ASSET.matcher(path).find()) {
        return error(400, "Missing X-Nativ-Host");
      }
      String given = in.get("x-nativ-region");
      host = "maps.geo." + (given == null || given.isEmpty() ? region : given)
          + ".amazonaws.com";
    }
    // A header from the phone is a header anyone can forge: never forward
    // anywhere but Amazon Location.
    Matcher match = AWS_HOST.matcher(host);
    if (!match.matches()) return error(400, "Not an Amazon Location host");
    String prefix = match.group(1);
    String hostRegion = match.group(2);
    String service = SIGNING_NAME.getOrDefault(prefix, "geo");

    // 3 · The query as it came, minus any key the client may have sent.
    //     Repeated parameters stay repeated, in their order.
    List<String[]> params = parseQuery(query);
    params.removeIf(p -> p[0].equals("key"));
    boolean withKey = apiKey != null && !service.equals("geo");
    if (withKey) params.add(new String[] {"key", apiKey});

    // 4 · Only what AWS needs. The app's Authorization belongs to your
    //     backend, and SigV4 puts its own. Path and query go out encoded
    //     exactly as they are signed.
    String encodedPath = encodePath(path);
    String encodedQuery = encodeQuery(params);
    String contentType = in.get("content-type");
    boolean hasContentType = contentType != null && !contentType.isEmpty();

    Map<String, List<String>> outgoing;
    if (withKey) {
      outgoing = new TreeMap<>(String.CASE_INSENSITIVE_ORDER);
      if (hasContentType) outgoing.put("content-type", List.of(contentType));
    } else {
      SdkHttpMethod sdkMethod;
      try {
        sdkMethod = SdkHttpMethod.fromValue(method);
      } catch (IllegalArgumentException e) {
        return error(405, "Method not allowed");
      }
      SdkHttpRequest.Builder unsigned = SdkHttpRequest.builder()
          .method(sdkMethod)
          .protocol("https")
          .host(host)
          .encodedPath(encodedPath)
          .putHeader("host", host);
      for (String[] p : params) unsigned.appendRawQueryParameter(p[0], p[1]);
      if (hasContentType) unsigned.putHeader("content-type", contentType);

      AwsCredentialsIdentity identity;
      try {
        identity = credentials.resolveCredentials();
      } catch (RuntimeException e) {
        System.err.println("nativ_maps proxy: no AWS credentials ("
            + e.getClass().getSimpleName() + ")");
        return error(500, "The proxy has no AWS credentials");
      }
      byte[] payload = body;
      outgoing = signer.sign(r -> r
              .identity(identity)
              .request(unsigned.build())
              .payload(() -> new ByteArrayInputStream(payload))
              .putProperty(AwsV4HttpSigner.SERVICE_SIGNING_NAME, service)
              .putProperty(AwsV4HttpSigner.REGION_NAME, hostRegion))
          .request()
          .headers();
    }

    URI url = URI.create("https://" + host + encodedPath
        + (encodedQuery.isEmpty() ? "" : "?" + encodedQuery));
    HttpResponse<byte[]> response;
    try {
      HttpRequest.Builder request = HttpRequest.newBuilder(url)
          .timeout(timeout)
          .method(method, body.length > 0
              ? HttpRequest.BodyPublishers.ofByteArray(body)
              : HttpRequest.BodyPublishers.noBody());
      outgoing.forEach((name, values) -> {
        if (SET_BY_CLIENT.contains(name.toLowerCase(Locale.ROOT))) return;
        for (String value : values) request.header(name, value);
      });
      // Not signed, the way fetch adds it: compression on the wire only.
      request.header("accept-encoding", "gzip");
      response = http.send(request.build(), HttpResponse.BodyHandlers.ofByteArray());
    } catch (IllegalArgumentException e) {
      return error(400, "Invalid request");
    } catch (IOException e) {
      return error(502, "Amazon Location unreachable: " + describe(e));
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return error(502, "Amazon Location unreachable: interrupted");
    }

    // 5 · The answer as it came —status and body— so the package's own
    //     error handling works through the proxy. The body is decompressed
    //     here, so content-encoding is not passed back.
    Map<String, String> out = new LinkedHashMap<>();
    for (String name : PASS_BACK) {
      String value = String.join(", ", response.headers().allValues(name));
      if (!value.isEmpty()) out.put(name, value);
    }
    byte[] bytes;
    try {
      bytes = decode(response, out);
    } catch (IOException e) {
      return error(502, "Amazon Location sent a body that can't be decoded");
    }

    // 6 · The style descriptor points at AWS, and with an API key AWS writes
    //     the key into every tile URL. Both are rewritten: the tiles come
    //     back through here, and the key never reaches the phone.
    int status = response.statusCode();
    if (status >= 200 && status < 300 && DESCRIPTOR.matcher(path).matches()) {
      String base = publicUrl != null ? publicUrl : origin;
      String text = new String(bytes, StandardCharsets.UTF_8)
          .replace("https://maps.geo." + hostRegion + ".amazonaws.com", base);
      bytes = stripKey(text).getBytes(StandardCharsets.UTF_8);
    }
    if (apiKey != null && isText(out.get("content-type"))) {
      String text = new String(bytes, StandardCharsets.UTF_8);
      if (text.contains(apiKey)) {
        bytes = text.replace(apiKey, "").getBytes(StandardCharsets.UTF_8);
      }
    }
    return new Result(status, Collections.unmodifiableMap(out), bytes);
  }

  /** Removes every `key=` parameter from the URLs inside [text]. */
  static String stripKey(String text) {
    return KEY_PARAM.matcher(text).replaceAll(m ->
        m.group(2) != null ? Matcher.quoteReplacement(m.group(1)) : "");
  }

  /** The body without its transfer compression. */
  private static byte[] decode(HttpResponse<byte[]> response,
      Map<String, String> out) throws IOException {
    byte[] bytes = response.body();
    String encoding = response.headers().firstValue("content-encoding")
        .orElse("").trim().toLowerCase(Locale.ROOT);
    if (bytes.length == 0 || encoding.isEmpty() || encoding.equals("identity")) {
      return bytes;
    }
    InputStream stream;
    switch (encoding) {
      case "gzip", "x-gzip" -> stream = new GZIPInputStream(new ByteArrayInputStream(bytes));
      case "deflate" -> stream = new InflaterInputStream(new ByteArrayInputStream(bytes));
      default -> {
        // Not asked for, and not one the JDK can undo: pass it on as it is.
        out.put("content-encoding", encoding);
        return bytes;
      }
    }
    try (stream; ByteArrayOutputStream buffer = new ByteArrayOutputStream()) {
      stream.transferTo(buffer);
      return buffer.toByteArray();
    }
  }

  /** Parses a query the way URLSearchParams does: `+` is a space. */
  static List<String[]> parseQuery(String query) {
    List<String[]> params = new ArrayList<>();
    if (query == null) return params;
    if (query.startsWith("?")) query = query.substring(1);
    for (String pair : query.split("&")) {
      if (pair.isEmpty()) continue;
      int eq = pair.indexOf('=');
      String name = eq < 0 ? pair : pair.substring(0, eq);
      String value = eq < 0 ? "" : pair.substring(eq + 1);
      params.add(new String[] {
        new String(percentDecode(name.replace('+', ' ')), StandardCharsets.UTF_8),
        new String(percentDecode(value.replace('+', ' ')), StandardCharsets.UTF_8),
      });
    }
    return params;
  }

  /** The query as SigV4 expects it on the wire: RFC 3986, `%20` for spaces. */
  private static String encodeQuery(List<String[]> params) {
    StringBuilder query = new StringBuilder();
    for (String[] p : params) {
      if (query.length() > 0) query.append('&');
      query.append(percentEncode(p[0].getBytes(StandardCharsets.UTF_8)))
          .append('=')
          .append(percentEncode(p[1].getBytes(StandardCharsets.UTF_8)));
    }
    return query.toString();
  }

  /**
   * The path with every segment fully percent-encoded, the way the AWS SDK
   * sends it, so that what is signed and what AWS receives agree. An
   * encoded slash inside a segment stays encoded.
   */
  static String encodePath(String path) {
    StringBuilder encoded = new StringBuilder();
    String[] segments = path.split("/", -1);
    for (int i = 0; i < segments.length; i++) {
      if (i > 0) encoded.append('/');
      encoded.append(percentEncode(percentDecode(segments[i])));
    }
    return encoded.toString();
  }

  /** `%XX` to bytes; a `%` not followed by two hex digits stays as it is. */
  private static byte[] percentDecode(String s) {
    byte[] in = s.getBytes(StandardCharsets.UTF_8);
    ByteArrayOutputStream out = new ByteArrayOutputStream(in.length);
    for (int i = 0; i < in.length; i++) {
      if (in[i] == '%' && i + 2 < in.length
          && hex(in[i + 1]) >= 0 && hex(in[i + 2]) >= 0) {
        out.write(hex(in[i + 1]) << 4 | hex(in[i + 2]));
        i += 2;
      } else {
        out.write(in[i]);
      }
    }
    return out.toByteArray();
  }

  /** RFC 3986: everything but the unreserved characters is encoded. */
  private static String percentEncode(byte[] bytes) {
    StringBuilder out = new StringBuilder(bytes.length);
    for (byte b : bytes) {
      int c = b & 0xff;
      if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
          || c == '-' || c == '.' || c == '_' || c == '~') {
        out.append((char) c);
      } else {
        out.append('%')
            .append(Character.toUpperCase(Character.forDigit(c >> 4, 16)))
            .append(Character.toUpperCase(Character.forDigit(c & 0xf, 16)));
      }
    }
    return out.toString();
  }

  private static int hex(byte b) {
    return Character.digit(b, 16);
  }

  private static boolean isText(String contentType) {
    return contentType != null && TEXT.matcher(contentType).find();
  }

  private static String describe(Exception e) {
    return e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
  }

  static Result error(int status, String message) {
    String json = "{\"message\":" + jsonString(message) + "}";
    return new Result(status, Map.of("content-type", "application/json"),
        json.getBytes(StandardCharsets.UTF_8));
  }

  private static String jsonString(String s) {
    StringBuilder out = new StringBuilder("\"");
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      switch (c) {
        case '"' -> out.append("\\\"");
        case '\\' -> out.append("\\\\");
        case '\n' -> out.append("\\n");
        case '\r' -> out.append("\\r");
        case '\t' -> out.append("\\t");
        default -> {
          if (c < 0x20) out.append(String.format("\\u%04x", (int) c));
          else out.append(c);
        }
      }
    }
    return out.append('"').toString();
  }

  private static String emptyToNull(String s) {
    return s == null || s.isEmpty() ? null : s;
  }

  private static String requireText(String s, String name) {
    if (s == null || s.isEmpty()) throw new IllegalArgumentException(name + " is required");
    return s;
  }

  /** Options for {@link Proxy}; see {@link Proxy#builder()}. */
  public static final class Builder {
    private String region;
    private Authorizer authorize;
    private String apiKey;
    private String publicUrl;
    private AwsCredentialsProvider credentials;
    private HttpClient httpClient;
    private Duration timeout = Duration.ofSeconds(60);

    private Builder() {}

    public Builder region(String region) {
      this.region = region;
      return this;
    }

    public Builder authorize(Authorizer authorize) {
      this.authorize = authorize;
      return this;
    }

    public Builder apiKey(String apiKey) {
      this.apiKey = apiKey;
      return this;
    }

    public Builder publicUrl(String publicUrl) {
      this.publicUrl = publicUrl;
      return this;
    }

    public Builder credentials(AwsCredentialsProvider credentials) {
      this.credentials = credentials;
      return this;
    }

    /** The client for the calls to AWS. Default: HTTP/1.1, no redirects. */
    public Builder httpClient(HttpClient httpClient) {
      this.httpClient = httpClient;
      return this;
    }

    /** How long a call to AWS may take before it's a 502. Default: 60 s. */
    public Builder timeout(Duration timeout) {
      this.timeout = Objects.requireNonNull(timeout, "timeout");
      return this;
    }

    public Proxy build() {
      return new Proxy(this);
    }
  }
}
