# Start all server applications

>**Custom Docker-Compose** in watsonx Orchestrate it not official supported: https://developer.watson-orchestrate.ibm.com/developer_edition/custom_yaml
>**Important Note**: _Before starting watsonx Orchestrate Developer Edition with a custom Docker Compose file, make sure you understand every change in your configuration. The ADK doesn’t offers official support to custom Compose setups, so you’re responsible for troubleshooting any issues that arise._

* Simplified Architecture local containers in compose

![](/images/run-containers-03.png)

1. Insert followling commands

```sh
cd local-container
bash start-build-containers.sh
```

* Example output:

```sh
...
[+] Running 4/4
 ✔ Container keycloak             Created                                                                  0.0s 
 ✔ Container web_app              Created                                                                  0.0s 
 ✔ Container booking_system_rest  Created                                                                  0.0s 
 ✔ Container hr_database          Created                                                                  0.0s 
Attaching to keycloak, booking_system_rest, hr_database, web_app
web_app              |  * Serving Flask app 'app'
web_app              |  * Debug mode: on
web_app              | WARNING: This is a development server. Do not use it in a production deployment. Use a production WSGI server instead.
web_app              |  * Running on all addresses (0.0.0.0)
web_app              |  * Running on http://127.0.0.1:8083
web_app              |  * Running on http://172.18.0.2:8083
web_app              | Press CTRL+C to quit
web_app              |  * Restarting with stat
web_app              |  * Debugger is active!
web_app              |  * Debugger PIN: 626-306-471
booking_system_rest  | INFO:     Started server process [1]
booking_system_rest  | INFO:     Waiting for application startup.
booking_system_rest  | INFO:     Application startup complete.
booking_system_rest  | INFO:     Uvicorn running on http://0.0.0.0:8082 (Press CTRL+C to quit)
hr_database          | INFO:     Started server process [1]
hr_database          | INFO:     Waiting for application startup.
hr_database          | INFO:     Application startup complete.
hr_database          | INFO:     Uvicorn running on http://0.0.0.0:8081 (Press CTRL+C to quit)
...
```

The following image show the running server applications.

![](/images/run-containers-01.png)

## OAuth2/OIDC with Keycloak

The compose setup now starts a local Keycloak server for OAuth2/OIDC:

- URL: `http://localhost:8080`
- Admin user: `admin`
- Admin password: `admin`
- Realm imported at startup: `galaxium`

### Automated setup (default)

The setup is automated through realm import:

- Compose mounts [`keycloak/realm/galaxium-realm.json`](./keycloak/realm/galaxium-realm.json) into Keycloak.
- Keycloak starts with `start-dev --import-realm`.
- Realm `galaxium` and the required clients are created automatically.

Verify realm import:

```sh
curl -s http://localhost:8080/realms/galaxium/.well-known/openid-configuration
```

If this returns JSON, import worked.
If this returns `Realm does not exist`, follow the manual setup below.

### Verify End-to-End OAuth for UI + REST + MCP (Recommended)

From `local-container/` run:

```sh
bash verify-keycloak-auth-e2e.sh
```

This single command validates all three surfaces in one compose session:

1. Sync + verify Keycloak client config for Inspector OAuth compatibility.
2. UI auth enforcement (`/` redirects to `/login`, unauthenticated APIs return `401`, login enables session APIs).
3. REST auth enforcement (`/flights` returns `401` without token and `200` with Keycloak traveler token).
4. MCP auth enforcement via protocol JSON-RPC (`initialize`/`tools/list` return `401` without token and `200` with token).

If this script passes, local compose auth is working concurrently for UI, REST, and MCP.
Reports are saved automatically in `local-container/test-results/` as:
- `oauth-e2e-<scope>-<timestamp>.md`
- `oauth-e2e-<scope>-<timestamp>.json`
- `oauth-e2e-<scope>-<timestamp>.log`

Scope examples:

```sh
# UI + REST only
bash verify-keycloak-auth.sh

# MCP only (includes Inspector CLI check)
bash verify-keycloak-auth-mcp.sh
```

### Focused Checks (Optional)

From `local-container/` run:

```sh
bash verify-keycloak-auth.sh
```

This wrapper runs: `bash verify-keycloak-auth-e2e.sh --scope ui-rest`

### Verify MCP Server Auth with MCP Inspector (Local + Containerized)

From `local-container/` run:

```sh
bash verify-keycloak-auth-mcp.sh
```

