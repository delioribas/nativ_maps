// Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
//
// The Lambda, on your machine. Each HTTP request becomes the event a Function
// URL would send (payload 2.0), goes to the BUILT handler —`dist/index.mjs`,
// the very file that gets deployed— and the result is written back the way
// the Function URL front end would: base64 bodies decoded, errors as 502.
//
//   npm run build
//   PORT=8086 PROXY_TOKEN=… AWS_REGION=us-east-1 node local.mjs
//
// It is not part of the deployment: only dist/ is.

import http from 'node:http';
import { randomUUID } from 'node:crypto';

const { PORT = '8086' } = process.env;

/** Function URLs refuse responses over 6 MB; base64 counts toward it. */
const MAX_RESPONSE = 6 * 1024 * 1024;

/** Bodies the Function URL hands over as text; everything else, base64. */
const TEXT_BODY = /json|text|xml|javascript|x-www-form-urlencoded/;

let handler;
try {
  ({ handler } = await import('./dist/index.mjs'));
} catch (e) {
  console.error(
    e.code === 'ERR_MODULE_NOT_FOUND'
      ? 'dist/index.mjs not found: run `npm run build` first.'
      : `The handler failed to start: ${e.message}`,
  );
  process.exit(1);
}

http
  .createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks);
    const event = toEvent(req, body);

    let result;
    try {
      result = await handler(event, { awsRequestId: event.requestContext.requestId });
    } catch (e) {
      // What a Function URL answers when the function throws.
      console.error(`handler threw: ${e.name}: ${e.message}`);
      res.writeHead(502, { 'content-type': 'application/json' });
      res.end('{"Message":"Internal Server Error"}');
      return;
    }
    if (Buffer.byteLength(JSON.stringify(result)) > MAX_RESPONSE) {
      console.error(`${req.method} ${event.rawPath}: response over 6 MB → 502`);
      res.writeHead(502, { 'content-type': 'application/json' });
      res.end('{"Message":"Internal Server Error"}');
      return;
    }
    res.writeHead(result.statusCode ?? 200, result.headers ?? {});
    res.end(
      result.body
        ? Buffer.from(result.body, result.isBase64Encoded ? 'base64' : 'utf8')
        : undefined,
    );
  })
  .listen(Number(PORT), () => {
    console.log(`nativ_maps Lambda proxy, locally, on http://localhost:${PORT}`);
  });

/** The event a Lambda Function URL would build for this request. */
function toEvent(req, body) {
  const url = new URL(req.url, 'http://placeholder');
  const headers = {};
  for (const [name, value] of Object.entries(req.headers)) {
    headers[name] = Array.isArray(value) ? value.join(',') : value;
  }
  // The Function URL moves cookies out of the headers…
  const cookies = headers.cookie?.split(/;\s*/);
  delete headers.cookie;
  // …and adds these. Here it's plain http, which the handler honors so the
  // style descriptor points back at this server.
  headers['x-forwarded-proto'] = 'http';
  headers['x-forwarded-port'] = PORT;
  headers['x-forwarded-for'] = req.socket.remoteAddress ?? '127.0.0.1';

  const text = TEXT_BODY.test(headers['content-type'] ?? '');
  const now = new Date();
  return {
    version: '2.0',
    routeKey: '$default',
    rawPath: url.pathname,
    rawQueryString: url.search.slice(1),
    ...(cookies ? { cookies } : {}),
    headers,
    ...(url.search
      ? { queryStringParameters: Object.fromEntries(url.searchParams) }
      : {}),
    requestContext: {
      accountId: 'anonymous',
      apiId: 'local',
      domainName: headers.host,
      domainPrefix: 'local',
      http: {
        method: req.method,
        path: url.pathname,
        protocol: `HTTP/${req.httpVersion}`,
        sourceIp: headers['x-forwarded-for'],
        userAgent: headers['user-agent'] ?? '',
      },
      requestId: randomUUID(),
      routeKey: '$default',
      stage: '$default',
      time: now.toISOString(),
      timeEpoch: now.getTime(),
    },
    ...(body.length > 0
      ? {
          body: body.toString(text ? 'utf8' : 'base64'),
          isBase64Encoded: !text,
        }
      : { isBase64Encoded: false }),
  };
}
