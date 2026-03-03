# Changelog: Local Compose OAuth Hardening and Unified Verification (2026-03-03)

## Summary

This change set hardens and simplifies local OAuth verification for the containerized stack so that UI, REST API, and MCP authentication can be validated together in one run.

Primary outcome:

- A single command now verifies Keycloak OAuth enforcement concurrently for:
  - `web_app` UI session flow
  - `booking_system_rest` bearer-token flow
  - `booking_system_mcp` bearer-token MCP JSON-RPC flow

## Review Findings

1. REST and MCP token validation parity is preserved.
   - Both use issuer/audience/JWKS-based JWT validation with the same environment model:
     - `AUTH_ENABLED`
     - `OIDC_ISSUER`
     - `OIDC_AUDIENCE`
     - `OIDC_JWKS_URL` (optional override)
2. Docker compose already enforces auth for all three services.
   - REST and MCP run with `AUTH_ENABLED=true`.
   - Web app runs with `OAUTH2_ENABLED=true` and `FRONTEND_AUTH_REQUIRED=true`.
3. MCP compatibility endpoints are present for local tooling.
   - `/mcp` streamable-http endpoint
   - `/msp` compatibility redirect
   - `/.well-known/*` metadata routes for OAuth discovery compatibility
4. Keycloak client drift is a practical local risk.
   - Existing remediation scripts (`sync-keycloak-inspector-client.sh`, `verify-keycloak-inspector-client.sh`) are retained and integrated into the unified E2E check.

## Auth Behavior Guarantees by Component

### UI (`web_app`)

- Unauthenticated browser access to `/` redirects to `/login`.
- Unauthenticated API calls return `401` with frontend auth challenge.
- After login, session-backed traveler calls succeed.

### REST API (`booking_system_rest`)

- Protected endpoints reject missing bearer token with `401`.
- Valid Keycloak traveler token grants access to protected endpoints.

### MCP (`booking_system_mcp`)

- Protocol requests to `/mcp` reject missing bearer token with `401`.
- Authenticated JSON-RPC calls (`initialize`, `tools/list`) succeed with `200`.

## Scripts Added or Updated

### Added

- `local-container/verify-keycloak-auth-e2e.sh`
  - One-shot end-to-end verifier for UI + REST + MCP in a single compose session.
  - Uses protocol-first MCP checks (`initialize`, `tools/list`) via direct JSON-RPC HTTP.
  - Calls Keycloak Inspector client sync/verify before runtime checks.

### Updated

- `local-container/README.md`
  - Adds primary recommended flow: `bash verify-keycloak-auth-e2e.sh`.
  - Repositions existing scripts as focused diagnostics.
  - Clarifies Inspector guidance:
    - recommended: `Custom Headers` bearer token mode
    - optional: OAuth mode after sync/verify
    - fallback: use `Custom Headers` when discovery fails

## Validation Commands

### Static validation

```sh
bash -n local-container/verify-keycloak-auth-e2e.sh
bash -n local-container/sync-keycloak-inspector-client.sh
bash -n local-container/verify-keycloak-inspector-client.sh
```

### Runtime validation (local Docker compose)

```sh
cd local-container
bash verify-keycloak-auth-e2e.sh
```

Expected high-level result:

- `PASS: Local Docker Compose OAuth enforcement verified end-to-end.`

## Known Limitations

1. Runtime verification depends on local Docker daemon availability and access permissions.
2. Keycloak in dev mode may emit non-secure cookie warnings in HTTP local environments; these are expected and not the root cause for token validation failures.
3. Inspector OAuth metadata discovery can vary by Inspector version; bearer-token header mode remains the stable fallback for local testing.

## Files in Scope

- `local-container/verify-keycloak-auth-e2e.sh` (new)
- `local-container/README.md` (updated)
- `ai_generated_documentation/COMMIT_CHANGE_DOCUMENTATION.md` (updated pointer)
