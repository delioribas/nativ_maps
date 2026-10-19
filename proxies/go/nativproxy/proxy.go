// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.

// Package nativproxy is the reference proxy for nativ_maps' ProxyCredentials:
// the phone calls this server, this server authenticates with Amazon Location
// and forwards. The phone never holds an AWS secret. The contract it
// implements is in doc/PROXY.md.
//
// It is framework-agnostic on purpose. [Proxy.Handle] takes and returns plain
// values, so it fits an AWS Lambda handler as well as any router, and
// [Proxy.Handler] wraps it as an [http.Handler] for net/http, chi, gin
// (gin.WrapH), echo (echo.WrapHandler) or anything else that speaks net/http.
package nativproxy

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	v4 "github.com/aws/aws-sdk-go-v2/aws/signer/v4"
	"github.com/aws/aws-sdk-go-v2/config"
)

var (
	// awsHost matches the only hosts this proxy will ever forward to. The
	// second group is the region the request is signed for.
	awsHost = regexp.MustCompile(`^(places|routes|maps|geofencing|tracking|cp\.geofencing|cp\.tracking)\.geo\.([a-z0-9-]+)\.amazonaws\.com$`)

	// mapAsset is what the map renderer asks for: it sends no X-Nativ headers.
	mapAsset = regexp.MustCompile(`^/v2/(styles|tiles|glyphs|static)/`)

	// descriptor is the style descriptor, whose URLs have to be rewritten.
	descriptor = regexp.MustCompile(`^/v2/styles/[^/]+/descriptor$`)

	// keyParam is a `key=` parameter inside a URL, with the `&` after it.
	keyParam = regexp.MustCompile(`[?&]key=[^&"\s]*&?`)

	// textType is a content type whose body may be scanned for the API key.
	textType = regexp.MustCompile(`json|text|xml`)
)

// signingNames is the SigV4 signing name per host prefix; geofencing and
// tracking, data and control plane alike, sign as plain `geo`.
var signingNames = map[string]string{
	"places": "geo-places",
	"routes": "geo-routes",
	"maps":   "geo-maps",
}

// passBack lists the response headers worth passing back; the rest are AWS
// internals.
var passBack = []string{"Content-Type", "Cache-Control", "ETag", "X-Amzn-Requestid"}

// Options configures a [Proxy].
type Options struct {
	// Region is used for map requests, which carry no X-Nativ headers.
	// Required.
	Region string

	// Authorize is your user check: your JWT, your cookie, whatever your
	// backend already uses. It runs before anything else; return false and
	// the request is answered 401 without forwarding anything. Required.
	Authorize func(ctx context.Context, header http.Header) bool

	// APIKey is an optional Amazon Location API key. If set, Places, Routes
	// and Maps use it instead of SigV4; it never reaches the phone.
	// Geofencing and tracking always need SigV4.
	APIKey string

	// PublicURL is the proxy's public base URL, for the style descriptor.
	// Empty means it is taken from each request (see [Request.Origin]).
	PublicURL string

	// Credentials signs the requests. Nil means the standard AWS chain:
	// environment variables, shared profile, SSO, container or instance role.
	Credentials aws.CredentialsProvider

	// Client sends the requests to AWS. Nil means a client with a 60-second
	// timeout that never follows redirects.
	Client *http.Client

	// Logger receives one line per request from [Proxy.Handler]: method, path
	// and status, never the query or the headers. Nil means [log.Default].
	Logger *log.Logger
}

// Request is an incoming request, independent of any framework.
type Request struct {
	// Method is the HTTP method, forwarded as is.
	Method string

	// Path is the AWS path, without the proxy's base, percent-encoded as it
	// arrived: `/v2/geocode`, not `/geo/v2/geocode`.
	Path string

	// Query is the raw query string, with or without the leading `?`.
	Query string

	// Header holds the incoming headers. Only Content-Type is forwarded.
	Header http.Header

	// Body is the request body, or nil. It is read only after Authorize
	// accepts the request.
	Body io.Reader

	// Origin is this proxy's base URL as the client saw it, such as
	// `https://api.example.com/geo`. Used only when PublicURL is empty.
	Origin string
}

