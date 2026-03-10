# Local Compose Stack

Use this folder when you want the full demo running locally with the smallest amount of setup.

## Start

From this directory run:

```sh
docker compose up --build
```

Start only the REST-backed frontend path:

```sh
docker compose up --build keycloak booking_system web_app
```

Start only the MCP-backed frontend path:

```sh
docker compose up --build keycloak booking_system_mcp web_app_mcp
```

If you start only one frontend path, only the matching backend and frontend URLs are expected to be available.

Optional thin wrappers are still available:

```sh
bash start-build-containers.sh
bash start-containers-detach.sh
```

## VM / LAN OAuth Option

Use [`docker_compose.vm-oauth.yaml`](./docker_compose.vm-oauth.yaml) when the protected stack runs on the host machine and OAuth clients connect from a VM or another machine over the LAN path.

This is the split-topology option:

- the Galaxium stack runs in Docker Compose on the host machine
- a second application or agent stack runs in another Docker Compose inside a VM on that same machine
- the VM-side containers connect to Keycloak and MCP through the host machine LAN IP or DNS name

This variant keeps Docker backchannel traffic on `http://keycloak:8080`, but it changes the token issuer and MCP discovery metadata to host-LAN-reachable URLs.
That avoids the current split where externally issued tokens use one issuer and container-issued tokens use another.

Source diagram: [network-configuration.drawio](../../network-configuration.drawio)

```mermaid
flowchart LR
  subgraph network["LAN with local machine"]
    subgraph host["Local machine"]
      subgraph vm["VM"]
        subgraph vm_compose["VM compose"]
          vm_app["Agent / app container"]
        end
      end

      subgraph host_compose["Host compose"]
        mcp["Booking MCP server\nhttp://HOST_IP:8084/mcp"]
        tools["Booking tools"]
        kc["Keycloak\nhttp://HOST_IP:8080"]
      end
    end
  end

  vm_app -->|"MCP calls over LAN\ninitialize, tools/list, tools/call"| mcp
  vm_app -->|"OAuth authorize / token over LAN"| kc
  mcp -->|"internal Docker backchannel\nJWKS fetch"| kc
  mcp --> tools
```

How this works:

1. The VM-side app connects to `MCP_PUBLIC_BASE_URL` on the host machine, not to `localhost`.
2. MCP OAuth discovery returns the host-LAN-reachable Keycloak issuer and the host-LAN-reachable MCP registration endpoint.
3. The VM-side app gets a token from `KEYCLOAK_PUBLIC_BASE_URL`, so the token `iss` claim becomes the host-LAN Keycloak URL.
4. REST and MCP validate against that same public issuer because `OIDC_ISSUER` is overridden to `${KEYCLOAK_PUBLIC_BASE_URL}/realms/galaxium`.
5. REST and MCP still download JWKS from `http://keycloak:8080/...` inside Docker, so signature verification stays on the internal container network.
6. The host-side web apps still use `http://keycloak:8080` for their own backchannel token requests because they are in the same compose network as Keycloak.

Why this fixes the OAuth problem:

- Without the override, externally minted tokens can carry issuer `http://HOST_IP:8080/...` while the services expect `http://keycloak:8080/...`, which causes `invalid_token`.
- With the override, the public issuer and the validated issuer are the same value.
- Only the JWKS fetch stays internal. That is safe because JWKS retrieval does not need to match the token `iss` hostname.
- A separate Docker daemon inside the VM cannot join the host Docker network, so LAN URLs are the correct boundary between the two compose stacks.

1. Copy the template and set the VM-reachable URLs:

```sh
cp vm-oauth.env.template vm-oauth.env
```

2. Edit `vm-oauth.env` and set concrete public URLs, for example:

```sh
KEYCLOAK_PUBLIC_BASE_URL=http://192.168.1.50:8080
MCP_PUBLIC_BASE_URL=http://192.168.1.50:8084
```

Here `192.168.1.50` must be the host machine IP that the VM can reach.
Do not use `localhost` for this split host+VM setup.

3. Start the stack with both compose files:

```sh
docker compose --env-file vm-oauth.env \
  -f docker_compose.yaml \
  -f docker_compose.vm-oauth.yaml \
  up --build -d
```

Start only the REST-backed frontend path on the host:

```sh
docker compose --env-file vm-oauth.env \
  -f docker_compose.yaml \
  -f docker_compose.vm-oauth.yaml \
  up --build -d keycloak booking_system web_app
```

Start only the MCP-backed frontend path on the host:

