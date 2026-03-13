from __future__ import annotations

import json
import os
import time
import unittest
from collections.abc import Iterable

from testing.webui_matrix.webui_test_matrix.auth import fetch_password_token
from testing.webui_matrix.webui_test_matrix.compose import ComposeStack, docker_available
from testing.webui_matrix.webui_test_matrix.config import ConfigurationError, build_selected_variants_from_env
from testing.webui_matrix.webui_test_matrix.http_client import HttpClient, HttpResponse
from testing.webui_matrix.webui_test_matrix.models import Variant


MCP_INITIALIZE_PAYLOAD = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-11-25",
        "capabilities": {},
        "clientInfo": {
            "name": "webui-auth-matrix",
            "version": "1.0.0",
        },
    },
}

MCP_TOOLS_LIST_PAYLOAD = {
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {},
}

MCP_ACCEPT_HEADER = "application/json, text/event-stream"


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def discover_live_variants() -> tuple[list[Variant], str | None]:
    try:
        return build_selected_variants_from_env(), None
    except ConfigurationError as exc:
        return [], str(exc)


def wait_for_url(client: HttpClient, url: str, *, expected_status: int = 200, timeout_seconds: float = 180.0) -> None:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            response = client.get(url, follow_redirects=False)
        except Exception:
            time.sleep(2.0)
            continue
        if response.status == expected_status:
            return
        time.sleep(2.0)
    raise AssertionError(f"timed out waiting for {url} to return HTTP {expected_status}")


def wait_for_variant_ready(variant: Variant) -> None:
    client = HttpClient()
    wait_for_url(client, variant.keycloak_openid_configuration_url)
    wait_for_url(client, variant.backend_health_url)
    wait_for_url(client, variant.frontend_health_url)
    if variant.backend.id == "mcp":
        wait_for_url(client, variant.mcp_authorization_server_url)


def extract_mcp_json(response: HttpResponse) -> dict[str, object]:
    body = response.text.strip()
    if not body:
        raise AssertionError("MCP response body is empty")

    try:
        payload = json.loads(body)
        if isinstance(payload, dict):
            return payload
    except json.JSONDecodeError:
        pass

    data_lines = []
    for line in body.splitlines():
        if line.startswith("data: "):
            data_lines.append(line[6:])
    if not data_lines:
        raise AssertionError(f"MCP response did not contain JSON payload: {body}")

    payload = json.loads(data_lines[-1])
    if not isinstance(payload, dict):
        raise AssertionError(f"MCP payload must be a JSON object: {payload}")
    return payload


def assert_tool_names(payload: dict[str, object], expected_names: Iterable[str]) -> None:
    result = payload.get("result")
    if not isinstance(result, dict):
        raise AssertionError(f"MCP tools/list payload missing result object: {payload}")
    tools = result.get("tools")
    if not isinstance(tools, list):
        raise AssertionError(f"MCP tools/list payload missing tools array: {payload}")

    actual_names = {tool.get("name") for tool in tools if isinstance(tool, dict)}
    missing_names = [name for name in expected_names if name not in actual_names]
    if missing_names:
        raise AssertionError(f"MCP tools/list missing tools: {', '.join(missing_names)}")


def login_session(client: HttpClient, variant: Variant) -> HttpResponse:
    response = client.post_form(
        variant.frontend_login_url,
        {
            "username": variant.credentials.traveler_username,
            "password": variant.credentials.traveler_password,
            "next": "/",
        },
        follow_redirects=True,
    )
    if response.status != 200:
        raise AssertionError(
            "frontend login failed for {variant}: {status} {body}".format(
                variant=variant.slug,
                status=response.status,
                body=response.text,
            )
        )
    return response


class LiveVariantCase(unittest.TestCase):
    VARIANT: Variant | None = None
    stack: ComposeStack | None = None

    @classmethod
    def setUpClass(cls) -> None:
        super().setUpClass()
        if cls.VARIANT is None:
            raise unittest.SkipTest("base class only")

        if not _as_bool(os.getenv("WEBUI_TEST_RUN_DOCKER"), default=False):
            raise unittest.SkipTest("set WEBUI_TEST_RUN_DOCKER=1 to run docker-backed integration tests")

        available, message = docker_available()
        if not available:
            raise unittest.SkipTest(message)

        cls.stack = ComposeStack(cls.VARIANT)
        try:
            cls.stack.up()
            wait_for_variant_ready(cls.VARIANT)
        except Exception as exc:
            logs = cls.stack.logs()
            raise AssertionError(
                "failed to start stack for {variant}: {error}\n{logs}".format(
                    variant=cls.VARIANT.slug,
                    error=exc,
                    logs=logs,
                )
            ) from exc

    @classmethod
    def tearDownClass(cls) -> None:
        try:
            if cls.stack and not _as_bool(os.getenv("WEBUI_TEST_KEEP_STACK"), default=False):
                cls.stack.down()
        finally:
            super().tearDownClass()

    def http_client(self) -> HttpClient:
        return HttpClient()

    def bearer_headers(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    def mcp_headers(self, token: str | None = None, session_id: str | None = None) -> dict[str, str]:
        headers = {
            "Accept": MCP_ACCEPT_HEADER,
            "MCP-Protocol-Version": "2025-11-25",
        }
        if token:
            headers["Authorization"] = f"Bearer {token}"
        if session_id:
            headers["MCP-Session-Id"] = session_id
        return headers

    def traveler_token(self) -> str:
        if self.VARIANT is None:
            raise AssertionError("variant is not initialized")
        return fetch_password_token(self.http_client(), self.VARIANT)