This wrapper runs: `bash verify-keycloak-auth-e2e.sh --scope mcp --with-inspector-cli`

Use these focused checks when `verify-keycloak-auth-e2e.sh` fails and you want to isolate UI/REST vs MCP issues.

### MCP Test App (CLI)

Use this if you want to verify MCP connectivity without Inspector UI.

```sh
cd local-container
python3 mcp_test_app.py
```

What it does:
1. Gets a Keycloak token (prefers `docker exec web_app`).
2. Calls MCP `initialize`.
3. Calls MCP `tools/list`.
4. Calls MCP `tools/call` for `list_flights`.

Useful options:

```sh
python3 mcp_test_app.py --skip-tool-call
python3 mcp_test_app.py --token-source http
python3 mcp_test_app.py --token "<access_token>"
python3 mcp_test_app.py --mcp-url http://localhost:8084/mcp
```

### Manual MCP Inspector Test (Local)

Use this short 3-terminal flow to validate MCP auth in Inspector.

1. Terminal 1: start the full local stack:

```sh
cd local-container
bash start-build-containers.sh
```

If you changed MCP auth/discovery code, rebuild and recreate MCP first:

```sh
docker compose -f docker_compose.yaml build booking_system_mcp
docker compose -f docker_compose.yaml up -d --force-recreate booking_system_mcp
```

2. Terminal 2: start MCP Inspector UI:

```sh
bash start-mcp-inspector-ui.sh
```

Open the browser URL printed by Inspector (usually `http://localhost:6274/...`).
If you test OAuth registration in the UI, click `Open Auth Settings` there.
Use `http://localhost:6274` (not `http://localhost:62744`).

If `npx` is missing, install Node.js first:

```sh
brew install node
```

3. Terminal 3: generate the bearer token for Custom Header JSON:

```sh
TOKEN="$(
  docker exec web_app python -c 'import requests; r=requests.post("http://keycloak:8080/realms/galaxium/protocol/openid-connect/token", data={"grant_type":"password","client_id":"web-app-proxy","client_secret":"web-app-proxy-secret","username":"demo-user","password":"demo-user-password"}, timeout=10); r.raise_for_status(); print(r.json().get("access_token",""))'
)"
TOKEN="$(echo "${TOKEN}" | tr -d '\r\n')"
printf '{"Authorization":"Bearer %s"}\n' "${TOKEN}"
```

4. In Inspector UI, connect to MCP:
- Connection type: `Streamable HTTP`
- URL: `http://localhost:8084/mcp`
- Important: use `/mcp` (not `/msp`)
- Auth mode: `Custom Headers` (recommended local mode)
- Paste the JSON from terminal 3:

```json
{"Authorization":"Bearer <TOKEN>"}
```

5. Press `Connect` in Inspector UI.

6. Run `tools/list`.
Expected result: `list_flights`, `book_flight`, `get_bookings`, `cancel_booking`, `register_user`, `get_user_id`.

7. Run `tools/call` with tool name `list_flights` to verify end-to-end MCP access.

### MCP Inspector OAuth Mode (Optional)

If you use Inspector OAuth flow (instead of Custom Headers), configure:

1. MCP URL: `http://localhost:8084/mcp`
2. OAuth Client ID: `web-app-proxy`
3. OAuth Client Secret: `web-app-proxy-secret`
4. Scope: `openid profile email`

Before launching Inspector OAuth flow, sync and verify Keycloak client settings:

```sh
cd local-container
bash sync-keycloak-inspector-client.sh
bash verify-keycloak-inspector-client.sh
```

Important:
- Local realm import is configured with `standardFlowEnabled=true` and Inspector redirect URIs for `web-app-proxy`.
- If your running Keycloak was started before this change, recreate Keycloak so realm import is re-applied:

```sh
docker compose -f docker_compose.yaml down
docker compose -f docker_compose.yaml up -d --force-recreate keycloak booking_system_mcp web_app booking_system
```

Troubleshooting:
- If Inspector UI shows `Connection Error - Check if your MCP server is running and proxy token is correct`:
  1. Stop Inspector.
  2. Start again with `bash start-mcp-inspector-ui.sh`.
  3. Open the exact browser URL printed by Inspector (do not type localhost manually).
  4. Use the generated `Custom Header JSON` from the saved config file.

