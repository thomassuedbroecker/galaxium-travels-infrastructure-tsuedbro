from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
LOCAL_CONTAINER_DIR = REPO_ROOT / "local-container"
TESTING_AUTOMATION_DIR = REPO_ROOT / "testing" / "automation"


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


class LocalContainerContractTests(unittest.TestCase):
    def test_vm_client_oauth_template_contains_only_oauth_variables(self) -> None:
        self.assertTrue((LOCAL_CONTAINER_DIR / "vm-client.env.template").exists())
        self.assertEqual(
            _shell_assignments("local-container/vm-client.env.template"),
            {"KEYCLOAK_BASE_URL", "KEYCLOAK_TOKEN_URL", "MCP_SERVER_URL"},
        )

    def test_vm_client_basic_auth_template_contains_only_basic_auth_variables(self) -> None:
        self.assertTrue((LOCAL_CONTAINER_DIR / "vm-client-basic-auth.env.template").exists())
        self.assertEqual(
            _shell_assignments("local-container/vm-client-basic-auth.env.template"),
            {"MCP_SERVER_URL", "BASIC_AUTH_USERNAME", "BASIC_AUTH_PASSWORD"},
        )

    def test_basic_auth_env_template_contains_shared_basic_auth_credentials(self) -> None:
        self.assertTrue((LOCAL_CONTAINER_DIR / "basic-auth.env.template").exists())
        self.assertEqual(
            _shell_assignments("local-container/basic-auth.env.template"),
            {"BASIC_AUTH_USERNAME", "BASIC_AUTH_PASSWORD"},
        )

    def test_basic_auth_scripts_load_default_basic_auth_env_file(self) -> None:
        script_paths = [
            "local-container/verify-basic-auth-backends.sh",
            "local-container/verify-basic-auth-frontends-and-inspector.sh",
            "local-container/start-mcp-inspector-ui.sh",
        ]
        for script_path in script_paths:
            content = _read(script_path)
            self.assertIn(
                'BASIC_AUTH_ENV_FILE="${BASIC_AUTH_ENV_FILE:-${SCRIPT_DIR}/basic-auth.env}"',
                content,
                msg=script_path,
            )
            self.assertIn(
                'load_env_file_if_present "${BASIC_AUTH_ENV_FILE}"',
                content,
                msg=script_path,
            )

    def test_basic_auth_verifiers_pass_basic_auth_env_file_to_compose_when_present(self) -> None:
        script_paths = [
            "local-container/verify-basic-auth-backends.sh",
            "local-container/verify-basic-auth-frontends-and-inspector.sh",
        ]
        for script_path in script_paths:
            content = _read(script_path)
            self.assertIn(
                'COMPOSE_ENV_ARGS=(--env-file "${BASIC_AUTH_ENV_FILE}")',
                content,
                msg=script_path,
            )
            self.assertIn(
                'docker compose "${COMPOSE_ENV_ARGS[@]}" -f "${COMPOSE_FILE}" up --build -d',
                content,
                msg=script_path,
            )

    def test_quickstart_documents_option_specific_env_templates(self) -> None:
        content = _read("QUICKSTART.md")
        self.assertIn("vm-client.env.template", content)
        self.assertIn("basic-auth.env.template", content)
        self.assertIn("vm-client-basic-auth.env.template", content)
        self.assertIn("docker compose --env-file local-container/basic-auth.env \\", content)

    def test_local_container_readme_documents_option_specific_env_templates(self) -> None:
        content = _read("local-container/README.md")
        self.assertIn("vm-client.env.template", content)
        self.assertIn("basic-auth.env.template", content)
        self.assertIn("vm-client-basic-auth.env.template", content)
        self.assertIn("docker compose --env-file basic-auth.env -f docker_compose.basic-auth.yaml up --build -d", content)

    def test_repo_readme_documents_auth_options_and_env_templates(self) -> None:
        content = _read("README.md")
        self.assertIn("shared Basic Auth", content)
        self.assertIn("vm-client.env.template", content)
        self.assertIn("basic-auth.env.template", content)
        self.assertIn("vm-client-basic-auth.env.template", content)
        self.assertIn("testing/automation/run-all-tests.sh", content)

    def test_architecture_drawio_marks_oauth_only_and_basic_auth_capable_components(self) -> None:
        content = _read("architecture/galaxim-travel-infrastructure.drawio")
        self.assertIn("OAuth option only", content)
        self.assertIn("OAuth or Basic Auth", content)
        self.assertIn("OAuth token validation or Basic Auth", content)

    def test_repo_aggregate_runner_includes_local_container_contract_suite(self) -> None:
        runner = _read("testing/automation/run-all-tests.sh")
        self.assertIn('bash "${SCRIPT_DIR}/run-local-container-contract-tests.sh"', runner)

    def test_local_container_contract_runner_executes_unit_suite(self) -> None:
        runner_path = TESTING_AUTOMATION_DIR / "run-local-container-contract-tests.sh"
        self.assertTrue(runner_path.exists())
        content = runner_path.read_text(encoding="utf-8")
        self.assertIn("python3 -m unittest testing.test_local_container_contracts -v", content)
        self.assertIn('LOG_FILE="${GENERATED_RESULTS_DIR}/contracts/local-container-contracts-${RUN_ID}.log"', content)


if __name__ == "__main__":
    unittest.main()
