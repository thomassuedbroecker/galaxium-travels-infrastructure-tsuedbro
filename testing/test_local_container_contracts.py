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
        # Templates that are sourced by the shell scripts use an "export" prefix
        # so the values reach the verification scripts' subprocesses.
        match = re.match(r"^(?:export\s+)?([A-Z0-9_]+)=", line)
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
                'docker compose ${COMPOSE_ENV_ARGS[@]+"${COMPOSE_ENV_ARGS[@]}"} -f "${COMPOSE_FILE}" up --build -d',
                content,
                msg=script_path,
            )

    def test_keycloak_ui_basic_auth_mcp_overlay_exists(self) -> None:
        overlay_path = LOCAL_CONTAINER_DIR / "docker_compose.mcp-ui-keycloak-basic.yaml"
        self.assertTrue(overlay_path.exists())
        content = overlay_path.read_text(encoding="utf-8")
        self.assertIn("AUTH_MODE=basic", content)
        self.assertIn("BACKEND_AUTH_MODE=basic", content)
        self.assertIn("FRONTEND_AUTH_REQUIRED=true", content)

    def test_keycloak_ui_basic_auth_mcp_verifier_uses_overlay_and_basic_env(self) -> None:
        content = _read("local-container/verify-keycloak-ui-basic-auth-mcp.sh")
        self.assertIn('BASIC_AUTH_ENV_FILE="${BASIC_AUTH_ENV_FILE:-${SCRIPT_DIR}/basic-auth.env}"', content)
        self.assertIn('load_env_file_if_present "${BASIC_AUTH_ENV_FILE}"', content)
        self.assertIn('docker_compose.mcp-ui-keycloak-basic.yaml', content)
        self.assertIn('--auth-scheme basic', content)

    def test_quickstart_documents_option_specific_env_templates(self) -> None:
        content = _read("QUICKSTART.md")
        self.assertIn("vm-client.env.template", content)
        self.assertIn("basic-auth.env.template", content)
        self.assertIn("vm-client-basic-auth.env.template", content)
        self.assertIn("docker compose --env-file local-container/basic-auth.env \\", content)
        self.assertIn("docker_compose.basic-auth-vm.yaml", content)
        self.assertIn("docker_compose.mcp-ui-keycloak-basic.yaml", content)
        self.assertIn("verify-keycloak-ui-basic-auth-mcp.sh", content)

    def test_local_container_readme_documents_option_specific_env_templates(self) -> None:
        content = _read("local-container/README.md")
        self.assertIn("vm-client.env.template", content)
        self.assertIn("basic-auth.env.template", content)
        self.assertIn("vm-client-basic-auth.env.template", content)
        self.assertIn("docker compose --env-file basic-auth.env -f docker_compose.basic-auth.yaml up --build -d", content)
        self.assertIn("docker_compose.basic-auth-vm.yaml", content)
        self.assertIn("docker_compose.mcp-ui-keycloak-basic.yaml", content)
        self.assertIn("verify-keycloak-ui-basic-auth-mcp.sh", content)

    def test_repo_readme_documents_auth_options_and_env_templates(self) -> None:
        content = _read("README.md")
        self.assertIn("shared Basic Auth", content)
        self.assertIn("Keycloak UI -> MCP Basic Auth", content)
        self.assertIn("vm-client.env.template", content)
        self.assertIn("basic-auth.env.template", content)
        self.assertIn("vm-client-basic-auth.env.template", content)
        self.assertIn("docker_compose.basic-auth-vm.yaml", content)
        self.assertIn("testing/automation/run-all-tests.sh", content)

    def test_architecture_drawio_marks_oauth_only_and_basic_auth_capable_components(self) -> None:
        content = _read("architecture/galaxim-travel-infrastructure.drawio")
        self.assertIn("OAuth option only", content)
        self.assertIn("OAuth or Basic Auth", content)
        self.assertIn("OAuth token validation or Basic Auth", content)

    def test_watsonx_note_documents_basic_auth_mcp_variant(self) -> None:
        content = _read("docs/watsonx_orchestrate_basic_auth_example_integration.md")
        self.assertIn("docker_compose.basic-auth.yaml", content)
        self.assertIn("vm-client-basic-auth.env.template", content)
        self.assertIn("--auth-scheme basic", content)
        self.assertIn("no Keycloak redirect URI setup is required", content)

    def test_manual_commandline_auth_guide_documents_oauth_and_basic_auth(self) -> None:
        content = _read("docs/manual_auth_check_using_the_commandline.md")
        self.assertIn("@modelcontextprotocol/inspector", content)
        self.assertIn("Authorization: Bearer ${ACCESS_TOKEN}", content)
        self.assertIn("Authorization: Basic ${BASIC_TOKEN}", content)
        self.assertIn("tools/list", content)
        self.assertIn("docker_compose.basic-auth.yaml", content)
        self.assertIn("docker_compose.yaml", content)
        self.assertIn("This stack does not start Keycloak.", content)
        self.assertIn("do not use `http://localhost:8086`", content)
        self.assertIn("Arguments cannot be passed to a URL-based MCP server.", content)
        self.assertIn("issue `#790`", content)

    def test_repo_docs_link_to_manual_commandline_auth_guide(self) -> None:
        repo_readme = _read("README.md")
        quickstart = _read("QUICKSTART.md")
        local_container_readme = _read("local-container/README.md")
        self.assertIn("manual_auth_check_using_the_commandline.md", repo_readme)
        self.assertIn("manual_auth_check_using_the_commandline.md", quickstart)
        self.assertIn("manual_auth_check_using_the_commandline.md", local_container_readme)

    def test_repo_aggregate_runner_includes_local_container_contract_suite(self) -> None:
        runner = _read("testing/automation/run-all-tests.sh")
        self.assertIn('bash "${SCRIPT_DIR}/run-local-container-contract-tests.sh"', runner)

    def test_local_container_contract_runner_executes_unit_suite(self) -> None:
        runner_path = TESTING_AUTOMATION_DIR / "run-local-container-contract-tests.sh"
        self.assertTrue(runner_path.exists())
        content = runner_path.read_text(encoding="utf-8")
        self.assertIn("python3 -m unittest testing.test_local_container_contracts -v", content)
        self.assertIn('LOG_FILE="${GENERATED_RESULTS_DIR}/contracts/local-container-contracts-${RUN_ID}.log"', content)

    def test_mcp_integration_runner_includes_mixed_mode_verifier(self) -> None:
        runner = _read("testing/automation/run-mcp-integration-tests.sh")
        self.assertIn('bash "${LOCAL_CONTAINER_DIR}/verify-keycloak-ui-basic-auth-mcp.sh" \\', runner)


