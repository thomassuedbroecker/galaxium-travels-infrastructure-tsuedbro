from __future__ import annotations

import unittest

from testing.webui_matrix.tests.support import (
    MCP_INITIALIZE_PAYLOAD,
    MCP_TOOLS_LIST_PAYLOAD,
    LiveVariantCase,
    assert_tool_names,
    discover_live_variants,
    extract_mcp_json,
)


class BackendContractMixin:
    def test_frontend_health_contract(self) -> None:
        assert self.VARIANT is not None

        response = self.http_client().get(self.VARIANT.frontend_health_url)
        self.assertEqual(response.status, 200, response.text)

        payload = response.json()
        self.assertEqual(payload["status"], "ok")
        self.assertEqual(payload["frontend_mode"], self.VARIANT.backend.id)
        self.assertEqual(payload["integration_mode"], self.VARIANT.expected_integration_mode)
        self.assertEqual(payload["proxy_to"], self.VARIANT.expected_proxy_to)
        self.assertTrue(payload["oauth2_enabled"])
        self.assertTrue(payload["frontend_auth_required"])
        self.assertFalse(payload["traveler_session_active"])

    def test_backend_auth_contract(self) -> None:
        assert self.VARIANT is not None

        if self.VARIANT.backend.id == "rest":
            backend_without_token = self.http_client().get(
                self.VARIANT.backend_flights_url,
                follow_redirects=False,
            )
            expected_status = 401 if self.VARIANT.oauth.backend_auth_enabled else 200
            self.assertEqual(expected_status, backend_without_token.status, backend_without_token.text)
            if expected_status == 401:
                self.assertIn("Missing bearer token", backend_without_token.text)
                if not self.VARIANT.environment.uses_vm_oauth_override:
                    return

            if expected_status == 200:
                payload = backend_without_token.json()
            else:
                token = self.traveler_token()
                backend_with_token = self.http_client().get(
                    self.VARIANT.backend_flights_url,
                    headers=self.bearer_headers(token),
                )
                self.assertEqual(200, backend_with_token.status, backend_with_token.text)
                payload = backend_with_token.json()
            self.assertIsInstance(payload, list)
            self.assertGreater(len(payload), 0)
            return

        headers = self.mcp_headers()
        without_token = self.http_client().post_json(
            self.VARIANT.mcp_endpoint_url,
            MCP_INITIALIZE_PAYLOAD,
            headers=headers,
            follow_redirects=False,
        )
        expected_status = 401 if self.VARIANT.oauth.backend_auth_enabled else 200
        self.assertEqual(expected_status, without_token.status, without_token.text)
        if self.VARIANT.oauth.backend_auth_enabled and not self.VARIANT.environment.uses_vm_oauth_override:
            return

        token = None
        if self.VARIANT.oauth.backend_auth_enabled:
            token = self.traveler_token()

        initialize = self.http_client().post_json(
            self.VARIANT.mcp_endpoint_url,
            MCP_INITIALIZE_PAYLOAD,
            headers=self.mcp_headers(token=token),
            follow_redirects=False,
        )
        self.assertEqual(200, initialize.status, initialize.text)
        initialize_payload = extract_mcp_json(initialize)
        result = initialize_payload.get("result", {})
        self.assertEqual("Booking System MCP", result.get("serverInfo", {}).get("name"))

        session_id = initialize.headers.get("Mcp-Session-Id") or initialize.headers.get("mcp-session-id")
        self.assertTrue(session_id)

        tools = self.http_client().post_json(
            self.VARIANT.mcp_endpoint_url,
            MCP_TOOLS_LIST_PAYLOAD,
            headers=self.mcp_headers(token=token, session_id=session_id),
            follow_redirects=False,
        )
        self.assertEqual(200, tools.status, tools.text)
        tools_payload = extract_mcp_json(tools)
        assert_tool_names(
            tools_payload,
            [
                "list_flights",
                "book_flight",
                "get_bookings",
                "cancel_booking",
                "register_user",
                "get_user_id",
            ],
        )


class PrepareEnvironmentMetadataMixin:
    def test_public_metadata_contract_for_prepare_environment(self) -> None:
        assert self.VARIANT is not None

        keycloak_config = self.http_client().get(self.VARIANT.keycloak_openid_configuration_url)
        self.assertEqual(200, keycloak_config.status, keycloak_config.text)
        self.assertEqual(
            self.VARIANT.keycloak_realm_url,
            keycloak_config.json()["issuer"],
        )

        if self.VARIANT.backend.id != "mcp":
            return

        auth_server = self.http_client().get(self.VARIANT.mcp_authorization_server_url)
        self.assertEqual(200, auth_server.status, auth_server.text)
        auth_payload = auth_server.json()
        self.assertEqual(self.VARIANT.keycloak_realm_url, auth_payload["issuer"])
        self.assertEqual(
            "http://{host}:8084/oauth/register".format(host=self.VARIANT.public_host),
            auth_payload["registration_endpoint"],
        )

        protected_resource = self.http_client().get(self.VARIANT.mcp_protected_resource_url)
        self.assertEqual(200, protected_resource.status, protected_resource.text)
        protected_payload = protected_resource.json()
        self.assertEqual(
            "http://{host}:8084/mcp".format(host=self.VARIANT.public_host),
            protected_payload["resource"],
        )
        self.assertIn(self.VARIANT.keycloak_realm_url, protected_payload["authorization_servers"])


_VARIANTS, _CONFIG_ERROR = discover_live_variants()

if _CONFIG_ERROR:
    class VariantSelectionError(unittest.TestCase):
        @classmethod
        def setUpClass(cls) -> None:
            raise unittest.SkipTest(_CONFIG_ERROR)
else:
    for _variant in _VARIANTS:
        _class_name = "".join(
            part.title().replace("_", "")
            for part in (
                _variant.environment.id,
                _variant.backend.id,
                _variant.oauth.id,
                "contract_test",
            )
        )
        _bases: tuple[type[object], ...] = (LiveVariantCase, BackendContractMixin)
        if _variant.environment.id == "local_machine_local_network_prepare":
            _bases = (LiveVariantCase, BackendContractMixin, PrepareEnvironmentMetadataMixin)
        globals()[_class_name] = type(
            _class_name,
            _bases,
            {"VARIANT": _variant},
        )
