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

    def test_code_engine_scripts_are_standalone(self) -> None:
        deploy_stack = _read("deployment/ibm-code-engine/deploy-stack.sh")
        self.assertNotIn("common.sh", deploy_stack)

        script_dir = REPO_ROOT / "deployment" / "ibm-code-engine" / "scripts"
        expected_scripts = {
            "00-prereqs.sh",
            "01-project.sh",
            "02-config-and-secrets.sh",
            "02b-build-and-push-images.sh",
            "03-deploy-keycloak.sh",
            "04-deploy-services.sh",
            "05-sync-keycloak-client.sh",
            "06-summary.sh",
        }

        self.assertEqual({path.name for path in script_dir.glob("*.sh")}, expected_scripts)
        for script_path in script_dir.glob("*.sh"):
            content = script_path.read_text(encoding="utf-8")
            self.assertNotIn("common.sh", content, msg=script_path.name)
            self.assertIn('ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"', content, msg=script_path.name)

    def test_code_engine_scripts_use_section_headers(self) -> None:
        script_dir = REPO_ROOT / "deployment" / "ibm-code-engine"
        files_to_expected_sections = {
            "deploy-stack.sh": ["Variable definition section", "Execution section"],
            "scripts/00-prereqs.sh": [
                "Variable definition section",
                "Function definition section",
                "Execution section",
                "Monitoring section",
                "Test section",
            ],
            "scripts/01-project.sh": [
                "Variable definition section",
                "Environment definition section",
                "Function definition section",
                "Execution section",
            ],
            "scripts/02-config-and-secrets.sh": [
                "Variable definition section",
                "Environment definition section",
                "Function definition section",
                "Execution section",
            ],
            "scripts/02b-build-and-push-images.sh": [
                "Variable definition section",
                "Environment definition section",
                "Function definition section",
                "Execution section",
                "Monitoring section",
            ],
            "scripts/03-deploy-keycloak.sh": [
                "Variable definition section",
                "Environment definition section",
                "Function definition section",
                "Execution section",
                "Monitoring section",
            ],
            "scripts/04-deploy-services.sh": [
                "Variable definition section",
                "Environment definition section",
                "Function definition section",
                "Execution section",
                "Monitoring section",
            ],
            "scripts/05-sync-keycloak-client.sh": [
                "Variable definition section",
                "Environment definition section",
                "Function definition section",
                "Execution section",
                "Monitoring section",
                "Test section",
            ],
            "scripts/06-summary.sh": [
                "Variable definition section",
                "Environment definition section",
                "Function definition section",
                "Execution section",
                "Monitoring section",
                "Test section",
            ],
        }

        for relative_path, expected_sections in files_to_expected_sections.items():
            content = (script_dir / relative_path).read_text(encoding="utf-8")
            self.assertIn("# ************************", content, msg=relative_path)
            for section_name in expected_sections:
                self.assertIn(section_name, content, msg=f"{relative_path}: {section_name}")

    def test_deploy_stack_wrapper_runs_the_numbered_scripts(self) -> None:
        content = _read("deployment/ibm-code-engine/deploy-stack.sh")
        self.assertIn("steps=(", content)
        self.assertIn("00-prereqs.sh", content)
        self.assertIn("02b-build-and-push-images.sh", content)
        self.assertIn("05-sync-keycloak-client.sh", content)
        self.assertIn('bash "${SCRIPTS_DIR}/${step}"', content)

    def test_generated_directory_is_reserved_for_rendered_env_files(self) -> None:
        generated_ignore = _read("deployment/ibm-code-engine/generated/.gitignore")
        self.assertEqual(generated_ignore.strip(), "*\n!.gitignore")

    def test_service_deploy_script_renders_env_files_and_uses_env_from_configmap(self) -> None:
        content = _read("deployment/ibm-code-engine/scripts/04-deploy-services.sh")
        self.assertIn('GENERATED_CONFIG_DIR="${DEPLOY_DIR}/generated"', content)
        self.assertIn("config_env_file()", content)
        self.assertIn("write_env_file()", content)
        self.assertIn("upsert_configmap_from_file()", content)
        self.assertIn('--from-env-file "${env_file}"', content)
        self.assertIn('--env-from-configmap "${BOOKING_API_CONFIGMAP_NAME}"', content)
        self.assertIn('--env-from-configmap "${MCP_CONFIGMAP_NAME}"', content)
        self.assertIn('--env-from-configmap "${WEB_APP_CONFIGMAP_NAME}"', content)
        self.assertIn('--env-from-configmap "${WEB_APP_MCP_CONFIGMAP_NAME}"', content)
        self.assertIn('mkdir -p "${GENERATED_CONFIG_DIR}"', content)
        self.assertIn("deploy_mcp_api_basic \"${mcp_base_url}\"", content)
        self.assertIn("deploy_mcp_api_oauth2 \"${keycloak_realm_url}\" \"${jwks_url}\" \"${mcp_base_url}\"", content)
        self.assertNotIn("--env AUTH_MODE=", content)
        self.assertNotIn('--env "BACKEND_URL=', content)
        self.assertNotIn('--env "MCP_SERVER_URL=', content)

    def test_summary_script_mentions_runtime_configmaps(self) -> None:
        content = _read("deployment/ibm-code-engine/scripts/06-summary.sh")
        self.assertIn("Rendered config dir:", content)
        self.assertIn("Booking API config:", content)
        self.assertIn("MCP config:", content)
        self.assertIn("REST UI config:", content)
        self.assertIn("MCP UI config:", content)
        self.assertIn("service configmaps", content)
        self.assertIn("rendered env files", content)

    def test_code_engine_readme_documents_basic_first_configmap_model(self) -> None:
        content = _read("deployment/ibm-code-engine/README.md")
        self.assertIn("only supported deployment package", content)
        self.assertIn("preconfigured for the `basic` auth path first", content)
        self.assertIn("Code Engine configmaps for per-service non-secret runtime settings", content)
        self.assertIn("deploy-stack.sh", content)
        self.assertIn("self-contained", content)
        self.assertIn("without sourcing a shared helper file first", content)
        self.assertIn("generated/", content)
        self.assertIn("renders env files for each deployed service variant into `generated/`", content)
        self.assertIn("--env-from-configmap", content)
        self.assertIn("visible config artifacts", content)
        self.assertNotIn("ce-deployment", content)

    def test_repo_aggregate_runner_includes_code_engine_contract_suite(self) -> None:
        content = _read("testing/automation/run-all-tests.sh")
        self.assertIn('bash "${SCRIPT_DIR}/run-code-engine-contract-tests.sh"', content)


if __name__ == "__main__":
    unittest.main()