class HrDatabaseFrontendContractTests(unittest.TestCase):
    """Contract assertions for the hr_database_frontend_java Quarkus service."""

    SERVICE_NAME = "hr_database_frontend_java"

    def _compose(self) -> str:
        return _read("local-container/docker_compose.yaml")

    def _frontend_section(self) -> str:
        compose = self._compose()
        start = compose.index(f"  {self.SERVICE_NAME}:")
        remainder = compose[start:]
        # Stop at the next service (same indentation) or top-level key.
        next_service = re.search(r"\n(?: {2})?[A-Za-z0-9_]+:\s*\n", remainder)
        return remainder[: next_service.start()] if next_service else remainder

    def test_hr_database_frontend_service_present_in_compose(self) -> None:
        self.assertIn(f"  {self.SERVICE_NAME}:", self._compose())

    def test_hr_database_frontend_port_mapping_is_8090_to_8088(self) -> None:
        # Quarkus listens on 8088 in the container; 8090 keeps the host port
        # clear of the other services in this compose file.
        self.assertIn("8090:8088", self._frontend_section())

    def test_hr_database_frontend_depends_on_hr_database(self) -> None:
        frontend_section = self._frontend_section()
        self.assertIn("depends_on", frontend_section)
        self.assertIn("hr_database", frontend_section)

    def test_hr_database_frontend_hr_backend_url_env_var_present(self) -> None:
        frontend_section = self._frontend_section()
        # java.net.URI.getHost() returns null for hosts containing underscores,
        # so the REST client base URI must use the hyphenated network alias.
        self.assertIn("HR_BACKEND_URL=http://hr-database:8081", frontend_section)

    def test_hr_database_frontend_image_tag_present(self) -> None:
        self.assertIn(f"{self.SERVICE_NAME}:1.0.0", self._compose())


class McpAccessOptionContractTests(unittest.TestCase):
    """Contract assertions for the MCP-only booking_system_mcp_* access option folders."""

    OPTIONS = {
        "booking_system_mcp_no_auth": "AUTH_MODE=none",
        "booking_system_mcp_basic_auth": "AUTH_MODE=basic",
        "booking_system_mcp_oauth2_no_implicit_flow": "AUTH_MODE=oauth2",
    }

    def test_each_option_folder_has_its_files_and_auth_mode(self) -> None:
        for folder, auth_mode in self.OPTIONS.items():
            with self.subTest(folder=folder):
                for name in ("README.md", "docker_compose.yaml", "mcp.env.template", "start.sh", "verify.sh"):
                    self.assertTrue((LOCAL_CONTAINER_DIR / folder / name).is_file(), name)
                self.assertIn(auth_mode, _read(f"local-container/{folder}/docker_compose.yaml"))

    def test_each_option_readme_has_integration_handover(self) -> None:
        for folder in self.OPTIONS:
            with self.subTest(folder=folder):
                content = _read(f"local-container/{folder}/README.md")
                self.assertIn("## Integration Handover", content)
                self.assertIn("MCP_REMOTE_SERVER_URL", content)

    def test_option_env_templates_are_gitignored_except_templates(self) -> None:
        gitignore = _read(".gitignore")
        self.assertIn("local-container/booking_system_mcp_*/*.env", gitignore)
        self.assertIn("!local-container/booking_system_mcp_*/*.env.template", gitignore)

    def test_oauth_option_pins_keycloak_issuer_to_public_url(self) -> None:
        compose = _read("local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml")
        self.assertIn("--hostname=${KEYCLOAK_PUBLIC_BASE_URL:-http://localhost:8086}", compose)
        self.assertIn("OIDC_ISSUER=${KEYCLOAK_PUBLIC_BASE_URL:-http://localhost:8086}/realms/galaxium", compose)

    def test_oauth_option_verifier_rejects_implicit_flow(self) -> None:
        verifier = _read("local-container/booking_system_mcp_oauth2_no_implicit_flow/verify.sh")
        self.assertIn("implicitFlowEnabled", verifier)
        self.assertIn('response_types_supported"] == ["code"]', verifier)

    def test_overview_doc_links_all_options(self) -> None:
        overview = _read("docs/mcp_access_options.md")
        for folder in self.OPTIONS:
            self.assertIn(f"local-container/{folder}/", overview)

    def test_overview_states_booking_system_mcp_is_the_only_mcp_service(self) -> None:
        self.assertIn(
            "Only one service is provided as MCP: `booking_system_mcp`",
            _read("docs/mcp_access_options.md"),
        )

    def test_oauth_option_realm_dir_is_configurable_and_documented(self) -> None:
        compose = _read("local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml")
        self.assertIn("${KEYCLOAK_REALM_DIR:-../keycloak/realm}:/opt/keycloak/data/import:ro", compose)
        keycloak_readme = _read("local-container/keycloak/README.md")
        self.assertIn("KEYCLOAK_REALM_DIR", keycloak_readme)
        self.assertIn('"implicitFlowEnabled": false', keycloak_readme)
        self.assertIn("aud-booking-api", keycloak_readme)


