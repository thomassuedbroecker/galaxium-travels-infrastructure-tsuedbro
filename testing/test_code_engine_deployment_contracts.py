from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def _read(relative_path: str) -> str:
    return (REPO_ROOT / relative_path).read_text(encoding="utf-8")


def _shell_assignments(relative_path: str) -> set[str]:
    assignments: set[str] = set()
    for raw_line in _read(relative_path).splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.match(r"^([A-Z0-9_]+)=", line)
        if match:
            assignments.add(match.group(1))
    return assignments


class CodeEngineDeploymentContractTests(unittest.TestCase):
    def test_deploy_template_defaults_to_basic_and_declares_runtime_configmaps(self) -> None:
        assignments = _shell_assignments("deployment/ibm-code-engine/deploy.env.template")
        self.assertIn("STACK_AUTH_MODE", assignments)
        self.assertIn("BOOKING_API_CONFIGMAP_NAME", assignments)
        self.assertIn("MCP_CONFIGMAP_NAME", assignments)
        self.assertIn("WEB_APP_CONFIGMAP_NAME", assignments)
        self.assertIn("WEB_APP_MCP_CONFIGMAP_NAME", assignments)

        content = _read("deployment/ibm-code-engine/deploy.env.template")
        self.assertIn("STACK_AUTH_MODE=basic", content)
        self.assertIn("Current preconfigured default in this folder: basic", content)

    def test_common_sh_defaults_to_basic_and_provides_configmap_helpers(self) -> None:
        content = _read("deployment/ibm-code-engine/scripts/common.sh")
        self.assertIn('local raw_mode="${1:-basic}"', content)
        self.assertIn('STACK_AUTH_MODE="$(normalize_stack_auth_mode "${STACK_AUTH_MODE:-basic}")"', content)
        self.assertIn("create_env_file()", content)
        self.assertIn("ce_upsert_configmap_from_env_lines()", content)
        self.assertIn("ce_remove_application_env_keys()", content)
        self.assertIn('--from-env-file "${env_file}"', content)

    def test_service_deploy_script_uses_env_from_configmap_for_runtime_settings(self) -> None:
        content = _read("deployment/ibm-code-engine/scripts/04-deploy-services.sh")
        self.assertIn('--env-from-configmap "${BOOKING_API_CONFIGMAP_NAME}"', content)
        self.assertIn('--env-from-configmap "${MCP_CONFIGMAP_NAME}"', content)
        self.assertIn('--env-from-configmap "${WEB_APP_CONFIGMAP_NAME}"', content)
        self.assertIn('--env-from-configmap "${WEB_APP_MCP_CONFIGMAP_NAME}"', content)
        self.assertIn("ce_upsert_configmap_from_env_lines", content)
        self.assertIn("deploy_mcp_api_basic \"${mcp_base_url}\"", content)
        self.assertIn("deploy_mcp_api_oauth2 \"${keycloak_realm_url}\" \"${jwks_url}\" \"${mcp_base_url}\"", content)
        self.assertNotIn("--env AUTH_MODE=", content)
        self.assertNotIn('--env "BACKEND_URL=', content)
        self.assertNotIn('--env "MCP_SERVER_URL=', content)

    def test_summary_script_mentions_runtime_configmaps(self) -> None:
        content = _read("deployment/ibm-code-engine/scripts/06-summary.sh")
        self.assertIn("Booking API config:", content)
        self.assertIn("MCP config:", content)
        self.assertIn("REST UI config:", content)
        self.assertIn("MCP UI config:", content)
        self.assertIn("service configmaps", content)

    def test_code_engine_readme_documents_basic_first_configmap_model(self) -> None:
        content = _read("deployment/ibm-code-engine/README.md")
        self.assertIn("preconfigured for the `basic` auth path first", content)
        self.assertIn("Code Engine configmaps for per-service non-secret runtime settings", content)
        self.assertIn("renders env files for each deployed service variant", content)
        self.assertIn("--env-from-configmap", content)
        self.assertIn("service runtime configmaps", content)

    def test_repo_aggregate_runner_includes_code_engine_contract_suite(self) -> None:
        content = _read("testing/automation/run-all-tests.sh")
        self.assertIn('bash "${SCRIPT_DIR}/run-code-engine-contract-tests.sh"', content)


if __name__ == "__main__":
    unittest.main()
