# Manual Auth Check Using The Commandline

This guide shows how to verify the Galaxium Booking MCP server manually from the command line.

It is intentionally separate from the existing bash automation.
Use it when you want to understand the auth flow step by step.

The MCP transport stays on `Streamable HTTP`.

## What You Will Test

- OAuth-protected MCP access with a Keycloak bearer token
- Basic Auth-protected MCP access with a shared `Authorization: Basic ...` header
- the same `tools/list` call in both modes

This guide talks directly to the MCP server.
It does not go through the browser UIs.

## Prerequisites

- Docker Desktop or another working Docker runtime
- `curl`
- `jq`
- `npx` optional, only if you also want to open MCP Inspector UI after the commandline checks

Check the tools:

```sh
docker --version
curl --version
jq --version
npx --version
```

## Current Inspector CLI Limitation

As of `2026-03-24`, the direct Inspector CLI form against a URL-based MCP server is not reliable.

This command may fail:

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --verbose
```

with:

```text
Arguments cannot be passed to a URL-based MCP server.
```

This is tracked upstream in `modelcontextprotocol/inspector` issue `#790`:
<https://github.com/modelcontextprotocol/inspector/issues/790>

For this repository, use:

- `curl` for the actual commandline verification
- Inspector UI mode started from the command line only when you want an interactive follow-up check

## OAuth MCP Check

Use this when the MCP server is running with Keycloak OAuth.

### 1. Start the OAuth MCP stack

From the repository root:

```sh
docker compose -f local-container/docker_compose.yaml up --build -d \
  keycloak booking_system_mcp
```

Wait until these URLs respond:

```sh
curl -fsS http://localhost:8086/realms/galaxium/.well-known/openid-configuration | jq -r .issuer
curl -fsS http://localhost:8084/.well-known/oauth-protected-resource | jq .
curl -fsS http://localhost:8084/.well-known/oauth-authorization-server | jq .
```

Expected:

- Keycloak issuer is `http://localhost:8086/realms/galaxium`
- the MCP metadata endpoints return JSON

### 2. Optional: confirm the current Inspector CLI limitation

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --verbose
```

Expected:

- the command fails
- the output may contain `Arguments cannot be passed to a URL-based MCP server.`

### 3. Get a traveler access token from Keycloak

```sh
ACCESS_TOKEN="$(
  curl -fsS \
    -X POST http://localhost:8086/realms/galaxium/protocol/openid-connect/token \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=password' \
    --data-urlencode 'client_id=web-app-proxy' \
    --data-urlencode 'client_secret=web-app-proxy-secret' \
    --data-urlencode 'username=demo-user' \
    --data-urlencode 'password=demo-user-password' \
  | jq -r '.access_token'
)"
```

Check that a token was returned:

```sh
test -n "${ACCESS_TOKEN}" && echo "access token acquired"
```

Optional claim check:

```sh
python3 - <<'PY' "${ACCESS_TOKEN}"
import base64, json, sys
token = sys.argv[1]
payload = token.split(".")[1]
payload += "=" * ((4 - len(payload) % 4) % 4)
print(json.dumps(json.loads(base64.urlsafe_b64decode(payload)), indent=2))
PY
```

### 4. Verify OAuth manually from the command line

```sh
curl -i \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"manual-oauth-check","version":"1.0.0"}}}'
```

Expected:

- HTTP `200`
- a response body containing `serverInfo`
- an `mcp-session-id` response header

### 5. Verify `tools/list` with the bearer token

Use the `mcp-session-id` value from the previous response:

```sh
SESSION_ID='<paste-the-mcp-session-id-here>'

curl -sS \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "MCP-Session-Id: ${SESSION_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

Expected:

- HTTP `200`
- a `data: {...}` payload containing tool names such as:
  - `list_flights`
  - `book_flight`
  - `get_bookings`
  - `cancel_booking`
  - `register_user`
  - `get_user_id`

### 6. Optional: verify `tools/call(list_flights)` with the bearer token

```sh
curl -sS \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "MCP-Session-Id: ${SESSION_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_flights","arguments":{}}}'
```

Expected:

- HTTP `200`
- the returned content includes the flight list

### 7. Optional: verify OAuth metadata and dynamic client registration manually

Read the authorization server metadata:

```sh
curl -fsS http://localhost:8084/.well-known/oauth-authorization-server | jq .
```

Register a demo client:

```sh
curl -fsS \
  -X POST http://localhost:8084/oauth/register \
  -H 'Content-Type: application/json' \
  -d '{"client_name":"manual-inspector-check","redirect_uris":["http://localhost:6274/oauth/callback"],"grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"client_secret_post","scope":"openid profile email"}' \
| jq .
```

Expected:

- HTTP `201`
- a JSON payload with `client_id`, `client_secret`, and `redirect_uris`

This step is not required for the CLI bearer-token check, but it helps explain why the repo also exposes OAuth metadata for Inspector-style clients.

### 8. Optional: open Inspector UI after the commandline proof

If you still want to inspect the server interactively after the commandline checks:

```sh
MCP_PROXY_AUTH_TOKEN=local-dev-token npx -y @modelcontextprotocol/inspector
```

Use:

- Connection mode: `Proxy`
- Transport: `Streamable HTTP`
- URL: `http://localhost:8084/mcp`
- Custom Header JSON:

```json
{"Authorization":"Bearer YOUR_ACCESS_TOKEN"}
```

### 9. Stop the OAuth stack

```sh
docker compose -f local-container/docker_compose.yaml down
```

## Basic Auth MCP Check

Use this when the MCP server is running in Basic Auth mode.

This stack does not start Keycloak.
In this section, do not use `http://localhost:8086`, do not request a bearer token, and do not call the OAuth metadata endpoints.

