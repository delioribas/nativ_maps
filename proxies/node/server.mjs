// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// A standalone server around proxy.mjs, with nothing but node:http.
//
//   PROXY_TOKEN=… AWS_REGION=us-east-1 node server.mjs
//
// The variables are the same in every reference proxy; see doc/PROXY.md.

import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { createProxy } from './proxy.mjs';

const { PORT = '8080', PROXY_TOKEN, AWS_REGION, ALS_API_KEY } = process.env;
// Without the trailing slash: with it, the tiles would end up under `//v2`.
const PROXY_BASE_PATH = (process.env.PROXY_BASE_PATH ?? '/geo').replace(/\/+$/, '');
const PROXY_PUBLIC_URL = process.env.PROXY_PUBLIC_URL?.replace(/\/+$/, '');

if (!PROXY_TOKEN || !AWS_REGION) {
  console.error('PROXY_TOKEN and AWS_REGION are required.');
  process.exit(1);
}

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
  publicUrl: PROXY_PUBLIC_URL,
});

http
  .createServer(async (req, res) => {
    const url = new URL(req.url, 'http://placeholder');
    if (!url.pathname.startsWith(`${PROXY_BASE_PATH}/`)) {
      res.writeHead(404).end();
      return;
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const scheme = req.headers['x-forwarded-proto'] ?? 'http';

    let result;
    try {
      result = await handle({
        method: req.method,
        path: url.pathname.slice(PROXY_BASE_PATH.length),
        query: url.search,
        headers: req.headers,
        body: chunks.length > 0 ? Buffer.concat(chunks) : undefined,
        origin: `${scheme}://${req.headers.host}${PROXY_BASE_PATH}`,
      });
    } catch (e) {
      // A bug here must not take the whole server down with it.
      console.error(`nativ_maps proxy: ${e.name}`);
      result = {
        status: 500,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ message: 'Internal proxy error' }),
      };
    }

    // Path and status only: the query can carry user data, and never log
    // headers, which carry the user's token.
    console.log(`${req.method} ${url.pathname} → ${result.status}`);
    res.writeHead(result.status, result.headers);
    res.end(result.body);
  })
  .listen(Number(PORT), () => {
    console.log(`nativ_maps proxy on :${PORT}${PROXY_BASE_PATH}`);
  });
