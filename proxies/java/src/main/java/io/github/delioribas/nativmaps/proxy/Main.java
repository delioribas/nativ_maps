// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// A standalone server around Proxy.java, with nothing but the JDK's
// com.sun.net.httpserver.
//
//   PROXY_TOKEN=… AWS_REGION=us-east-1 java -jar target/nativ-maps-proxy.jar
//
// The variables are the same in every reference proxy.

package io.github.delioribas.nativmaps.proxy;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;

public final class Main {

  /** Like node:http, these keep only their first value when repeated. */
  private static final Set<String> SINGLE_VALUED = Set.of(
      "age", "authorization", "content-length", "content-type", "etag",
      "expires", "from", "host", "if-modified-since", "if-unmodified-since",
      "last-modified", "location", "max-forwards", "proxy-authorization",
      "referer", "retry-after", "server", "user-agent");

  private static final PrintStream LOG =
      new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8);

  private Main() {}

  public static void main(String[] args) throws IOException {
    Map<String, String> env = System.getenv();
    String port = orDefault(env.get("PORT"), "8080");
    String basePath = env.getOrDefault("PROXY_BASE_PATH", "/geo");
    String publicUrl = env.get("PROXY_PUBLIC_URL");
    String token = env.get("PROXY_TOKEN");
    String region = env.get("AWS_REGION");
    String apiKey = env.get("ALS_API_KEY");

    if (token == null || token.isEmpty() || region == null || region.isEmpty()) {
      System.err.println("PROXY_TOKEN and AWS_REGION are required.");
      System.exit(1);
    }

    // A shared token, to try it. In production, check your own session here:
    // your JWT, your cookie, whatever your backend already uses.
    byte[] expected = ("Bearer " + token).getBytes(StandardCharsets.UTF_8);
    Proxy.Authorizer authorize = headers -> {
      byte[] given = headers.getOrDefault("authorization", "")
          .getBytes(StandardCharsets.UTF_8);
      return given.length == expected.length && MessageDigest.isEqual(given, expected);
    };

    Proxy proxy = Proxy.builder()
        .region(region)
        .authorize(authorize)
        .apiKey(apiKey)
        .publicUrl(publicUrl)
        .build();

    HttpServer server = HttpServer.create(new InetSocketAddress(Integer.parseInt(port)), 0);
    server.createContext("/", exchange -> {
      try {
        serve(exchange, proxy, basePath);
      } finally {
        exchange.close();
      }
    });
    server.setExecutor(Executors.newCachedThreadPool());
    server.start();
    LOG.println("nativ_maps proxy on :" + port + basePath);
  }

  private static void serve(HttpExchange exchange, Proxy proxy, String basePath)
      throws IOException {
    String method = exchange.getRequestMethod();
    URI uri = exchange.getRequestURI();
    String pathname = resolveDots(uri.getRawPath());
    if (!pathname.startsWith(basePath + "/")) {
      exchange.sendResponseHeaders(404, -1);
      return;
    }
    byte[] body = exchange.getRequestBody().readAllBytes();
    Map<String, String> headers = lowercase(exchange);
    String scheme = headers.getOrDefault("x-forwarded-proto", "http");

    Proxy.Result result;
    try {
      result = proxy.handle(
          method,
          pathname.substring(basePath.length()),
          uri.getRawQuery(),
          headers,
          body,
          scheme + "://" + headers.get("host") + basePath);
    } catch (RuntimeException e) {
      System.err.println("nativ_maps proxy: " + e.getClass().getSimpleName());
      result = Proxy.error(500, "Internal error");
    }

    // Path and status only: the query can carry user data, and never log
    // headers, which carry the user's token.
    LOG.println(method + " " + pathname + " → " + result.status());
    result.headers().forEach(exchange.getResponseHeaders()::set);
    byte[] bytes = result.body();
    boolean empty = bytes.length == 0 || method.equalsIgnoreCase("HEAD");
    exchange.sendResponseHeaders(result.status(), empty ? -1 : bytes.length);
    if (!empty) {
      try (OutputStream out = exchange.getResponseBody()) {
        out.write(bytes);
      }
    }
  }

  /** Header names in lowercase, repeated values joined the way node:http does. */
  private static Map<String, String> lowercase(HttpExchange exchange) {
    Map<String, String> headers = new HashMap<>();
    exchange.getRequestHeaders().forEach((name, values) -> {
      if (values.isEmpty()) return;
      String key = name.toLowerCase(Locale.ROOT);
      String value = SINGLE_VALUED.contains(key) ? values.get(0) : String.join(", ", values);
      headers.merge(key, value, (a, b) -> SINGLE_VALUED.contains(key) ? a : a + ", " + b);
    });
    return headers;
  }

  /** `.` and `..` segments resolved, as the WHATWG URL parser does in Node. */
  static String resolveDots(String rawPath) {
    if (rawPath == null || !rawPath.startsWith("/")) return "/" + (rawPath == null ? "" : rawPath);
    String[] segments = rawPath.substring(1).split("/", -1);
    List<String> out = new ArrayList<>();
    for (int i = 0; i < segments.length; i++) {
      String s = segments[i].toLowerCase(Locale.ROOT);
      boolean last = i == segments.length - 1;
      if (s.equals("..") || s.equals(".%2e") || s.equals("%2e.") || s.equals("%2e%2e")) {
        if (!out.isEmpty()) out.remove(out.size() - 1);
        if (last) out.add("");
      } else if (s.equals(".") || s.equals("%2e")) {
        if (last) out.add("");
      } else {
        out.add(segments[i]);
      }
    }
    return "/" + String.join("/", out);
  }

  private static String orDefault(String value, String fallback) {
    return value == null || value.isEmpty() ? fallback : value;
  }
}
