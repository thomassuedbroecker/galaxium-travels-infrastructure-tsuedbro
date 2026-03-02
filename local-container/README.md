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

### Verify Keycloak Is Enforced (Automated Test)

From `local-container/` run:

```sh
bash verify-keycloak-auth.sh
```

What this script verifies:

1. Keycloak and the booking API are reachable.
2. Calling `GET /flights` without a bearer token fails with `401`.
3. Calling `GET /flights` with a Keycloak traveler token succeeds with `200`.
4. The web app root redirects to `/login` when no traveler session exists.
5. Web app APIs fail with `401` without traveler login.
6. After traveler login, web app APIs (flights/bookings/book) succeed.

If all checks pass, Keycloak is actively used to protect the booking API endpoints.

> Note: Tokens requested from `http://localhost:8080` may have an issuer mismatch with the booking API (`Invalid issuer`) because the API validates the in-network issuer (`http://keycloak:8080/...`). The script requests a token from inside the Docker network to avoid this mismatch.

### Verify MCP Server Auth with MCP Inspector (Local + Containerized)

From `local-container/` run:

```sh
bash verify-keycloak-auth-mcp.sh
```

What this script verifies:

1. Keycloak and the MCP server are reachable.
2. MCP Inspector `tools/list` without a bearer token is rejected (`401`).
3. MCP Inspector `tools/list` with a Keycloak traveler token succeeds and returns MCP tools.

Implementation note:
- If `npx` is available, the script runs `@modelcontextprotocol/inspector` directly.
- If `npx` is not available, it runs the inspector from a Docker container (`ghcr.io/modelcontextprotocol/inspector:latest`).

### Manual MCP Inspector Test (Local)

Use this short flow to validate MCP auth in Inspector.

1. Terminal 1: start the full local stack:

```sh
cd local-container
bash start-build-containers.sh
```

2. Terminal 2: start MCP Inspector UI:

```sh
npx @modelcontextprotocol/inspector
```

Use the browser URL opened by Inspector (it includes `MCP_PROXY_AUTH_TOKEN=...`).
If you open `http://localhost:6274` manually without this token, the UI can show a connection error.
Optional fixed token launch:

```sh
export MCP_PROXY_AUTH_TOKEN=local-dev-token
npx @modelcontextprotocol/inspector
```

If `npx` is missing, install Node.js first:

```sh
brew install node
```

3. Terminal 3: get a Keycloak access token:

```sh
TOKEN="$(
  docker exec web_app python -c 'import requests; r=requests.post("http://keycloak:8080/realms/galaxium/protocol/openid-connect/token", data={"grant_type":"password","client_id":"web-app-proxy","client_secret":"web-app-proxy-secret","username":"demo-user","password":"demo-user-password"}, timeout=10); r.raise_for_status(); print(r.json().get("access_token",""))'
)"
TOKEN="$(echo "${TOKEN}" | tr -d '\r\n')"
printf '{"Authorization":"Bearer %s"}\n' "${TOKEN}"
# macOS helper (optional): copy JSON header directly to clipboard
printf '{"Authorization":"Bearer %s"}' "${TOKEN}" | pbcopy
```

4. In Inspector UI, connect to MCP:
- Connection type: `Streamable HTTP`
- URL: `http://localhost:8084/mcp`
- Important: use `/mcp` (not `/msp`)
- Auth mode: `Custom Headers` (do not use OAuth mode)
- Header: `Authorization: Bearer <TOKEN>`
- If you use `Custom Header JSON`, paste:

```json
{"Authorization":"Bearer <TOKEN>"}
```

Note: The current Inspector UI does not expose a full OAuth form (`Token URL`, `Client ID`, etc.).  
It also does not provide username/password fields.  
Get the token in terminal (step 3), then paste it into the header field.

Run `tools/list` after connect. Expected result: tool list is returned (`list_flights`, `book_flight`, `get_bookings`, `cancel_booking`, `register_user`, `get_user_id`).

Troubleshooting:
- If container logs show `POST /msp ... 404`, Inspector is pointing to the wrong path.
- The correct URL is `http://localhost:8084/mcp` (not `/msp`).
- In Inspector, remove old saved connection entries and reconnect with the URL above.
- If Inspector shows `MCP error -32602: Invalid request parameters`, switch auth mode to `Custom Headers`, clear any OAuth settings, and reconnect.
- If Inspector shows `MCP error -32601: Method not found`, check container logs for `MCP request method: ...` to see which JSON-RPC method was requested.
- `GET /openapi.json` returning `404` is expected for this MCP server.
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

- Do not use OAuth discovery in Inspector for this local setup. If enabled, Inspector may probe `/.well-known/...` on the MCP server and show additional 404s.

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
4. Set `Standard flow = Off`.
5. Set `Direct access grants = On` (required for traveler username/password login in this demo frontend).
6. Set client secret to `web-app-proxy-secret` (Credentials tab).

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
