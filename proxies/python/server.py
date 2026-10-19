# Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
#
# A standalone server around proxy.py, with nothing but the standard library.
#
#   PROXY_TOKEN=… AWS_REGION=us-east-1 python server.py
#
# The variables are the same in every reference proxy; see doc/PROXY.md.

from __future__ import annotations

import contextlib
import errno
import os
import signal
import socket
import socketserver
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

from proxy import ProxyResponse, bearer_token, create_proxy, encode_path

# Node keeps only the first of these when a client repeats them and joins the
# rest with ", " (cookies with "; "). The same here, so a repeated header
# means the same thing to every reference proxy.
_FIRST_ONLY = {
    "age", "authorization", "content-length", "content-type", "etag",
    "expires", "from", "host", "if-modified-since", "if-unmodified-since",
    "last-modified", "location", "max-forwards", "proxy-authorization",
    "referer", "retry-after", "server", "user-agent",
}


def _headers(message) -> dict:
    out: dict = {}
    for name, value in message.items():
        name = name.lower()
        if name not in out:
            out[name] = value
        elif name not in _FIRST_ONLY:
            out[name] += ("; " if name == "cookie" else ", ") + value
    return out


def make_handler(handle, base_path: str):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"  # keep-alive: MapLibre asks for many tiles
        timeout = 30  # an idle keep-alive connection is closed after this

        def _serve(self):
            try:
                target = urlsplit(self.path)
            except ValueError:
                return self._send(ProxyResponse(400, {}, b""), close=True)
            # http.server decodes the request line as latin-1: back to bytes.
            path = encode_path(target.path.encode("latin-1"))
            if not path.startswith(f"{base_path}/"):
                return self._send(ProxyResponse(404, {}, b""), close=True)
            try:
                body = self._read_body()
            except ValueError:
                return self._send(ProxyResponse(400, {}, b""), close=True)
            scheme = self.headers.get("x-forwarded-proto") or "http"
            host = self.headers.get("host") or f"localhost:{self.server.server_port}"

            try:
                result = handle(
                    method=self.command,
                    path=path[len(base_path):],
                    query=target.query.encode("latin-1").decode("utf-8", "replace"),
                    headers=_headers(self.headers),
                    body=body or None,
                    origin=f"{scheme}://{host}{base_path}",
                )
            except Exception as e:
                print(f"{type(e).__name__} on {self.command} {path}", file=sys.stderr, flush=True)
                result = ProxyResponse(
                    500, {"content-type": "application/json"}, b'{"message":"Internal error"}'
                )

            # Path and status only: the query can carry user data, and never
            # log headers, which carry the user's token.
            print(f"{self.command} {path} → {result.status}", flush=True)
            self._send(result)

        def _read_body(self) -> bytes:
            if "chunked" in (self.headers.get("transfer-encoding") or "").lower():
                chunks = []
                while True:
                    size = int(self.rfile.readline(65537).split(b";")[0].strip(), 16)
                    if size == 0:
                        while self.rfile.readline(65537) not in (b"\r\n", b"\n", b""):
                            pass  # trailers
                        return b"".join(chunks)
                    chunks.append(self.rfile.read(size))
                    self.rfile.readline()
            length = int(self.headers.get("content-length") or 0)
            if length < 0:
                raise ValueError("negative Content-Length")
            return self.rfile.read(length) if length else b""

        def _send(self, result: ProxyResponse, close: bool = False):
            self.send_response(result.status)
            for name, value in result.headers.items():
                self.send_header(name, value)
            bodiless = result.status < 200 or result.status in (204, 304)
            if not bodiless:
                self.send_header("Content-Length", str(len(result.body)))
            if close:
                self.send_header("Connection", "close")
            self.end_headers()
            if not bodiless and self.command != "HEAD":
                self.wfile.write(result.body)

        do_GET = do_HEAD = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = _serve

        def version_string(self):
            return "nativ-maps-proxy"  # not the Python version

        def log_message(self, format, *args):
            pass  # the default line has the query string in it

    return Handler


class _Server(ThreadingHTTPServer):
    """IPv6 and IPv4 on the same port, like Node's `listen(port)`."""

    address_family = socket.AF_INET6

    def server_bind(self):
        with contextlib.suppress(OSError):
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        socketserver.TCPServer.server_bind(self)  # skips a reverse DNS lookup
        self.server_name, self.server_port = "localhost", self.server_address[1]

    def handle_error(self, request, client_address):
        # The renderer cancels the tiles it no longer needs: not an error.
        if not isinstance(sys.exc_info()[1], ConnectionError):
            super().handle_error(request, client_address)


class _Server4(_Server):
    address_family = socket.AF_INET


def main():
    env = os.environ
    token, region = env.get("PROXY_TOKEN"), env.get("AWS_REGION")
    if not token or not region:
        print("PROXY_TOKEN and AWS_REGION are required.", file=sys.stderr)
        sys.exit(1)
    port = int(env.get("PORT") or "8080")
    base_path = env.get("PROXY_BASE_PATH", "/geo")

    # A shared token, to try it. In production, check your own session here:
    # your JWT, your cookie, whatever your backend already uses.
    handle = create_proxy(
        region=region,
        authorize=bearer_token(token),
        api_key=env.get("ALS_API_KEY") or None,
        public_url=env.get("PROXY_PUBLIC_URL") or None,
    )
    handler = make_handler(handle, base_path)
    try:
        server = _Server(("::", port), handler)
    except OSError as e:  # no IPv6 here (some containers)
        if e.errno not in (errno.EAFNOSUPPORT, errno.EADDRNOTAVAIL):
            raise
        server = _Server4(("", port), handler)

    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    print(f"nativ_maps proxy on :{port}{base_path}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