// Response is what to send back to the client.
type Response struct {
	Status int
	Header http.Header
	Body   []byte
}

// Proxy forwards authorized requests to Amazon Location. It is safe for
// concurrent use; create one and share it.
type Proxy struct {
	region      string
	authorize   func(context.Context, http.Header) bool
	apiKey      string
	publicURL   string
	credentials aws.CredentialsProvider
	signer      *v4.Signer
	client      *http.Client
	logger      *log.Logger
}

// New creates a [Proxy]. Without Options.Credentials it loads the default
// AWS configuration, which is the only reason it needs a context.
func New(ctx context.Context, opts Options) (*Proxy, error) {
	if opts.Region == "" {
		return nil, errors.New("nativproxy: Region is required")
	}
	if opts.Authorize == nil {
		return nil, errors.New("nativproxy: Authorize is required")
	}

	credentials := opts.Credentials
	if credentials == nil {
		cfg, err := config.LoadDefaultConfig(ctx)
		if err != nil {
			return nil, fmt.Errorf("nativproxy: loading the AWS configuration: %w", err)
		}
		credentials = cfg.Credentials
	}
	// A cache refreshes temporary credentials before they expire instead of
	// fetching them on every request. The default chain already comes cached.
	if _, cached := credentials.(*aws.CredentialsCache); credentials != nil && !cached {
		credentials = aws.NewCredentialsCache(credentials)
	}

	client := opts.Client
	if client == nil {
		client = &http.Client{
			Timeout: 60 * time.Second,
			// Amazon Location doesn't redirect. If something ever did, the
			// redirect is passed back instead of followed: this proxy goes
			// only to the hosts it validated.
			CheckRedirect: func(*http.Request, []*http.Request) error {
				return http.ErrUseLastResponse
			},
		}
	}

	logger := opts.Logger
	if logger == nil {
		logger = log.Default()
	}

	return &Proxy{
		region:      opts.Region,
		authorize:   opts.Authorize,
		apiKey:      opts.APIKey,
		publicURL:   strings.TrimRight(opts.PublicURL, "/"),
		credentials: credentials,
		signer:      v4.NewSigner(),
		client:      client,
		logger:      logger,
	}, nil
}

