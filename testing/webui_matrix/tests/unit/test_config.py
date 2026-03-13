from __future__ import annotations

import os
import unittest
from unittest.mock import patch

from testing.webui_matrix.webui_test_matrix.config import (
    ConfigurationError,
    all_variants,
    build_selected_variants_from_env,
    build_variant,
)


class ConfigTests(unittest.TestCase):
    def test_all_variants_contains_expected_matrix_size(self) -> None:
        with patch.dict(os.environ, {"WEBUI_TEST_PUBLIC_HOST": "192.168.1.50"}, clear=True):
            variants = all_variants()
        self.assertEqual(len(variants), 8)

    def test_local_machine_network_defaults_to_localhost(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            variant = build_variant(
                "local_machine_network",
                "rest",
                "backend_and_ui_oauth",
            )
        self.assertEqual(variant.public_host, "localhost")
        self.assertEqual(variant.frontend_base_url, "http://localhost:8083")

    def test_local_network_prepare_requires_public_host(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ConfigurationError):
                build_variant(
                    "local_machine_local_network_prepare",
                    "mcp",
                    "backend_and_ui_oauth",
                )

    def test_local_network_prepare_uses_explicit_public_host(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            variant = build_variant(
                "local_machine_local_network_prepare",
                "mcp",
                "ui_oauth",
                public_host="192.168.1.50",
            )
        self.assertEqual(variant.keycloak_base_url, "http://192.168.1.50:8080")
        self.assertEqual(variant.compose_env["MCP_PUBLIC_BASE_URL"], "http://192.168.1.50:8084")

    def test_selected_variants_support_dimension_expansion(self) -> None:
        env = {
            "WEBUI_TEST_BACKEND_MODE": "all",
            "WEBUI_TEST_OAUTH_MODE": "all",
            "WEBUI_TEST_ENVIRONMENT": "local_machine_network",
        }
        with patch.dict(os.environ, env, clear=True):
            variants = build_selected_variants_from_env()
        self.assertEqual(len(variants), 4)

    def test_selected_variants_fail_for_invalid_backend(self) -> None:
        with patch.dict(os.environ, {"WEBUI_TEST_BACKEND_MODE": "invalid"}, clear=True):
            with self.assertRaises(ConfigurationError):
                build_selected_variants_from_env()

    def test_local_network_prepare_sets_public_issuer_and_token_urls(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            variant = build_variant(
                "local_machine_local_network_prepare",
                "mcp",
                "backend_and_ui_oauth",
                public_host="192.168.1.50",
            )
        self.assertEqual(
            variant.compose_env["MCP_BACKEND_OIDC_ISSUER"],
            "http://192.168.1.50:8080/realms/galaxium",
        )
        self.assertEqual(
            variant.compose_env["MCP_UI_OIDC_TOKEN_URL"],
            "http://192.168.1.50:8080/realms/galaxium/protocol/openid-connect/token",
        )
        self.assertEqual(
            variant.compose_env["REST_UI_OIDC_TOKEN_URL"],
            "http://192.168.1.50:8080/realms/galaxium/protocol/openid-connect/token",
        )

    def test_local_machine_network_keeps_internal_compose_issuer_and_token_urls(self) -> None:
        with patch.dict(os.environ, {}, clear=True):
            variant = build_variant(
                "local_machine_network",
                "mcp",
                "backend_and_ui_oauth",
            )
        self.assertEqual(
            variant.compose_env["MCP_BACKEND_OIDC_ISSUER"],
            "http://keycloak:8080/realms/galaxium",
        )
        self.assertEqual(
            variant.compose_env["MCP_UI_OIDC_TOKEN_URL"],
            "http://keycloak:8080/realms/galaxium/protocol/openid-connect/token",
        )
