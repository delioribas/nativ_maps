<?php

// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// Reference proxy for nativ_maps' `ProxyCredentials`: the phone calls this
// server, this server authenticates with Amazon Location and forwards.
// The contract it implements is in doc/PROXY.md.
//
// Framework-agnostic on purpose: `public/index.php` plugs it into any PHP
// SAPI —the built-in server, Apache, php-fpm—, and the same class fits
// Laravel, Slim or Symfony (see README.md).

declare(strict_types=1);

namespace NativMaps\Proxy;

use Aws\Credentials\CredentialProvider;
use Aws\Signature\SignatureV4;
use GuzzleHttp\Client;
use GuzzleHttp\ClientInterface;
use GuzzleHttp\Exception\ConnectException;
use GuzzleHttp\Exception\GuzzleException;
use GuzzleHttp\Exception\RequestException;
use GuzzleHttp\Psr7\Request;
use GuzzleHttp\Psr7\Uri;

final class Proxy
{
    /**
     * The only hosts this proxy will ever forward to. `D`: `$` is the end of
     * the string, not "before a trailing newline" as PCRE has it by default.
     */
    private const AWS_HOST =
        '/^(places|routes|maps|geofencing|tracking|cp\.geofencing|cp\.tracking)\.geo\.([a-z0-9-]+)\.amazonaws\.com$/D';

    /** What the map renderer asks for: it sends no X-Nativ headers. */
    private const MAP_ASSET = '#^/v2/(styles|tiles|glyphs|static)/#';

    /** The style descriptor, whose URLs have to be rewritten. */
    private const DESCRIPTOR = '#^/v2/styles/[^/]+/descriptor$#D';

    /** SigV4 signing name per host prefix; geofencing and tracking sign as `geo`. */
    private const SIGNING_NAME = [
        'places' => 'geo-places',
        'routes' => 'geo-routes',
        'maps' => 'geo-maps',
    ];

    /** Response headers worth passing back; the rest are AWS internals. */
    private const PASS_BACK = ['content-type', 'cache-control', 'etag', 'x-amzn-requestid'];

    private readonly string $region;
    private readonly \Closure $authorize;
    private readonly ?string $apiKey;
    private readonly ?string $publicUrl;
    private readonly \Closure $credentials;
    private readonly ClientInterface $http;

    /** @var array<string, SignatureV4> */
    private array $signers = [];

    /**
     * @param string $region Region for map requests, which carry no X-Nativ
     *   headers.
     * @param callable(array<string, string>): bool $authorize Your user check,
     *   given the request headers with lowercase names. Return false and
     *   nothing is forwarded.
     * @param string|null $apiKey An Amazon Location API key. If set, Places,
     *   Routes and Maps use it instead of SigV4; it never reaches the phone.
     *   Geofencing and tracking always need SigV4.
     * @param string|null $publicUrl The proxy's public base URL, for the style
     *   descriptor. Without it, it's taken from each request.
     * @param callable|null $credentials An aws-sdk-php credential provider;
     *   default: the standard chain (env vars, profile, ECS/EC2 role…).
     * @param ClientInterface|null $http The HTTP client. If you pass your own,
     *   give it `http_errors => false`: AWS's errors have to come back as
     *   answers, not exceptions.
     */
    public function __construct(
        string $region,
        callable $authorize,
        ?string $apiKey = null,
        ?string $publicUrl = null,
        ?callable $credentials = null,
        ?ClientInterface $http = null,
    ) {
        $this->region = $region;
        $this->authorize = \Closure::fromCallable($authorize);
        $this->apiKey = $apiKey === '' ? null : $apiKey;
        $this->publicUrl = $publicUrl === '' ? null : $publicUrl;
        $this->credentials = \Closure::fromCallable(
            $credentials ?? CredentialProvider::defaultProvider(),
        );
        $this->http = $http ?? new Client([
            // AWS's errors are answers: they go back to the package as they
            // came, status and body, so its own error handling works.
            'http_errors' => false,
            // Never anywhere but the host that passed the allowlist.
            'allow_redirects' => false,
            'connect_timeout' => 10,
            'timeout' => 60,
        ]);
    }