// Handle authorizes one request, forwards it to Amazon Location and returns
// the answer. It never returns an error: every failure is a [Response] with
// a JSON `{"message": "…"}` body, and AWS's own errors come back unchanged.
func (p *Proxy) Handle(ctx context.Context, req Request) Response {
	// 1 · Your user, before anything else: an unauthenticated request must
	//     not cost a cent.
	if !p.authorize(ctx, req.Header) {
		return errorResponse(http.StatusUnauthorized, "Unauthorized")
	}

	// 2 · Where it's going. The package says it; the map renderer doesn't,
	//     and everything it asks for lives on the Maps host.
	host := req.Header.Get("X-Nativ-Host")
	if host == "" {
		if !mapAsset.MatchString(req.Path) {
			return errorResponse(http.StatusBadRequest, "Missing X-Nativ-Host")
		}
		region := req.Header.Get("X-Nativ-Region")
		if region == "" {
			region = p.region
		}
		host = "maps.geo." + region + ".amazonaws.com"
	}
	// A header from the phone is a header anyone can forge: never forward
	// anywhere but Amazon Location. The signing name comes from the host,
	// not from anything else the client says.
	match := awsHost.FindStringSubmatch(host)
	if match == nil {
		return errorResponse(http.StatusBadRequest, "Not an Amazon Location host")
	}
	prefix, hostRegion := match[1], match[2]
	service, ok := signingNames[prefix]
	if !ok {
		service = "geo"
	}

	target, err := url.Parse("https://" + host + req.Path)
	if err != nil || !strings.HasPrefix(req.Path, "/") || target.Host != host {
		return errorResponse(http.StatusBadRequest, "Malformed path")
	}

	// 3 · The query as it came, minus any key the client may have sent.
	//     Repeated parameters stay repeated.
	params := withoutKey(parseQuery(req.Query))
	withKey := p.apiKey != "" && service != "geo"
	if withKey {
		params = append(params, param{name: "key", value: p.apiKey})
	}
	target.RawQuery = encodeQuery(params)

	var body []byte
	if req.Body != nil {
		if body, err = io.ReadAll(req.Body); err != nil {
			return errorResponse(http.StatusBadRequest, "Could not read the request body")
		}
	}

	// 4 · Only what AWS needs. The app's Authorization belongs to your
	//     backend, and SigV4 puts its own.
	var reader io.Reader
	if len(body) > 0 {
		reader = bytes.NewReader(body)
	}
	outgoing, err := http.NewRequestWithContext(ctx, req.Method, target.String(), reader)
	if err != nil {
		return errorResponse(http.StatusBadRequest, "Malformed request")
	}
	if contentType := req.Header.Get("Content-Type"); contentType != "" {
		outgoing.Header.Set("Content-Type", contentType)
	}
	if !withKey {
		if err := p.sign(ctx, outgoing, body, service, hostRegion); err != nil {
			// The detail stays in the server log: it may name profiles,
			// roles or files that are none of the client's business.
			p.logger.Printf("nativproxy: signing failed: %v", err)
			return errorResponse(http.StatusInternalServerError, "Could not sign the request for Amazon Location")
		}
	}

	response, err := p.client.Do(outgoing)
	if err != nil {
		return errorResponse(http.StatusBadGateway, "Amazon Location unreachable: "+p.transportMessage(err))
	}
	defer response.Body.Close()
	// net/http has already decompressed a gzip body it asked for, so
	// Content-Encoding is not passed back.
	data, err := io.ReadAll(response.Body)
	if err != nil {
		return errorResponse(http.StatusBadGateway, "Amazon Location unreachable: "+p.transportMessage(err))
	}

	// 5 · The answer as it came —status and body— so the package's own
	//     error handling works through the proxy.
	header := http.Header{}
	for _, name := range passBack {
		if value := response.Header.Get(name); value != "" {
			header.Set(name, value)
		}
	}

	// 6 · The style descriptor points at AWS, and with an API key AWS writes
	//     the key into every tile URL. Both are rewritten: the tiles come back
	//     through here, and the key never reaches the phone.
	success := response.StatusCode >= 200 && response.StatusCode < 300
	if success && descriptor.MatchString(req.Path) {
		base := p.publicURL
		if base == "" {
			base = req.Origin
		}
		text := strings.ReplaceAll(string(data), "https://maps.geo."+hostRegion+".amazonaws.com", base)
		data = []byte(stripKey(text))
	}
	if p.apiKey != "" && textType.MatchString(header.Get("Content-Type")) &&
		bytes.Contains(data, []byte(p.apiKey)) {
		data = bytes.ReplaceAll(data, []byte(p.apiKey), nil)
	}

	return Response{Status: response.StatusCode, Header: header, Body: data}
}

// Handler adapts the proxy to net/http, serving it under basePath (such as
// `/geo`). basePath is matched against the path the handler sees, so behind
// [http.StripPrefix] pass what is left of it, or "".
//
// Requests outside basePath get an empty 404. Every other one is logged as
// `METHOD path → status`: the query can carry user data, and the headers
// carry the user's token, so neither is ever logged.
func (p *Proxy) Handler(basePath string) http.Handler {
	basePath = strings.TrimRight(basePath, "/")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.EscapedPath()
		if !strings.HasPrefix(path, basePath+"/") {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		scheme := "http"
		if r.TLS != nil {
			scheme = "https"
		}
		if proto := r.Header.Get("X-Forwarded-Proto"); proto != "" {
			scheme = proto
		}

		result := p.Handle(r.Context(), Request{
			Method: r.Method,
			Path:   path[len(basePath):],
			Query:  r.URL.RawQuery,
			Header: r.Header,
			Body:   r.Body,
			Origin: scheme + "://" + r.Host + basePath,
		})

		p.logger.Printf("%s %s → %d", r.Method, path, result.Status)
		result.write(w)
	})
}

