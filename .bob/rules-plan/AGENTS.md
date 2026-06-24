# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Architecture Rules (Non-Obvious)

- **Auth is stateless and re-evaluated per request**: `auth_mode()` reads env vars on every call — there is no cached auth state. Both `booking_system_rest/auth.py` and `booking_system_mcp/auth.py` are near-identical implementations of the same pattern.

- **`AUTH_ENABLED=true` is deprecated shorthand for `AUTH_MODE=oauth2`**: New code should use `AUTH_MODE` explicitly. The legacy var is supported for backwards compat with compose configs.

- **MCP OAuth metadata is self-hosted**: `mcp_server.py` serves its own `/.well-known/oauth-authorization-server`, `/.well-known/oauth-protected-resource`, and `/oauth/register` endpoints — it does not delegate to Keycloak directly. It proxies/rewrites Keycloak URLs so MCP Inspector can discover them from the host network.

- **Seed data is not idempotent**: `seed()` deletes all rows and re-inserts on every startup. Persistent state between runs is not supported by design.

- **No shared database**: Each service (`booking_system_rest`, `booking_system_mcp`) has its own independent SQLite file. Changes to one are not visible to the other.

- **IBM Code Engine deployment uses bash + ibmcloud CLI, not Terraform or Helm**: Scripts are in `deployment/ibm-code-engine/`. Default auth mode for Code Engine is `basic` (not OAuth), unlike the local compose default which is OAuth. Plan new auth features to work in both modes.

- **Contract tests are the guard rail for documentation drift**: Any renaming of env vars, compose files, or shell scripts must be accompanied by updating the corresponding assertions in `testing/test_local_container_contracts.py` and `testing/test_code_engine_deployment_contracts.py` or the CI suite will fail.
