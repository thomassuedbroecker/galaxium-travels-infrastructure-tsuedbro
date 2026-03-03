# Changelog: Local Compose OAuth Simplification + Inspector UX Stabilization (2026-03-03)

## Summary

This iteration simplifies local OAuth validation and improves troubleshooting visibility:

1. One canonical test engine (`verify-keycloak-auth-e2e.sh`) with scopes.
2. Saved test results (`.md`, `.json`, `.log`) for each run.
3. Focused scripts reduced to wrappers to remove duplicated logic.
4. Added deterministic Inspector UI launcher with generated connection config.
5. Added `local-container/test-results/` to `.gitignore` to avoid report artifacts polluting git status.
6. Hardened MCP OAuth discovery compatibility for Inspector OAuth mode.

## What Changed

### 1. Unified test execution and reduced duplicated code

- Reworked `local-container/verify-keycloak-auth-e2e.sh` into a scoped test suite:
  - `--scope all` (default): UI + REST + MCP
  - `--scope ui-rest`: UI + REST only
  - `--scope mcp`: MCP protocol checks only
  - `--with-inspector-cli`: optional Inspector CLI validation layer
- Existing scripts were simplified to wrappers:
  - `local-container/verify-keycloak-auth.sh`
  - `local-container/verify-keycloak-auth-mcp.sh`

### 2. Defined test cases and persistent report artifacts

The unified test suite now executes and records explicit test IDs:

- `E2E-000`: environment + compose startup
- `E2E-001`: unauthenticated UI root redirects to `/login`
- `E2E-002`: unauthenticated UI API request is rejected (`401`)
- `E2E-003`: traveler login succeeds and session-backed API calls work
- `E2E-004`: REST endpoint rejects missing bearer token (`401`)
- `E2E-005`: REST endpoint accepts valid Keycloak token (`200`)
- `E2E-006`: MCP JSON-RPC rejects missing bearer token (`401`)
- `E2E-007`: MCP `initialize` + `tools/list` succeed with token (`200`)
- `E2E-008`: Keycloak Inspector client sync + verify pass
- `E2E-010`: optional Inspector CLI auth check
- `E2E-011`: shared traveler token acquisition

Saved report outputs for each run are now created in `local-container/test-results/`:

- `oauth-e2e-<scope>-<timestamp>.md`
- `oauth-e2e-<scope>-<timestamp>.json`
- `oauth-e2e-<scope>-<timestamp>.log`

### 3. Inspector UI access improvements

Added `local-container/start-mcp-inspector-ui.sh`:

- fetches traveler bearer token from running compose setup
- generates Inspector connection config file:
  - `local-container/test-results/inspector-ui-config-<timestamp>.md`
- starts Inspector with a fixed `MCP_PROXY_AUTH_TOKEN`
- prints exact connection values for UI

This avoids common failures caused by:

- using an old browser tab with stale proxy token
- opening localhost manually instead of the URL printed by Inspector
- incorrect custom header formatting

### 3a. OAuth metadata discovery compatibility hardening

To address Inspector OAuth error `Failed to discover OAuth metadata`, MCP server handling was hardened:

- CORS headers are now applied to MCP and metadata responses.
- `OPTIONS` preflight is handled with `204` for metadata and MCP paths.
- Added extra metadata route compatibility variants:
  - `/.well-known/openid-configuration/mcp`
  - `/.well-known/openid-configuration/msp`
  - `/.well-known/oauth-authorization-server/mcp`
  - `/.well-known/oauth-authorization-server/msp`
- `start-mcp-inspector-ui.sh` now performs metadata preflight validation before opening Inspector.
- Unified E2E script now includes metadata discovery test case (`E2E-009`) and sets explicit MCP `Accept` headers to avoid transport `406` negotiation failures.

### 4. Documentation updates

`local-container/README.md` now emphasizes:

1. primary one-command E2E verification
2. focused wrapper commands for UI/REST and MCP
3. report artifact locations
4. Inspector UI startup through the helper script

## Validation Notes

Recommended runtime validation on local machine:

```sh
cd local-container
bash verify-keycloak-auth-e2e.sh
```

Focused validations:

```sh
bash verify-keycloak-auth.sh
bash verify-keycloak-auth-mcp.sh
```

Inspector UI startup:

```sh
bash start-mcp-inspector-ui.sh
```

## Files Touched in this iteration

- `local-container/verify-keycloak-auth-e2e.sh` (major simplification + reporting)
- `local-container/verify-keycloak-auth.sh` (wrapper)
- `local-container/verify-keycloak-auth-mcp.sh` (wrapper)
- `local-container/start-mcp-inspector-ui.sh` (new)
- `booking_system_mcp/mcp_server.py` (CORS + metadata discovery compatibility)
- `local-container/README.md` (overview and troubleshooting refresh)
- `.gitignore` (ignore generated test reports)