If you just finished the OAuth section above, stop that stack first so you are not accidentally testing the wrong deployment:

```sh
docker compose -f local-container/docker_compose.yaml down
```

### 1. Prepare the Basic Auth env file

If you do not already have one:

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
```

The default credentials are:

- username: `demo-basic-user`
- password: `demo-basic-password`

### 2. Start the Basic Auth MCP stack

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth.yaml up --build -d \
  booking_system_mcp
```

Check the health endpoint:

```sh
curl -fsS http://localhost:8084/ | head
```

The only service you need for this manual backend check is the MCP server on `http://localhost:8084/mcp`.
There is no Keycloak dependency in this configuration.

### 3. Confirm the MCP server rejects unauthenticated requests

This is the first real commandline proof for Basic Auth:

```sh
curl -i \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"manual-basic-check","version":"1.0.0"}}}'
```

Expected:

- HTTP `401 Unauthorized`
- `WWW-Authenticate: Basic realm="Galaxium Booking MCP"`
- a response body similar to `{"detail":"Missing basic credentials"}`

### 4. Optional: confirm the current Inspector CLI limitation

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --verbose
```

Expected:

- the command fails
- the output may contain `Arguments cannot be passed to a URL-based MCP server.`

### 5. Build the Basic Auth header value

Load the credentials:

```sh
set -a
source local-container/basic-auth.env
set +a
```

Create the base64 token:

```sh
BASIC_TOKEN="$(printf '%s' "${BASIC_AUTH_USERNAME}:${BASIC_AUTH_PASSWORD}" | base64 | tr -d '\r\n')"
```

Optional check:

```sh
echo "Authorization: Basic ${BASIC_TOKEN}"
```

### 6. Verify Basic Auth manually with `initialize`

```sh
curl -i \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"manual-basic-check","version":"1.0.0"}}}'
```

Expected:

- HTTP `200`
- an `mcp-session-id` response header
- a response body containing `serverInfo`

### 7. Verify `tools/list` with Basic Auth

Use the `mcp-session-id` value from the previous response:

```sh
export SESSION_ID='<paste-the-mcp-session-id-here>'
```

Invoke following command:

```sh
curl -sS \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "MCP-Session-Id: ${SESSION_ID}" \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

c136eee344ba4f8aa886becd4d3b73ec

Expected:

- HTTP `200`
- a `data: {...}` payload with:
  - `list_flights`
  - `book_flight`
  - `get_bookings`
  - `cancel_booking`
  - `register_user`
  - `get_user_id`

### 8. Verify `tools/call(list_flights)` with Basic Auth

```sh
curl -sS \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "MCP-Session-Id: ${SESSION_ID}" \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_flights","arguments":{}}}'
```

Expected:

- HTTP `200`
- a `data: {...}` payload containing the available flights

### 9. Optional: open Inspector UI after the commandline proof

```sh
MCP_PROXY_AUTH_TOKEN=local-dev-token npx -y @modelcontextprotocol/inspector
```

Use:

- Connection mode: `Proxy`
- Transport: `Streamable HTTP`
- URL: `http://localhost:8084/mcp`
- Custom Header JSON:

```json
{"Authorization":"Basic YOUR_BASE64_TOKEN"}
```

Replace `YOUR_BASE64_TOKEN` with `${BASIC_TOKEN}`.

### 10. Optional: compare with a direct curl call

This direct HTTP call is useful because current Inspector CLI mode is unreliable for URL-based servers:

```sh
curl -i \
  -X POST http://localhost:8084/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -H 'MCP-Protocol-Version: 2025-11-25' \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"manual-basic-check","version":"1.0.0"}}}'
```

Expected:

- HTTP `200`
- an MCP initialize response

### 11. Stop the Basic Auth stack

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth.yaml down
```

## Mixed Mode Note

The repo also supports `Keycloak UI -> MCP Basic Auth`.

That mode affects the browser UI, not the direct Inspector-to-MCP connection.
When you test the backend directly with Inspector UI or raw HTTP:

- use `Bearer <token>` for the OAuth MCP stack
- use `Basic <base64(username:password)>` for the Basic Auth MCP stack

Do not try to mix the browser login with the direct Inspector header model.

## Common Problems

- `401 Missing bearer token`
  - You are hitting the OAuth MCP server without the bearer token header.
- `401` with Basic Auth
  - Rebuild `BASIC_TOKEN` from the current `basic-auth.env` values.
- `401 Missing basic credentials`
  - You reached the Basic Auth MCP server, but the `Authorization: Basic ...` header was not sent.
- `200` on Basic Auth `initialize`, but `tools/list` fails
  - Reuse the exact `mcp-session-id` returned by `initialize` in the `MCP-Session-Id` header.
- `localhost:8086` does not respond during the Basic Auth check
  - That is expected. Keycloak is not started in the Basic Auth stack.
- metadata endpoint does not exist in Basic Auth mode
  - That is expected. `/.well-known/oauth-authorization-server` only applies to the OAuth MCP variant.
- `Arguments cannot be passed to a URL-based MCP server.`
  - That is the current Inspector CLI limitation for URL-based MCP servers. Use Inspector UI mode or a raw `curl` check instead.
- Inspector cannot connect even with a token
  - Recheck that the stack is running, the transport is `Streamable HTTP`, and the MCP URL is `http://localhost:8084/mcp`.

## Related Docs

- Local compose guide: [local-container/README.md](./local-container/README.md)
- Quickstart: [QUICKSTART.md](./QUICKSTART.md)
- Basic Auth example note: [watsonx_orchestrate_basic_auth_example_integration.md](./watsonx_orchestrate_basic_auth_example_integration.md)
