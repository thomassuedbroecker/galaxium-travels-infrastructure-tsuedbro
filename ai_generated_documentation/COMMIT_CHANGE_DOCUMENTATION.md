# Commit Change Documentation

## Update 2026-03-03 (Inspector Protocol Stabilization)

The MCP Inspector regression (`initialize -> MCP -32601 Method not found`) was fixed by replacing custom MCP middleware auth with native FastMCP auth wiring and updating MCP E2E checks for session-aware streamable-http responses.

This cycle also refined the local manual Inspector runbook in `local-container/README.md` with:
- explicit Terminal 1/2/3 flow
- corrected UI port (`6274`)
- corrected custom header format (`Authorization: Bearer <token>`)

See:

- [`CHANGELOG_LOCAL_COMPOSE_OAUTH_SIMPLIFICATION_2026-03-03.md`](./CHANGELOG_LOCAL_COMPOSE_OAUTH_SIMPLIFICATION_2026-03-03.md)

## Update 2026-03-03 (Local Compose OAuth Hardening)

For the latest local Docker Compose OAuth hardening cycle and unified UI+REST+MCP verification flow, see:

- [`CHANGELOG_LOCAL_COMPOSE_OAUTH_2026-03-03.md`](./CHANGELOG_LOCAL_COMPOSE_OAUTH_2026-03-03.md)
- [`CHANGELOG_LOCAL_COMPOSE_OAUTH_SIMPLIFICATION_2026-03-03.md`](./CHANGELOG_LOCAL_COMPOSE_OAUTH_SIMPLIFICATION_2026-03-03.md)

Highlights of this update:

1. Added `local-container/verify-keycloak-auth-e2e.sh` as the primary one-command local auth verifier with saved reports.
2. Reduced duplicated verification logic by converting focused scripts into wrappers around the unified test suite.
3. Added `local-container/start-mcp-inspector-ui.sh` to stabilize Inspector UI startup and connection configuration.

## Suggested Commit Title

`docs(auth): clarify env-based Keycloak toggles and align Code Engine deployment + verification`

## Suggested Commit Body

```
- Keep authentication explicitly environment-driven for both services
  - booking API: AUTH_ENABLED
  - web app: OAUTH2_ENABLED
- Clarify defaults and required OIDC variables in templates and READMEs
- Add end-to-end non-compose/Code Engine Keycloak deployment guide
- Add remote auth verification script for deployed URLs
- Update Code Engine notebooks to pass auth/OIDC env vars explicitly
- Validate local compose Keycloak flow via automated verification script
```

## Why This Change

The previous behavior was easy to misinterpret outside Docker Compose.  
This update makes auth toggles explicit and documents how to reproduce the same Keycloak-protected behavior in non-compose deployments (for example IBM Cloud Code Engine).

## Scope of Changes

### Runtime Behavior

1. Web app auth remains controlled by environment variable:
   - `OAUTH2_ENABLED=false` by default
   - `OAUTH2_ENABLED=true` enforces Keycloak token usage
2. Web app fails fast when OAuth2 is enabled but required OIDC settings are missing.

### Documentation and Templates

1. Added explicit toggle semantics and required variables in templates:
   - `booking_system_rest/.env-template`
   - `galaxium-booking-web-app/.env-template`
2. Clarified compose vs non-compose behavior in docs:
   - root README
   - booking API README
   - web app README
   - local container README
3. Added dedicated non-compose deployment guide:
   - `CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`

### Deployment Notebooks

1. Updated booking API Code Engine notebook to load/pass:
   - `AUTH_ENABLED`
   - `OIDC_ISSUER`
   - `OIDC_AUDIENCE`
   - `OIDC_JWKS_URL`
2. Updated web app Code Engine notebook to load/pass:
   - `OAUTH2_ENABLED`
   - `OIDC_TOKEN_URL`
   - `OIDC_CLIENT_ID`
   - `OIDC_CLIENT_SECRET`
   - `OIDC_SCOPE`

### Verification Utilities

1. Added remote verification script:
   - `local-container/verify-keycloak-auth-remote.sh`
2. Existing compose verification script remains available:
   - `local-container/verify-keycloak-auth.sh`

## Files Changed

- `README.md`
- `booking_system_rest/.env-template`
- `booking_system_rest/README.md`
- `booking_system_rest/deployment_rest_server.ipynb`
- `galaxium-booking-web-app/.env-template`
- `galaxium-booking-web-app/README.md`
- `galaxium-booking-web-app/app/app.py`
- `galaxium-booking-web-app/deployment_web_application_server.ipynb`
- `local-container/README.md`
- `CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md` (new)
- `local-container/verify-keycloak-auth-remote.sh` (new)

## Validation Performed

1. JSON validation:
   - `python3 -m json.tool booking_system_rest/deployment_rest_server.ipynb`
   - `python3 -m json.tool galaxium-booking-web-app/deployment_web_application_server.ipynb`
2. Python syntax check:
   - `python3 -m py_compile galaxium-booking-web-app/app/app.py`
3. Shell syntax check:
   - `bash -n local-container/verify-keycloak-auth.sh`
   - `bash -n local-container/verify-keycloak-auth-remote.sh`
4. End-to-end local auth verification (compose):
   - `bash local-container/verify-keycloak-auth.sh`
   - Result: PASS
   - Verified outcomes:
     - no token => 401
     - valid Keycloak token => 200
     - web proxy endpoint => 200

## Deployment Notes

To match compose behavior outside compose, set both:

1. `AUTH_ENABLED=true` (booking API)
2. `OAUTH2_ENABLED=true` (web app)

Then configure the required OIDC endpoints and secrets as documented in `CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`.
