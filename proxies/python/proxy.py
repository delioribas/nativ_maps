# Copyright (c) 2026 Delio Ribas. MIT License — see LICENSE.
#
# Reference proxy for nativ_maps' `ProxyCredentials`: the phone calls this
# server, this server authenticates with Amazon Location and forwards.
# The contract it implements is in doc/PROXY.md.
#
# Framework-agnostic on purpose: `server.py` plugs it into http.server, and
# the same function fits FastAPI, Flask or Django (see README.md). It mirrors
# proxies/node/proxy.mjs line by line.

from __future__ import annotations

import gzip
import hmac
import http.client
import json
import re
import threading
import urllib.error
import urllib.request
import zlib
from typing import Callable, Mapping, NamedTuple, Optional, Union
from urllib.parse import parse_qsl, quote

from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.session import get_session

#: The only hosts this proxy will ever forward to. Used with `fullmatch`.
AWS_HOST = re.compile(
    r"(places|routes|maps|geofencing|tracking|cp\.geofencing|cp\.tracking)"
    r"\.geo\.([a-z0-9-]+)\.amazonaws\.com"
)

#: What the map renderer asks for: it sends no X-Nativ headers.
MAP_ASSET = re.compile(r"/v2/(styles|tiles|glyphs|static)/")

#: The style descriptor, whose URLs have to be rewritten. Used with `fullmatch`.
DESCRIPTOR = re.compile(r"/v2/styles/[^/]+/descriptor")

#: SigV4 signing name per host prefix; geofencing and tracking sign as `geo`.
SIGNING_NAME = {"places": "geo-places", "routes": "geo-routes", "maps": "geo-maps"}

#: Response headers worth passing back; the rest are AWS internals.
PASS_BACK = ("content-type", "cache-control", "etag", "x-amzn-requestid")

#: How long to wait for Amazon Location before answering 502.
TIMEOUT_SECONDS = 60

# What a URL path can't carry as it is: the same characters WHATWG URL
# parsing (and so the Node proxy) percent-encodes. `%` is kept, so a path
# that is already encoded passes through untouched.
_PATH_SAFE = "!$%&'()*+,/:;=@[\\]^|"


class ProxyResponse(NamedTuple):
    """What to answer the phone: unpacks as `status, headers, body`."""

    status: int
    headers: dict
    body: bytes


Authorize = Callable[[Mapping[str, str]], bool]
CredentialsProvider = Callable[[], object]


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Amazon Location never redirects; a signed request is never replayed."""

    def redirect_request(self, *args, **kwargs):
        return None


_opener = urllib.request.build_opener(_NoRedirect)


def default_credentials() -> CredentialsProvider:
    """The standard AWS chain: env vars, profile, SSO, container/instance role.

    Resolved on the first signed request, not at startup, and frozen on each
    call so that refreshable credentials (roles, SSO) renew themselves.
    """
    session = get_session()
    lock = threading.Lock()
    resolved = None

    def provide():
        nonlocal resolved
        with lock:
            if resolved is None:
                resolved = session.get_credentials()
        return resolved.get_frozen_credentials() if resolved else None

    return provide


def bearer_token(token: str) -> Authorize:
    """A shared token, to try it: `Authorization: Bearer {token}`.

    In production, check your own session instead: your JWT, your cookie,
    whatever your backend already uses.
    """
    expected = f"Bearer {token}".encode()

    def authorize(headers: Mapping[str, str]) -> bool:
        given = headers.get("authorization") or ""
        try:
            raw = given.encode("latin-1")  # how HTTP servers decode headers
        except UnicodeEncodeError:
            raw = given.encode()
        return hmac.compare_digest(raw, expected)

    return authorize


def encode_path(path: Union[str, bytes]) -> str:
    """Percent-encodes what can't travel raw in a path; `%XX` is kept."""
    return quote(path, safe=_PATH_SAFE)


