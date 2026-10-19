// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// Reference proxy for nativ_maps' `ProxyCredentials`: the phone calls this
// server, this server authenticates with Amazon Location and forwards.
// The contract it implements is in doc/PROXY.md.
//
// Framework-agnostic on purpose: `server.mjs` plugs it into node:http, the
// AWS Lambda version into a Function URL, and the same function fits Express,
// Fastify or NestJS.

import { SignatureV4 } from '@smithy/signature-v4';
import { Sha256 } from '@aws-crypto/sha256-js';
import { defaultProvider } from '@aws-sdk/credential-provider-node';

/** The only hosts this proxy will ever forward to. */
const AWS_HOST =
  /^(places|routes|maps|geofencing|tracking|cp\.geofencing|cp\.tracking)\.geo\.([a-z0-9-]+)\.amazonaws\.com$/;

/** What the map renderer asks for: it sends no X-Nativ headers. */
const MAP_ASSET = /^\/v2\/(styles|tiles|glyphs|static)\//;

/** The style descriptor, whose URLs have to be rewritten. */
const DESCRIPTOR = /^\/v2\/styles\/[^/]+\/descriptor$/;

/** SigV4 signing name per host prefix; geofencing and tracking sign as `geo`. */
const SIGNING_NAME = {
  places: 'geo-places',
  routes: 'geo-routes',
  maps: 'geo-maps',
};

/** Response headers worth passing back; the rest are AWS internals. */
const PASS_BACK = ['content-type', 'cache-control', 'etag', 'x-amzn-requestid'];

/** How long Amazon Location gets to answer before it's a 502. */
const TIMEOUT_MS = 60_000;

/**
 * Creates the request handler.
 *
 * @param {object} options
 * @param {string} options.region Region for map requests, which carry no
 *   X-Nativ headers.
 * @param {(headers: Record<string, string>) => boolean | Promise<boolean>}
 *   options.authorize Your user check. Return false and nothing is forwarded.
 * @param {string} [options.apiKey] An Amazon Location API key. If set, Places,
 *   Routes and Maps use it instead of SigV4; it never reaches the phone.
 *   Geofencing and tracking always need SigV4.
 * @param {string} [options.publicUrl] The proxy's public base URL, for the
 *   style descriptor. Without it, it's taken from each request.
 * @param {() => Promise<object>} [options.credentials] AWS credentials;
 *   default: the standard chain (env vars, profile, instance/Lambda role).
 */