class LabsCatalogContractTests(unittest.TestCase):
    """LABS.md is a logical layer: every lab must point to files that exist, and lab.sh must match it."""

    LOCAL_LABS = ["01", "02", "03", "04", "04-vm", "05", "06", "07", "08"]
    ALL_LABS = ["L01", "L02", "L03", "L04", "L05", "L06", "L07", "L08", "L09", "L10"]
    # Files that users create from a *.template; LABS.md names them but they are not committed.
    USER_CREATED_SUFFIXES = (".env",)

    def _labs(self) -> str:
        return _read("LABS.md")

    def test_every_lab_has_a_catalog_row_and_a_section(self) -> None:
        content = self._labs()
        for lab in self.ALL_LABS:
            with self.subTest(lab=lab):
                self.assertRegex(content, rf"\| \[{lab}\]\(#{lab.lower()}-")
                self.assertRegex(content, rf"\n## {lab}: ")

    def test_quickstart_options_and_code_engine_paths_are_mapped(self) -> None:
        content = self._labs()
        for option in ("QUICKSTART Option 1", "QUICKSTART Option 2", "QUICKSTART Option 3", "QUICKSTART Option 4"):
            self.assertIn(option, content)
        self.assertIn("Code Engine Path A", content)
        self.assertIn("Code Engine Path B", content)

    def test_relative_links_point_to_existing_files(self) -> None:
        for target in re.findall(r"\]\(\./([^)#\s]+)", self._labs()):
            with self.subTest(target=target):
                self.assertTrue((REPO_ROOT / target).exists(), target)

    def test_backticked_repo_paths_exist(self) -> None:
        pattern = r"`((?:local-container|deployment|hr_database_frontend_java|hr_database_backend|docs)/[^`\s<*]+)`"
        for path in re.findall(pattern, self._labs()):
            if path.endswith(self.USER_CREATED_SUFFIXES):
                continue
            with self.subTest(path=path):
                self.assertTrue((REPO_ROOT / path).exists(), path)

    def test_lab_wrapper_lists_the_same_local_labs(self) -> None:
        wrapper = _read("local-container/lab.sh")
        match = re.search(r'^LABS="([^"]+)"', wrapper, re.MULTILINE)
        self.assertIsNotNone(match)
        self.assertEqual(match.group(1).split(), self.LOCAL_LABS)
        for lab in self.LOCAL_LABS:
            with self.subTest(lab=lab):
                self.assertIn(f"    {lab}) echo ", wrapper)

    def test_lab_wrapper_references_existing_files_only(self) -> None:
        wrapper = _read("local-container/lab.sh")
        for name in re.findall(r'"\$\{SCRIPT_DIR\}/([A-Za-z0-9_.\-/]+)"', wrapper):
            if name.endswith(self.USER_CREATED_SUFFIXES):
                continue
            with self.subTest(name=name):
                self.assertTrue((LOCAL_CONTAINER_DIR / name).exists(), name)
        for name in re.findall(r'"\$\{HR_DIR\}/([A-Za-z0-9_.\-]+)"', wrapper):
            with self.subTest(name=name):
                self.assertTrue((REPO_ROOT / "hr_database_frontend_java" / name).exists(), name)

    def test_entry_docs_link_to_labs(self) -> None:
        for doc in ("README.md", "NAVIGATOR.md", "QUICKSTART.md", "ARCHITECTURE.md"):
            with self.subTest(doc=doc):
                self.assertIn("(./LABS.md)", _read(doc))
        self.assertIn("(../LABS.md)", _read("local-container/README.md"))


if __name__ == "__main__":
    unittest.main()