- If OAuth flow shows `Failed to discover OAuth metadata`:
  1. Rebuild/recreate MCP container (commands above).
  2. Run `bash start-mcp-inspector-ui.sh` and confirm metadata preflight passes.
  3. Verify these endpoints return `200`:
     - `http://localhost:8084/.well-known/oauth-protected-resource`
     - `http://localhost:8084/.well-known/oauth-authorization-server`
  4. If still failing, use `Custom Headers` mode to continue testing and inspect `booking_system_mcp` logs.

- If OAuth flow shows `Client Registration -> Load failed`:
  1. Rebuild/recreate MCP container (commands above).
  2. Run `bash start-mcp-inspector-ui.sh` and confirm client-registration preflight passes.
  3. Verify registration endpoint from metadata:
     - `curl -s http://localhost:8084/.well-known/oauth-authorization-server | jq -r .registration_endpoint`
  4. Test registration endpoint manually (expect `201`):

```sh
REG="$(curl -s http://localhost:8084/.well-known/oauth-authorization-server | jq -r .registration_endpoint)"
curl -i -X POST "${REG}" \
  -H "Content-Type: application/json" \
  -d '{"client_name":"manual-check","redirect_uris":["http://localhost:6274/oauth/callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"client_secret_post","scope":"openid profile email"}'
```

  5. If this still fails, use `Custom Headers` mode to continue testing and inspect `booking_system_mcp` logs.

- If `verify-keycloak-inspector-client.sh` reports `standardFlowEnabled expected 'true' but got 'false'`, run:

```sh
bash sync-keycloak-inspector-client.sh
bash verify-keycloak-inspector-client.sh
```

- If `verify-keycloak-inspector-client.sh` reports `client secret mismatch`, reset local Keycloak state and re-import the realm:

```sh
docker compose -f docker_compose.yaml down
docker compose -f docker_compose.yaml up -d --force-recreate keycloak web_app booking_system booking_system_mcp
bash verify-keycloak-inspector-client.sh
```

- If container logs show `POST /msp ... 404`, Inspector is pointing to the wrong path.
- The correct URL is `http://localhost:8084/mcp` (not `/msp`).
- In Inspector, remove old saved connection entries and reconnect with the URL above.
- If Inspector shows `MCP error -32602: Invalid request parameters`, switch auth mode to `Custom Headers`, clear any OAuth settings, and reconnect.
- If Inspector shows `MCP error -32601: Method not found`, rebuild/recreate MCP and restart Inspector:

```sh
docker compose -f docker_compose.yaml build booking_system_mcp
docker compose -f docker_compose.yaml up -d --force-recreate booking_system_mcp
bash start-mcp-inspector-ui.sh
```

Then remove old saved Inspector connections and reconnect to `http://localhost:8084/mcp`.
- `GET /openapi.json` returning `404` is expected for this MCP server.
- If UI, REST, or MCP checks fail in unclear ways, run the unified verifier first:

```sh
bash verify-keycloak-auth-e2e.sh
```

- If OAuth discovery fails, verify MCP metadata returns host-reachable auth URLs (not `keycloak:8080`):

```sh
curl -s http://localhost:8084/.well-known/oauth-protected-resource | jq .
curl -s http://localhost:8084/.well-known/oauth-authorization-server | jq .
```

Expected: `authorization_servers` and `issuer` use `http://localhost:8080/realms/galaxium`.
- Use MCP checks instead:

```sh
curl -i http://localhost:8084/
curl -i -X POST http://localhost:8084/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <TOKEN>" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"debug","version":"1.0"}}}'
```
- After MCP code changes, rebuild/recreate the MCP container before testing:

```sh
docker compose -f docker_compose.yaml build booking_system_mcp
docker compose -f docker_compose.yaml up -d --force-recreate booking_system_mcp
docker compose -f docker_compose.yaml logs -f booking_system_mcp
```
- Use `Custom Header JSON` for auth:

```json
{"Authorization":"Bearer <TOKEN>"}
```

- Recommended for local dev: use `Custom Headers` mode with bearer token.
- Optional: OAuth mode can work after `sync-keycloak-inspector-client.sh` and `verify-keycloak-inspector-client.sh`.
- If OAuth mode metadata discovery fails, switch back to `Custom Headers` to continue testing.

Compatibility behavior in this repo:
- `/msp` is accepted as a legacy alias and redirected to `/mcp`.
- `/.well-known/openid-configuration`
- `/.well-known/oauth-authorization-server`
- `/.well-known/oauth-protected-resource` (and `/mcp`, `/msp` variants)
are exposed on the MCP server for local Inspector discovery compatibility.