export function createProxy({
  region,
  authorize,
  apiKey,
  publicUrl,
  credentials = defaultProvider(),
}) {
  const signers = new Map();
  const signerFor = (service, signingRegion) => {
    const key = `${service}|${signingRegion}`;
    if (!signers.has(key)) {
      signers.set(
        key,
        new SignatureV4({
          service,
          region: signingRegion,
          credentials,
          sha256: Sha256,
        }),
      );
    }
    return signers.get(key);
  };

  /**
   * @param {object} request
   * @param {string} request.method
   * @param {string} request.path The AWS path, without the proxy's base.
   * @param {string} request.query The raw query string, with or without `?`.
   * @param {Record<string, string>} request.headers Lowercase names.
   * @param {Uint8Array} [request.body]
   * @param {string} request.origin This proxy's base URL as the client saw it.
   * @returns {Promise<{status: number, headers: Record<string, string>,
   *   body: Uint8Array}>}
   */
  return async function handle({ method, path, query, headers, body, origin }) {
    // 1 · Your user, before anything else: an unauthenticated request must
    //     not cost a cent.
    if (!(await authorize(headers))) return error(401, 'Unauthorized');

    // 2 · Where it's going. The package says it; the map renderer doesn't,
    //     and everything it asks for lives on the Maps host.
    let host = headers['x-nativ-host'];
    if (!host) {
      if (!MAP_ASSET.test(path)) return error(400, 'Missing X-Nativ-Host');
      host = `maps.geo.${headers['x-nativ-region'] || region}.amazonaws.com`;
    }
    // A header from the phone is a header anyone can forge: never forward
    // anywhere but Amazon Location.
    const match = AWS_HOST.exec(host);
    if (!match) return error(400, 'Not an Amazon Location host');
    const [, prefix, hostRegion] = match;
    const service = SIGNING_NAME[prefix] ?? 'geo';

    // 3 · The query as it came, minus any key the client may have sent.
    const params = new URLSearchParams(query);
    params.delete('key');
    const withKey = Boolean(apiKey) && service !== 'geo';
    if (withKey) params.set('key', apiKey);

    // 4 · Only what AWS needs. The app's Authorization belongs to your
    //     backend, and SigV4 puts its own.
    const outgoing = {
      method,
      protocol: 'https:',
      hostname: host,
      path,
      query: toQueryObject(params),
      headers: { host },
      body: body && body.length > 0 ? body : undefined,
    };
    if (headers['content-type']) {
      outgoing.headers['content-type'] = headers['content-type'];
    }
    let request = outgoing;
    if (!withKey) {
      try {
        request = await signerFor(service, hostRegion).sign(outgoing);
      } catch (e) {
        // No credentials, or expired ones. The detail stays in the server's
        // log; the phone only learns that this end is misconfigured.
        console.error(`nativ_maps proxy: could not sign (${e.name})`);
        return error(500, 'Could not sign the request for Amazon Location');
      }
    }

    // Sent exactly as signed: SigV4 canonicalizes the query in RFC 3986, and
    // URLSearchParams would send a space as `+`, which AWS doesn't sign.
    const url = new URL(`https://${host}${path}`);
    url.search = encodeQuery(params);
    let response;
    try {
      response = await fetch(url, {
        method,
        headers: request.headers,
        body: outgoing.body,
        // A signed request never follows a redirect anywhere else.
        redirect: 'manual',
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (e) {
      const why = e.name === 'TimeoutError' ? 'timed out' : 'unreachable';
      return error(502, `Amazon Location ${why}`);
    }

    // 5 · The answer as it came —status and body— so the package's own
    //     error handling works through the proxy. `fetch` has already
    //     decompressed it, so content-encoding is not passed back.
    const out = {};
    for (const name of PASS_BACK) {
      const value = response.headers.get(name);
      if (value) out[name] = value;
    }
    let bytes = new Uint8Array(await response.arrayBuffer());

    // 6 · The style descriptor points at AWS, and with an API key AWS writes
    //     the key into every tile URL. Both are rewritten: the tiles come
    //     back through here, and the key never reaches the phone.
    if (response.ok && DESCRIPTOR.test(path)) {
      const base = publicUrl || origin;
      const text = new TextDecoder()
        .decode(bytes)
        .replaceAll(`https://maps.geo.${hostRegion}.amazonaws.com`, base);
      bytes = new TextEncoder().encode(stripKey(text));
    }
    if (apiKey && isText(out['content-type'])) {
      const text = new TextDecoder().decode(bytes);
      if (text.includes(apiKey)) {
        bytes = new TextEncoder().encode(text.replaceAll(apiKey, ''));
      }
    }
    return { status: response.status, headers: out, body: bytes };
  };
}

/** Removes every `key=` parameter from the URLs inside [text]. */
function stripKey(text) {
  return text.replace(/([?&])key=[^&"\s]*(&)?/g, (_, sep, amp) =>
    amp ? sep : '',
  );
}

/** The query in RFC 3986, the same encoding SigV4 signs. */
function encodeQuery(params) {
  const encode = (text) =>
    encodeURIComponent(text).replace(
      /[!'()*]/g,
      (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
    );
  return [...params].map(([k, v]) => `${encode(k)}=${encode(v)}`).join('&');
}

function toQueryObject(params) {
  const query = {};
  for (const name of new Set(params.keys())) {
    const values = params.getAll(name);
    query[name] = values.length === 1 ? values[0] : values;
  }
  return query;
}

function isText(contentType = '') {
  return /json|text|xml/.test(contentType);
}

function error(status, message) {
  return {
    status,
    headers: { 'content-type': 'application/json' },
    body: new TextEncoder().encode(JSON.stringify({ message })),
  };
}
