from __future__ import annotations

import json
from dataclasses import dataclass
from http.cookiejar import CookieJar
from typing import Any
from urllib import error, parse, request


class NoRedirectHandler(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        return None


@dataclass(frozen=True)
class HttpResponse:
    url: str
    status: int
    headers: dict[str, str]
    body: bytes

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")

    def json(self) -> Any:
        return json.loads(self.text)


class HttpClient:
    def __init__(self) -> None:
        self._cookie_jar = CookieJar()
        self._follow_redirects_opener = request.build_opener(
            request.HTTPCookieProcessor(self._cookie_jar)
        )
        self._no_redirect_opener = request.build_opener(
            request.HTTPCookieProcessor(self._cookie_jar),
            NoRedirectHandler(),
        )

    def request(
        self,
        method: str,
        url: str,
        *,
        headers: dict[str, str] | None = None,
        data: bytes | None = None,
        timeout: float = 10.0,
        follow_redirects: bool = True,
    ) -> HttpResponse:
        opener = self._follow_redirects_opener if follow_redirects else self._no_redirect_opener
        req = request.Request(url, data=data, method=method.upper())
        for key, value in (headers or {}).items():
            req.add_header(key, value)
        try:
            with opener.open(req, timeout=timeout) as response:
                return HttpResponse(
                    url=response.geturl(),
                    status=response.status,
                    headers=dict(response.headers.items()),
                    body=response.read(),
                )
        except error.HTTPError as exc:
            body = exc.read()
            exc.close()
            return HttpResponse(
                url=exc.geturl(),
                status=exc.code,
                headers=dict(exc.headers.items()),
                body=body,
            )

    def get(self, url: str, *, headers: dict[str, str] | None = None, follow_redirects: bool = True) -> HttpResponse:
        return self.request(
            "GET",
            url,
            headers=headers,
            follow_redirects=follow_redirects,
        )

    def post_form(
        self,
        url: str,
        fields: dict[str, str],
        *,
        headers: dict[str, str] | None = None,
        timeout: float = 10.0,
        follow_redirects: bool = True,
    ) -> HttpResponse:
        body = parse.urlencode(fields).encode("utf-8")
        request_headers = {"Content-Type": "application/x-www-form-urlencoded"}
        request_headers.update(headers or {})
        return self.request(
            "POST",
            url,
            headers=request_headers,
            data=body,
            timeout=timeout,
            follow_redirects=follow_redirects,
        )

    def post_json(
        self,
        url: str,
        payload: Any,
        *,
        headers: dict[str, str] | None = None,
        timeout: float = 10.0,
        follow_redirects: bool = True,
    ) -> HttpResponse:
        body = json.dumps(payload).encode("utf-8")
        request_headers = {"Content-Type": "application/json"}
        request_headers.update(headers or {})
        return self.request(
            "POST",
            url,
            headers=request_headers,
            data=body,
            timeout=timeout,
            follow_redirects=follow_redirects,
        )