```sh
docker compose --env-file vm-oauth.env \
  -f docker_compose.yaml \
  -f docker_compose.vm-oauth.yaml \
  up --build -d keycloak booking_system_mcp web_app_mcp
```

If you start only one frontend path on the host, only the matching backend and frontend URLs are expected to be available.

What changes in this mode:

- Keycloak is started with a fixed public hostname via `--hostname=${KEYCLOAK_PUBLIC_BASE_URL}`.
- REST and MCP validate `iss=${KEYCLOAK_PUBLIC_BASE_URL}/realms/galaxium`.
- REST and MCP still fetch JWKS from the internal Docker URL `http://keycloak:8080/.../certs`.
- MCP discovery advertises `MCP_PUBLIC_BASE_URL` and the public Keycloak realm URL.
- The second compose inside the VM must call the host machine over LAN URLs. It cannot join the host Docker network.
- `GALAXIUM_SHARED_NETWORK` only helps when both compose projects use the same Docker daemon.

Recommended verification from another machine or from the VM host:

```sh
export BOOKING_API_BASE_URL=http://192.168.1.50:8082
export KEYCLOAK_TOKEN_URL=http://192.168.1.50:8080/realms/galaxium/protocol/openid-connect/token
export OIDC_CLIENT_ID=web-app-proxy
export OIDC_CLIENT_SECRET=web-app-proxy-secret
bash verify-keycloak-auth-remote.sh
```

For the compose running inside the VM, point its OAuth and MCP settings to the same host-LAN URLs, for example:

```sh
KEYCLOAK_BASE_URL=http://192.168.1.50:8080
KEYCLOAK_TOKEN_URL=http://192.168.1.50:8080/realms/galaxium/protocol/openid-connect/token
MCP_SERVER_URL=http://192.168.1.50:8084/mcp
```

Metadata sanity checks for this mode:

```sh
curl -s http://192.168.1.50:8080/realms/galaxium/.well-known/openid-configuration | jq -r .issuer
curl -s http://192.168.1.50:8084/.well-known/oauth-authorization-server | jq .
```

Expected:

- Keycloak `issuer` is `http://192.168.1.50:8080/realms/galaxium`
- MCP metadata `issuer` points to the same Keycloak realm URL
- MCP `registration_endpoint` points to `http://192.168.1.50:8084/oauth/register`

## Local URLs

- Keycloak: `http://localhost:8080`
- HR API docs: `http://localhost:8081/docs`
- Booking REST API docs: `http://localhost:8082/docs`
- Web app (REST-backed): `http://localhost:8083`
- MCP endpoint: `http://localhost:8084/mcp`
- Web app (direct MCP client): `http://localhost:8085`

## Built-In Credentials

- Keycloak admin: `admin` / `admin`
- Traveler login: `demo-user` / `demo-user-password`

The compose file imports the realm automatically from `keycloak/realm/galaxium-realm.json`.

## Verification

Run the complete auth smoke test:

```sh
bash verify-keycloak-auth-e2e.sh
```

Run focused checks:

```sh
bash verify-keycloak-auth.sh
bash verify-keycloak-auth-mcp.sh
```

Run the lightweight MCP CLI test:

```sh
python3 mcp_test_app.py
```

Reports from the verification scripts are written to `test-results/`.

## MCP Inspector

If you want to inspect the MCP server interactively:

1. Start the compose stack.
2. Run `bash start-mcp-inspector-ui.sh`.
3. Open the exact browser URL printed by Inspector.
4. In the UI, set `Streamable HTTP`, `http://localhost:8084/mcp`, and `Via Proxy`.
5. If you follow the manual Inspector UI flow, use the OAuth screens first to register the Inspector client in Keycloak.
6. After that bootstrap step, use `Authentication` -> `Custom Headers`, enable the header row toggle, and add your bearer token as `Authorization: Bearer <token>`.
7. Use the container-based token command for the final MCP connection. Do not replace it with a browser-issued `localhost` token.

Optional helper scripts for the OAuth registration/bootstrap path:

   ```sh
   bash sync-keycloak-inspector-client.sh
   bash verify-keycloak-inspector-client.sh
   ```

Use `/mcp`, not `/msp`. The `/msp` path is only kept as a compatibility redirect.

## Stop

```sh
docker compose down
```

## Related Docs

- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Advanced deployment notes: [../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md](../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)
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
docker compose -f docker_compose.yaml up -d --force-recreate keycloak web_app web_app_mcp booking_system booking_system_mcp
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
