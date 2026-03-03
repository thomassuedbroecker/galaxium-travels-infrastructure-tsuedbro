#!/usr/bin/env python3
"""Small MCP connectivity test app for local containerized setup.

This script:
1) Acquires a Keycloak access token (docker-internal by default)
2) Calls MCP JSON-RPC initialize
3) Calls tools/list
4) Calls tools/call for list_flights (if available)
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


def _http_post_json(url: str, payload: dict[str, Any], headers: dict[str, str]) -> tuple[int, str]:
    request = urllib.request.Request(
        url=url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read().decode("utf-8")
            return response.status, body
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        return error.code, body


def _http_post_form(url: str, form: dict[str, str]) -> tuple[int, str]:
    data = urllib.parse.urlencode(form).encode("utf-8")
    request = urllib.request.Request(
        url=url,
        data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            body = response.read().decode("utf-8")
            return response.status, body
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        return error.code, body


def _token_via_docker() -> str:
    command = [
        "docker",
        "exec",
        "web_app",
        "python",
        "-c",
        (
            "import requests; "
            "r=requests.post("
            "'http://keycloak:8080/realms/galaxium/protocol/openid-connect/token', "
            "data={"
            "'grant_type':'password',"
            "'client_id':'web-app-proxy',"
            "'client_secret':'web-app-proxy-secret',"
            "'username':'demo-user',"
            "'password':'demo-user-password'"
            "}, timeout=15); "
            "r.raise_for_status(); "
            "print(r.json().get('access_token',''))"
        ),
    ]
    try:
        output = subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, timeout=25)
    except subprocess.CalledProcessError as error:
        raise RuntimeError(
            "Docker token retrieval failed:\n"
            f"{error.output}"
        ) from error
    except Exception as error:
        raise RuntimeError(f"Docker token retrieval failed: {error}") from error

    token = output.strip()
    if not token:
        raise RuntimeError("Docker token retrieval returned empty token")
    return token


def _token_via_http(
    token_url: str,
    client_id: str,
    client_secret: str,
    username: str,
    password: str,
) -> str:
    status, body = _http_post_form(
        token_url,
        {
            "grant_type": "password",
            "client_id": client_id,
            "client_secret": client_secret,
            "username": username,
            "password": password,
        },
    )
    if status != 200:
        raise RuntimeError(f"Token request failed ({status}): {body}")
    parsed = json.loads(body)
    token = (parsed.get("access_token") or "").strip()
    if not token:
        raise RuntimeError(f"Token missing in response: {body}")
    return token


def _get_token(args: argparse.Namespace) -> str:
    if args.token:
        return args.token.strip()

    if args.token_source in {"docker", "auto"}:
        try:
            token = _token_via_docker()
            print("OK: token acquired via docker exec web_app")
            return token
        except Exception as error:
            if args.token_source == "docker":
                raise
            print(f"WARN: docker token acquisition failed, trying HTTP token URL: {error}")

    token = _token_via_http(
        token_url=args.token_url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        username=args.username,
        password=args.password,
    )
    print("OK: token acquired via token URL")
    return token


def _rpc(
    mcp_url: str,
    token: str,
    request_id: int,
    method: str,
    params: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
    }
    if params is not None:
        payload["params"] = params

    status, body = _http_post_json(
        mcp_url,
        payload,
        {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "MCP-Protocol-Version": "2025-11-25",
        },
    )

    if status != 200:
        raise RuntimeError(f"{method} failed with HTTP {status}: {body}")

    try:
        parsed = json.loads(body)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"{method} returned non-JSON response: {body}") from error

    if "error" in parsed:
        raise RuntimeError(f"{method} RPC error: {json.dumps(parsed['error'])}")

    if "result" not in parsed:
        raise RuntimeError(f"{method} RPC response has no result: {body}")

    return parsed["result"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Local MCP server connectivity test app")
    parser.add_argument("--mcp-url", default="http://localhost:8084/mcp")
    parser.add_argument(
        "--token-source",
        choices=["auto", "docker", "http"],
        default="auto",
        help="How to get token when --token is not provided",
    )
    parser.add_argument(
        "--token-url",
        default="http://localhost:8080/realms/galaxium/protocol/openid-connect/token",
    )
    parser.add_argument("--client-id", default="web-app-proxy")
    parser.add_argument("--client-secret", default="web-app-proxy-secret")
    parser.add_argument("--username", default="demo-user")
    parser.add_argument("--password", default="demo-user-password")
    parser.add_argument("--token", default="", help="Use provided bearer token")
    parser.add_argument(
        "--skip-tool-call",
        action="store_true",
        help="Skip tools/call(list_flights)",
    )
    args = parser.parse_args()

    try:
        token = _get_token(args)
        print(f"OK: token length={len(token)}")

        init_result = _rpc(
            mcp_url=args.mcp_url,
            token=token,
            request_id=1,
            method="initialize",
            params={
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "local-mcp-test-app", "version": "1.0.0"},
            },
        )
        print(
            "OK: initialize",
            json.dumps(
                {
                    "protocolVersion": init_result.get("protocolVersion"),
                    "serverInfo": init_result.get("serverInfo"),
                }
            ),
        )

        tools_result = _rpc(
            mcp_url=args.mcp_url,
            token=token,
            request_id=2,
            method="tools/list",
            params={},
        )
        tools = tools_result.get("tools") or []
        names = [tool.get("name", "") for tool in tools]
        print(f"OK: tools/list -> {len(names)} tools")
        print("Tools:", ", ".join(names))

        if not args.skip_tool_call and "list_flights" in names:
            call_result = _rpc(
                mcp_url=args.mcp_url,
                token=token,
                request_id=3,
                method="tools/call",
                params={"name": "list_flights", "arguments": {}},
            )
            print("OK: tools/call(list_flights)")
            print("Result keys:", ", ".join(sorted(call_result.keys())))
        elif args.skip_tool_call:
            print("SKIP: tools/call check disabled")
        else:
            print("WARN: list_flights not found in tools/list output")

        print("PASS: MCP test app completed successfully.")
        return 0
    except Exception as error:
        print(f"FAIL: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