// write sends the response through net/http, byte for byte.
func (res Response) write(w http.ResponseWriter) {
	header := w.Header()
	for name, values := range res.Header {
		header[name] = values
	}
	// Without this, net/http would sniff a Content-Type AWS never sent.
	if _, ok := header["Content-Type"]; !ok {
		header["Content-Type"] = nil
	}
	if len(res.Body) > 0 {
		header.Set("Content-Length", strconv.Itoa(len(res.Body)))
	}
	w.WriteHeader(res.Status)
	if len(res.Body) > 0 {
		_, _ = w.Write(res.Body)
	}
}

// sign adds SigV4 to the outgoing request, with the SHA-256 of its body
// (the hash of the empty string when there is none).
func (p *Proxy) sign(ctx context.Context, req *http.Request, body []byte, service, region string) error {
	if p.credentials == nil {
		return errors.New("no AWS credentials provider")
	}
	credentials, err := p.credentials.Retrieve(ctx)
	if err != nil {
		return err
	}
	hash := sha256.Sum256(body)
	return p.signer.SignHTTP(ctx, credentials, req, hex.EncodeToString(hash[:]), service, region, time.Now())
}

// transportMessage describes a network failure without the URL that
// net/http puts in its errors: with an API key, that URL contains it.
func (p *Proxy) transportMessage(err error) string {
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		err = urlErr.Err
	}
	message := err.Error()
	if p.apiKey != "" {
		message = strings.ReplaceAll(message, p.apiKey, "")
	}
	return message
}

// param is one query parameter. A slice of them keeps the order and the
// repetitions, which url.Values would sort.
type param struct{ name, value string }

// parseQuery splits a raw query the way a browser's URLSearchParams does: on
// `&` only, `+` as a space, and a malformed escape kept as written. Unlike
// url.ParseQuery, it never drops a parameter it doesn't like.
func parseQuery(raw string) []param {
	var params []param
	for _, pair := range strings.Split(strings.TrimPrefix(raw, "?"), "&") {
		if pair == "" {
			continue
		}
		name, value, _ := strings.Cut(pair, "=")
		params = append(params, param{name: unescape(name), value: unescape(value)})
	}
	return params
}

// unescape decodes `+` and `%XX`, leaving any other `%` as it is.
func unescape(s string) string {
	s = strings.ReplaceAll(s, "+", " ")
	if !strings.Contains(s, "%") {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '%' && i+2 < len(s) {
			if n, err := strconv.ParseUint(s[i+1:i+3], 16, 8); err == nil {
				b.WriteByte(byte(n))
				i += 2
				continue
			}
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// withoutKey removes every `key` parameter: the client's key never goes on.
func withoutKey(params []param) []param {
	kept := params[:0]
	for _, p := range params {
		if p.name != "key" {
			kept = append(kept, p)
		}
	}
	return kept
}

// encodeQuery serializes the parameters in order, in RFC 3986 (a space is
// `%20`, never `+`): the encoding SigV4 signs, so every proxy sends the same
// bytes. When the request is signed, the signer then rewrites it in
// canonical order.
func encodeQuery(params []param) string {
	var b strings.Builder
	for i, p := range params {
		if i > 0 {
			b.WriteByte('&')
		}
		b.WriteString(queryEscape(p.name))
		b.WriteByte('=')
		b.WriteString(queryEscape(p.value))
	}
	return b.String()
}

// queryEscape is url.QueryEscape with a space as `%20`.
func queryEscape(s string) string {
	return strings.ReplaceAll(url.QueryEscape(s), "+", "%20")
}

// stripKey removes every `key=` parameter from the URLs inside text, keeping
// the separator when another parameter follows it.
func stripKey(text string) string {
	return keyParam.ReplaceAllStringFunc(text, func(match string) string {
		if strings.HasSuffix(match, "&") {
			return match[:1]
		}
		return ""
	})
}

// errorResponse is the proxy's own error: a JSON `{"message": "…"}`.
func errorResponse(status int, message string) Response {
	var buf bytes.Buffer
	encoder := json.NewEncoder(&buf)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(map[string]string{"message": message})
	return Response{
		Status: status,
		Header: http.Header{"Content-Type": {"application/json"}},
		Body:   bytes.TrimSuffix(buf.Bytes(), []byte("\n")),
	}
}
