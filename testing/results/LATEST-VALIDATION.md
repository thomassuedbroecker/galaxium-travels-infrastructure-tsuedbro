# Latest Validation

- Summary date: `2026-10-15`
- Reviewed code: commit `af29c97` plus the MCP access option folders (`local-container/booking_system_mcp_*`)
- Host: macOS, Rancher Desktop (moby), LAN IP `192.168.2.88`
- Scope: **every supported local combination**, plus the no-Docker suites
- Result: **PASS. Every combination passed, with no failures.**

All images were rebuilt from the checkout (`docker compose -f local-container/docker_compose.yaml build`) before the Docker runs.

## No-Docker Suites (the CI Jobs)

| Suite | Command | Result |
| --- | --- | --- |
| REST unit tests | `bash testing/automation/run-rest-api-tests.sh` (pytest in the container) | 37 passed |
| Local-container + Code Engine contracts | `python3 -m unittest testing.test_local_container_contracts testing.test_code_engine_deployment_contracts` | 39 passed |
| WebUI matrix unit | `python3 -m unittest testing.webui_matrix.tests.unit.test_config` | 11 passed |
| Java HR backend (not in CI) | `mvn -B test` in `hr_database_backend_java/` (run in `maven:3.9.9-eclipse-temurin-21`) | 12 passed |
| Java HR portal (not in CI) | `mvn -B test` in `hr_database_frontend_java/` | compiles; the module has no tests |

## Compose Combinations

| # | Combination | Compose file(s) | Verification | Result |
| --- | --- | --- | --- | --- |
| 1 | Full stack, OAuth (Keycloak) | `docker_compose.yaml` | `verify-keycloak-auth-e2e.sh --with-inspector-cli` (scope `all`), `verify-keycloak-auth.sh`, `verify-keycloak-auth-mcp.sh`, `verify-keycloak-inspector-client.sh`, `mcp_test_app.py` | PASS |
| 1b | Full stack, including HR | `docker_compose.yaml` (all services) | HTTP smoke: `:8081/employees`, `:8081/jobs`, `:8090/`, `:8090/api/employees`, `:8090/api/jobs`, `:8090/q/health` all `200` | PASS |
| 2 | VM / LAN OAuth | `docker_compose.yaml` + `docker_compose.vm-oauth.yaml` (`--env-file vm-oauth.env`) | `verify-keycloak-auth-remote.sh`; MCP over the LAN IP: `401` without a token, `client_credentials` token → `initialize` + `tools/list`; metadata advertises LAN URLs; `mcp_test_app.py --token` | PASS |
| 3 | Basic Auth stack | `docker_compose.basic-auth.yaml` | `verify-basic-auth-backends.sh`, `verify-basic-auth-frontends-and-inspector.sh` | PASS |
| 3b | Basic Auth VM stack (used by the watsonx Orchestrate guide) | `docker_compose.basic-auth-vm.yaml` | Over the LAN IP: MCP `401` without credentials, session + `tools/list` with credentials; REST `/flights` `401`/`200`; web UIs `200` | PASS |
| 4 | Keycloak UI + MCP Basic Auth | `docker_compose.yaml` + `docker_compose.mcp-ui-keycloak-basic.yaml` | `verify-keycloak-ui-basic-auth-mcp.sh` | PASS |
| 5 | WebUI auth matrix (REST/MCP × OAuth modes × local/LAN) | `testing/webui_matrix/docker_compose.auth-matrix.yaml` | `run-webui-auth-matrix.sh --env-file full-matrix.env` | PASS, 55 tests, 0 skipped |
| 6 | MCP only, no auth | `booking_system_mcp_no_auth/docker_compose.yaml` | `booking_system_mcp_no_auth/verify.sh` | PASS |
| 7 | MCP only, Basic Auth | `booking_system_mcp_basic_auth/docker_compose.yaml` | `booking_system_mcp_basic_auth/verify.sh` | PASS |
| 8 | MCP only, OAuth 2.0 (localhost) | `booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml` | `booking_system_mcp_oauth2_no_implicit_flow/verify.sh` | PASS |
| 8b | MCP only, OAuth 2.0 (LAN IP) | same, with `KEYCLOAK_PUBLIC_BASE_URL` / `MCP_PUBLIC_BASE_URL` set to the LAN IP | `verify.sh`, plus token + `initialize` from a separate container (stand-in for watsonx Orchestrate) | PASS |
| 8c | MCP only, OAuth 2.0, custom realm | same, with `KEYCLOAK_REALM_DIR` pointing to a realm that adds a dedicated client | `verify.sh` with `OIDC_CLIENT_ID=wxo-booking-mcp`; password grant rejected | PASS |
| 9 | HR standalone, Python backend | `hr_database_frontend_java/docker-compose.yaml` | `:8090/api/employees`, `:8090/api/jobs` `200` (backend is internal only) | PASS |
| 10 | HR standalone, Java backend | `hr_database_frontend_java/docker-compose.java-backend.yaml` | `:8089/employees`, `:8089/jobs`, `:8090/api/employees`, `:8090/api/jobs` `200` | PASS |

Run the combinations one at a time. Several of them publish the same host ports.

## Findings During This Run

- **HR container name conflict.** The standalone HR stacks and `local-container/docker_compose.yaml` use the same fixed container names (`hr_database`, `hr_database_frontend_java`, `hr_database_backend_java`). Stopped containers left behind by a standalone HR stack make the full stack fail with `Conflict. The container name "/hr_database" is already in use`. Workaround: `bash hr_database_frontend_java/stop-hr-app.sh` (or `docker compose -f hr_database_frontend_java/<file> down`) before starting the full stack. Now documented in the READMEs.
- **Environment, not repo:** after a Rancher Desktop glitch (two Lima host agents), no published port was reachable from the Mac. Restarting Rancher Desktop (`rdctl shutdown` and `rdctl start`) fixed it.
- Keycloak logs a deprecation warning for `KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` (the newer names are `KC_BOOTSTRAP_ADMIN_*`). This is harmless on Keycloak 26.0.

Not run: IBM Code Engine deployment (cloud) and Podman.

## Historical Evidence

Earlier runs (March and September 2026) are listed in [testing/README.md](../README.md#current-verified-state). Generated artifacts are not tracked in Git.