def create_proxy(
    *,
    region: str,
    authorize: Authorize,
    api_key: Optional[str] = None,
    public_url: Optional[str] = None,
    credentials: Optional[CredentialsProvider] = None,
):
    """Creates the request handler.

    region: region for map requests, which carry no X-Nativ headers.
    authorize: your user check, given the request headers (lowercase names).
        Return False and nothing is forwarded.
    api_key: an Amazon Location API key. If set, Places, Routes and Maps use
        it instead of SigV4; it never reaches the phone. Geofencing and
        tracking always need SigV4.
    public_url: the proxy's public base URL, for the style descriptor.
        Without it, it's taken from each request (`origin`).
    credentials: returns botocore credentials; default: the standard chain.
    """
    provide = credentials or default_credentials()

    def handle(
        *,
        method: str,
        path: Union[str, bytes],
        query: str,
        headers: Mapping[str, str],
        body: Optional[bytes] = None,
        origin: str,
    ) -> ProxyResponse:
        """One request.

        path: the AWS path, without the proxy's base (raw, not decoded).
        query: the raw query string, with or without `?`.
        origin: this proxy's base URL as the client saw it.
        """
        headers = {name.lower(): value for name, value in headers.items()}
        path = encode_path(path)

        # 1 · Your user, before anything else: an unauthenticated request
        #     must not cost a cent.
        if not authorize(headers):
            return _error(401, "Unauthorized")

        # 2 · Where it's going. The package says it; the map renderer
        #     doesn't, and everything it asks for lives on the Maps host.
        host = headers.get("x-nativ-host")
        if not host:
            if not MAP_ASSET.match(path):
                return _error(400, "Missing X-Nativ-Host")
            host = f"maps.geo.{headers.get('x-nativ-region') or region}.amazonaws.com"
        # A header from the phone is a header anyone can forge: never forward
        # anywhere but Amazon Location.
        match = AWS_HOST.fullmatch(host)
        if not match:
            return _error(400, "Not an Amazon Location host")
        prefix, host_region = match.groups()
        service = SIGNING_NAME.get(prefix, "geo")

        # 3 · The query as it came, minus any key the client may have sent.
        #     Repeated parameters stay repeated, in their order.
        params = [
            (name, value)
            for name, value in parse_qsl((query or "").removeprefix("?"), keep_blank_values=True)
            if name != "key"
        ]
        with_key = bool(api_key) and service != "geo"
        if with_key:
            params.append(("key", api_key))
        url = f"https://{host}{path}"
        if params:
            # Already in SigV4's canonical encoding, so what is signed and
            # what is sent are the same bytes.
            url += "?" + "&".join(
                f"{quote(n, safe='-_.~')}={quote(v, safe='-_.~')}" for n, v in params
            )

        # 4 · Only what AWS needs. The app's Authorization belongs to your
        #     backend, and SigV4 puts its own.
        outgoing = {"host": host}
        if headers.get("content-type"):
            outgoing["content-type"] = headers["content-type"]
        data = body if body else None
        if not with_key:
            try:
                frozen = provide()
            except Exception as e:  # expired SSO token, unreachable role…
                return _error(500, f"No AWS credentials: {type(e).__name__}")
            if frozen is None:
                return _error(500, "No AWS credentials")
            signed = AWSRequest(method=method, url=url, data=data, headers=outgoing)
            SigV4Auth(frozen, service, host_region).add_auth(signed)
            outgoing = dict(signed.headers.items())

        request = urllib.request.Request(url, data=data, headers=outgoing, method=method)
        try:
            status, response_headers, raw = _fetch(request)
        except (urllib.error.URLError, http.client.HTTPException, OSError, EOFError, zlib.error) as e:
            return _error(502, f"Amazon Location unreachable: {getattr(e, 'reason', e)}")

        # 5 · The answer as it came —status and body— so the package's own
        #     error handling works through the proxy. The body is already
        #     decompressed, so content-encoding is not passed back.
        out = {}
        for name in PASS_BACK:
            value = response_headers.get(name)
            if value:
                out[name] = value

        # 6 · The style descriptor points at AWS, and with an API key AWS
        #     writes the key into every tile URL. Both are rewritten: the
        #     tiles come back through here, and the key never reaches the
        #     phone.
        if 200 <= status < 300 and DESCRIPTOR.fullmatch(path):
            base = public_url or origin
            text = raw.decode("utf-8", "replace").replace(
                f"https://maps.geo.{host_region}.amazonaws.com", base
            )
            raw = _strip_key(text).encode()
        if api_key and _is_text(out.get("content-type")):
            text = raw.decode("utf-8", "replace")
            if api_key in text:
                raw = text.replace(api_key, "").encode()
        return ProxyResponse(status, out, raw)

    return handle


def _fetch(request):
    """Status, headers and body, for 2xx and for AWS's own errors alike."""
    try:
        response = _opener.open(request, timeout=TIMEOUT_SECONDS)
        status = response.status
    except urllib.error.HTTPError as e:
        # urllib raises on 4xx/5xx, but the error is also the response.
        response, status = e, e.code
    with response:
        headers = response.headers
        raw = response.read()
    # urllib asks for `identity`; if AWS compresses anyway, undo it here.
    encoding = (headers.get("content-encoding") or "").strip().lower()
    if encoding in ("gzip", "x-gzip"):
        raw = gzip.decompress(raw)
    elif encoding == "deflate":
        try:
            raw = zlib.decompress(raw)
        except zlib.error:
            raw = zlib.decompress(raw, -zlib.MAX_WBITS)
    return status, headers, raw


_KEY_PARAM = re.compile(r'([?&])key=[^&"\s]*(&)?')


def _strip_key(text: str) -> str:
    """Removes every `key=` parameter from the URLs inside `text`."""
    return _KEY_PARAM.sub(lambda m: m.group(1) if m.group(2) else "", text)


def _is_text(content_type: Optional[str]) -> bool:
    return bool(re.search(r"json|text|xml", content_type or ""))


def _error(status: int, message: str) -> ProxyResponse:
    body = json.dumps({"message": message}, separators=(",", ":"), ensure_ascii=False)
    return ProxyResponse(status, {"content-type": "application/json"}, body.encode())
