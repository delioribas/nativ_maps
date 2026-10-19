<?php

// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// A plain front controller around src/Proxy.php: every request goes through
// here, whatever serves PHP.
//
//   PROXY_TOKEN=… AWS_REGION=us-east-1 php -S localhost:8080 public/index.php
//
// The variables are the same in every reference proxy; see doc/PROXY.md.

declare(strict_types=1);

use NativMaps\Proxy\Proxy;

require dirname(__DIR__) . '/vendor/autoload.php';

// The body is the AWS answer, byte for byte: a PHP warning printed into it
// would break a tile. And PHP adds headers of its own —a Content-Type when
// there is none, a charset to any text/* one, X-Powered-By—; the proxy sends
// only what AWS sent.
ini_set('display_errors', '0');
ini_set('default_mimetype', '');
ini_set('default_charset', '');
header_remove('X-Powered-By');

$basePath = getenv('PROXY_BASE_PATH');
$basePath = $basePath === false ? '/geo' : $basePath;
$token = (string) getenv('PROXY_TOKEN');
$region = (string) getenv('AWS_REGION');

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
// Path and query raw, from REQUEST_URI: `$_GET` would collapse repeated
// parameters, and a decoded path would no longer be the one AWS signs.
$requestUri = $_SERVER['REQUEST_URI'] ?? '/';
$cut = strpos($requestUri, '?');
$path = removeDotSegments($cut === false ? $requestUri : substr($requestUri, 0, $cut));
$query = $cut === false ? '' : substr($requestUri, $cut);

if ($token === '' || $region === '') {
    error_log('PROXY_TOKEN and AWS_REGION are required.');
    send(500, ['content-type' => 'application/json'], '{"message":"PROXY_TOKEN and AWS_REGION are required."}');
    return;
}

if (!str_starts_with($path, "{$basePath}/")) {
    send(404, [], '');
    return;
}

$headers = [];
foreach (getallheaders() as $name => $value) {
    $headers[strtolower((string) $name)] = (string) $value;
}

// A shared token, to try it. In production, check your own session here:
// your JWT, your cookie, whatever your backend already uses.
$expected = "Bearer {$token}";
$authorize = static fn (array $headers): bool => hash_equals($expected, $headers['authorization'] ?? '');

$proxy = new Proxy(
    region: $region,
    authorize: $authorize,
    apiKey: getenv('ALS_API_KEY') ?: null,
    publicUrl: getenv('PROXY_PUBLIC_URL') ?: null,
);

$https = !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';
$scheme = $headers['x-forwarded-proto'] ?? ($https ? 'https' : 'http');

[$status, $responseHeaders, $body] = $proxy->handle(
    $method,
    substr($path, strlen($basePath)),
    $query,
    $headers,
    (string) file_get_contents('php://input'),
    "{$scheme}://" . ($headers['host'] ?? '') . $basePath,
);

send($status, $responseHeaders, $body);

// Path and status only: the query can carry user data, and never log
// headers, which carry the user's token.
error_log("{$method} {$path} → {$status}");

/** @param array<string, string> $headers */
function send(int $status, array $headers, string $body): void
{
    http_response_code($status);
    foreach ($headers as $name => $value) {
        header("{$name}: {$value}");
    }
    echo $body;
}

/**
 * Resolves `.` and `..` (also percent-encoded) the way any URL parser does
 * —Node's included—, so `/geo/../x` is not taken for a path under `/geo/`.
 */
function removeDotSegments(string $path): string
{
    $segments = explode('/', str_replace('\\', '/', $path));
    $last = count($segments) - 1;
    $out = [];
    foreach ($segments as $i => $segment) {
        $lower = strtolower($segment);
        $isDot = $lower === '.' || $lower === '%2e';
        $isDotDot = in_array($lower, ['..', '.%2e', '%2e.', '%2e%2e'], true);
        if ($isDotDot && count($out) > 1) {
            array_pop($out);
        }
        if ($isDot || $isDotDot) {
            if ($i === $last) {
                $out[] = '';
            }
            continue;
        }
        $out[] = $segment;
    }

    return implode('/', $out);
}