### Manual setup fallback (if import fails)

Open `http://localhost:8080/admin` and log in with:

- user: `admin`
- password: `admin`

Create the realm:

1. Create realm `galaxium`.

Create client `booking-api`:

1. Create client with `Client ID = booking-api`.
2. Set `Client authentication = On`.
3. Set `Service accounts roles = On`.
4. Set `Standard flow = Off`.
5. Set `Direct access grants = Off`.
6. Save and keep the generated client secret (or set `booking-api-secret`).

Create client `web-app-proxy`:

1. Create client with `Client ID = web-app-proxy`.
2. Set `Client authentication = On`.
3. Set `Service accounts roles = On`.
4. Set `Standard flow = On` (required for Inspector OAuth authorization-code flow).
5. Set `Direct access grants = On` (required for traveler username/password login in this demo frontend).
6. Set client secret to `web-app-proxy-secret` (Credentials tab).
7. Add valid redirect URIs: `http://localhost:6274/oauth/callback`, `http://localhost:6274/oauth/callback/debug`, `http://127.0.0.1:6274/oauth/callback`, `http://127.0.0.1:6274/oauth/callback/debug`.
8. Add web origins: `http://localhost:6274`, `http://127.0.0.1:6274`.

Add audience mapper to `web-app-proxy`:

1. Open `web-app-proxy` client.
2. Add mapper type `Audience`.
3. Set included client audience to `booking-api`.
4. Enable `Add to access token`.

Optional demo user:

1. Create user `demo-user`.
2. Set password to `demo-user-password` and disable temporary password.

Configured OAuth2 clients:

- `booking-api`
- `web-app-proxy` (used by the Flask web app for traveler login and backend token forwarding)

Test token request:

```sh
curl -s -X POST \
  http://localhost:8080/realms/galaxium/protocol/openid-connect/token \
  -d "grant_type=client_credentials" \
  -d "client_id=web-app-proxy" \
  -d "client_secret=web-app-proxy-secret"
```

The booking REST API and MCP server now validate bearer tokens when `AUTH_ENABLED=true`.
The web app enforces traveler login when `FRONTEND_AUTH_REQUIRED=true`.

* Simplified Architecture on Code Engine

![](/images/run-containers-on-code-engine-01.png)

## Deploying Without Docker Compose (Code Engine Example)

For a full non-compose setup guide (including Keycloak realm/client setup and required environment variables for both services), see:

- [`../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`](../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)

Important:

1. In this compose file, auth toggles are set to `AUTH_ENABLED=true` (for `booking_system_rest` and `booking_system_mcp`), `OAUTH2_ENABLED=true`, and `FRONTEND_AUTH_REQUIRED=true`.
2. Outside compose (for example Code Engine), you must set these toggles explicitly to keep the same behavior.

For an automated auth verification against deployed URLs (no Docker needed), run:

```sh
export BOOKING_API_BASE_URL=https://<booking-api-url>
export KEYCLOAK_TOKEN_URL=https://<keycloak-url>/realms/galaxium/protocol/openid-connect/token
export OIDC_CLIENT_ID=web-app-proxy
export OIDC_CLIENT_SECRET=<web-app-proxy-client-secret>
export WEB_APP_BASE_URL=https://<web-app-url>
# optional (verifies post-login frontend access)
# export TRAVELER_USERNAME=<traveler-username>
# export TRAVELER_PASSWORD=<traveler-password>
bash verify-keycloak-auth-remote.sh
```

Additional command:

Get token

```sh
TOKEN="$(
  docker exec web_app python -c 'import requests; r=requests.post("http://keycloak:8080/realms/galaxium/protocol/openid-connect/token", data={"grant_type":"password","client_id":"web-app-proxy","client_secret":"web-app-proxy-secret","username":"demo-user","password":"demo-user-password"}, timeout=10); r.raise_for_status(); print(r.json().get("access_token",""))'
)"
TOKEN="$(echo "${TOKEN}" | tr -d '\r\n')"
printf '{"Authorization":"Bearer %s"}\n' "${TOKEN}"
```

Important:
- Use the token command above (`docker exec web_app ... http://keycloak:8080 ...`).
- Do not request the token from `http://localhost:8080/...` for MCP auth checks in this compose setup.
- `localhost` tokens have issuer `http://localhost:8080/realms/galaxium`, but REST/MCP validate issuer `http://keycloak:8080/realms/galaxium`, which causes `invalid_token`.