    /**
     * @param string $method
     * @param string $path The AWS path, without the proxy's base, still
     *   percent-encoded as it arrived.
     * @param string $query The raw query string, with or without `?`. Raw on
     *   purpose: `$_GET` collapses repeated parameters.
     * @param array<string, string> $headers Lowercase names.
     * @param string $body The raw body (`php://input`).
     * @param string $origin This proxy's base URL as the client saw it.
     * @return array{0: int, 1: array<string, string>, 2: string} Status,
     *   headers and body.
     */
    public function handle(
        string $method,
        string $path,
        string $query,
        array $headers,
        string $body,
        string $origin,
    ): array {
        // 1 · Your user, before anything else: an unauthenticated request must
        //     not cost a cent.
        if (!($this->authorize)($headers)) {
            return self::error(401, 'Unauthorized');
        }

        // 2 · Where it's going. The package says it; the map renderer doesn't,
        //     and everything it asks for lives on the Maps host.
        $host = $headers['x-nativ-host'] ?? '';
        if ($host === '') {
            if (preg_match(self::MAP_ASSET, $path) !== 1) {
                return self::error(400, 'Missing X-Nativ-Host');
            }
            $region = ($headers['x-nativ-region'] ?? '') !== ''
                ? $headers['x-nativ-region']
                : $this->region;
            $host = "maps.geo.{$region}.amazonaws.com";
        }
        // A header from the phone is a header anyone can forge: never forward
        // anywhere but Amazon Location.
        if (preg_match(self::AWS_HOST, $host, $match) !== 1) {
            return self::error(400, 'Not an Amazon Location host');
        }
        [, $prefix, $hostRegion] = $match;
        $service = self::SIGNING_NAME[$prefix] ?? 'geo';

        // 3 · The query as it came, minus any key the client may have sent.
        //     Pair by pair, so `additional-features=Contact&additional-
        //     features=TimeZone` keeps both.
        $params = array_filter(
            self::parseQuery($query),
            static fn (array $pair): bool => $pair[0] !== 'key',
        );
        $withKey = $this->apiKey !== null && $service !== 'geo';
        if ($withKey) {
            $params[] = ['key', $this->apiKey];
        }
        $outgoingQuery = implode('&', array_map(
            static fn (array $pair): string => rawurlencode($pair[0]) . '=' . rawurlencode($pair[1]),
            $params,
        ));

        // 4 · Only what AWS needs. The app's Authorization belongs to your
        //     backend, and SigV4 puts its own.
        $outgoingHeaders = ['host' => $host];
        if (($headers['content-type'] ?? '') !== '') {
            $outgoingHeaders['content-type'] = $headers['content-type'];
        }
        $uri = (new Uri())
            ->withScheme('https')
            ->withHost($host)
            ->withPath($path)
            ->withQuery($outgoingQuery);
        $request = new Request($method, $uri, $outgoingHeaders, $body === '' ? null : $body);

        if (!$withKey) {
            try {
                $credentials = ($this->credentials)()->wait();
            } catch (\Throwable) {
                return self::error(500, 'AWS credentials unavailable');
            }
            $request = $this->signerFor($service, $hostRegion)->signRequest($request, $credentials);
        }

        try {
            $response = $this->http->send($request);
        } catch (GuzzleException $e) {
            return self::error(502, 'Amazon Location unreachable: ' . $this->reason($e));
        }

        // 5 · The answer as it came —status and body— so the package's own
        //     error handling works through the proxy. Guzzle has already
        //     decompressed it, so content-encoding is not passed back.
        $out = [];
        foreach (self::PASS_BACK as $name) {
            $value = $response->getHeaderLine($name);
            if ($value !== '') {
                $out[$name] = $value;
            }
        }
        $status = $response->getStatusCode();
        $bytes = (string) $response->getBody();

        // 6 · The style descriptor points at AWS, and with an API key AWS
        //     writes the key into every tile URL. Both are rewritten: the
        //     tiles come back through here, and the key never reaches the
        //     phone.
        if ($status >= 200 && $status < 300 && preg_match(self::DESCRIPTOR, $path) === 1) {
            $bytes = self::stripKey(str_replace(
                "https://maps.geo.{$hostRegion}.amazonaws.com",
                $this->publicUrl ?? $origin,
                $bytes,
            ));
        }
        if ($this->apiKey !== null
            && preg_match('/json|text|xml/', $out['content-type'] ?? '') === 1
            && str_contains($bytes, $this->apiKey)
        ) {
            $bytes = str_replace($this->apiKey, '', $bytes);
        }

        return [$status, $out, $bytes];
    }

    private function signerFor(string $service, string $region): SignatureV4
    {
        return $this->signers["{$service}|{$region}"] ??= new SignatureV4($service, $region);
    }

    /**
     * Why AWS couldn't be reached. Not Guzzle's message: it ends with the full
     * URL, and with an API key that URL carries the key.
     */
    private function reason(GuzzleException $e): string
    {
        $context = $e instanceof ConnectException || $e instanceof RequestException
            ? $e->getHandlerContext()
            : [];
        $reason = is_string($context['error'] ?? null) && $context['error'] !== ''
            ? $context['error']
            : 'request failed';

        return $this->apiKey === null ? $reason : str_replace($this->apiKey, '', $reason);
    }

    /**
     * The query as name/value pairs, decoded the way a browser's
     * URLSearchParams does it: `+` is a space, and repeated names are kept.
     *
     * @return list<array{0: string, 1: string}>
     */
    private static function parseQuery(string $query): array
    {
        if (str_starts_with($query, '?')) {
            $query = substr($query, 1);
        }
        $pairs = [];
        foreach (explode('&', $query) as $part) {
            if ($part === '') {
                continue;
            }
            [$name, $value] = array_pad(explode('=', $part, 2), 2, '');
            $pairs[] = [
                rawurldecode(str_replace('+', ' ', $name)),
                rawurldecode(str_replace('+', ' ', $value)),
            ];
        }

        return $pairs;
    }

    /** Removes every `key=` parameter from the URLs inside $text. */
    private static function stripKey(string $text): string
    {
        return preg_replace_callback(
            '/([?&])key=[^&"\s]*(&)?/',
            static fn (array $m): string => ($m[2] ?? '') !== '' ? $m[1] : '',
            $text,
        ) ?? $text;
    }

    /** @return array{0: int, 1: array<string, string>, 2: string} */
    private static function error(int $status, string $message): array
    {
        return [
            $status,
            ['content-type' => 'application/json'],
            json_encode(
                ['message' => $message],
                JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE,
            ) ?: '{}',
        ];
    }
}
