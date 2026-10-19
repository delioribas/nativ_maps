// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// The AWS Lambda adapter around the reference proxy's core.
//
// The core is imported straight from `../../node/proxy.mjs` —not copied—, so
// this proxy and the node:http one can never drift apart. `build.mjs` bundles
// both, with their dependencies, into the single file that gets deployed.
//
// It answers a Lambda Function URL, and an API Gateway HTTP API too: both
// send payload format 2.0. The variables are the same in every reference
// proxy; see doc/PROXY.md. Credentials: none. The function's execution role
// signs, through the default chain, so there is no AWS secret anywhere.

import { timingSafeEqual } from 'node:crypto';
import { createProxy } from '../../node/proxy.mjs';

const {
  PROXY_BASE_PATH = '/geo',
  PROXY_PUBLIC_URL,
  PROXY_TOKEN,
  AWS_REGION,
  ALS_API_KEY,
} = process.env;

// Fail closed, at init: Lambda reports it on every invocation, and nothing
// is ever forwarded without a user check.
if (!PROXY_TOKEN || !AWS_REGION) {
  throw new Error('PROXY_TOKEN and AWS_REGION are required.');
}

/** `/geo`, `/geo/` and `geo` all mean the same base. */
const base = `/${PROXY_BASE_PATH.replace(/^\/+|\/+$/g, '')}`.replace(/^\/$/, '');

// A shared token, to try it. In production, check your own session here:
// your JWT, your cookie, whatever your backend already uses.
const expected = Buffer.from(`Bearer ${PROXY_TOKEN}`);
const authorize = (headers) => {
  const given = Buffer.from(headers.authorization ?? '');
  return given.length === expected.length && timingSafeEqual(given, expected);
};

const handle = createProxy({
  region: AWS_REGION,
  authorize,
  apiKey: ALS_API_KEY || undefined,
  publicUrl: PROXY_PUBLIC_URL || undefined,
});

/**
 * The Lambda entry point: a payload 2.0 event in, a Function URL result out.
 *
 * @param {object} event Function URL or API Gateway HTTP API event, v2.0.
 * @returns {Promise<{statusCode: number, headers: Record<string, string>,
 *   body: string, isBase64Encoded: boolean}>}
 */
export async function handler(event) {
  const method = event.requestContext?.http?.method ?? 'GET';
  // The path as it travels on the wire. Whether the front end hands it over
  // percent-encoded or not, this yields the same thing the node:http server
  // sees, which is what the SigV4 signature has to cover.
  const pathname = new URL(`http://placeholder${event.rawPath ?? '/'}`)
    .pathname;

  if (!pathname.startsWith(`${base}/`)) return done(method, pathname, 404);

  const headers = {};
  for (const [name, value] of Object.entries(event.headers ?? {})) {
    headers[name.toLowerCase()] = value;
  }
  const body = event.body
    ? Buffer.from(event.body, event.isBase64Encoded ? 'base64' : 'utf8')
    : undefined;
  // The Function URL front end says https; only http is honored besides,
  // for local.mjs.
  const scheme = headers['x-forwarded-proto'] === 'http' ? 'http' : 'https';

  let result;
  try {
    result = await handle({
      method,
      path: pathname.slice(base.length),
      query: event.rawQueryString ?? '',
      headers,
      body,
      origin: `${scheme}://${event.requestContext?.domainName}${base}`,
    });
  } catch (e) {
    // Signing can fail before anything is sent: no role, no credentials.
    // Its name goes to the log; the phone only learns that it failed.
    console.error(`${method} ${pathname} → 500 (${e.name})`);
    return reply(500, { 'content-type': 'application/json' },
      Buffer.from('{"message":"Internal proxy error"}'));
  }
  return done(method, pathname, result.status, result.headers, result.body);
}

/** Path and status only: the query can carry user data, headers the token. */
function done(method, pathname, status, headers = {}, body = new Uint8Array()) {
  console.log(`${method} ${pathname} → ${status}`);
  return reply(status, headers, body);
}

/** JSON and text travel as text; tiles, glyphs and images as base64. */
function reply(statusCode, headers, bytes) {
  const buffer = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const text = /json|text|xml/.test(headers['content-type'] ?? '');
  return {
    statusCode,
    headers,
    body: buffer.toString(text ? 'utf8' : 'base64'),
    isBase64Encoded: !text,
  };
}
