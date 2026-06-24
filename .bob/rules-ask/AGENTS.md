# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Documentation Context (Non-Obvious)

- **`booking_system_mcp/app.py` is dead code**: The docstring says "Legacy FastAPI reference" and it is not used by the compose stack. The active MCP entry point is `mcp_server.py`.

- **HR database is Markdown-backed**: `HR_database/app.py` reads employee data from `data/employees.md`, a pipe-delimited Markdown table — not a SQL database.

- **Two separate web frontends**: `galaxium-booking-web-app/` proxies to the REST API; `galaxium-booking-web-app-mcp/` proxies to the MCP server. They are structurally identical but use different backend protocols.

- **Contract tests enforce documentation**: `testing/test_local_container_contracts.py` and `testing/test_code_engine_deployment_contracts.py` assert that specific strings exist in README, QUICKSTART, and shell scripts. Changing documented commands or template filenames will break these tests.

- **Multiple compose overlays**: There is not one compose file but several for different auth/deployment scenarios. The canonical default (OAuth + Keycloak) is `local-container/docker_compose.yaml`; others are overlays or standalone variants.

- **Keycloak port mapping**: Keycloak container runs on internal port 8080 but is exposed as 8086 on the host (to avoid conflict with other local services). `localhost:8086` is the host-accessible Keycloak URL.

- **`/msp` is an alias**: The MCP server accepts `/msp` in addition to `/mcp` as a 307-redirect path for Watson Orchestrate compatibility; both paths are intentional and documented.
