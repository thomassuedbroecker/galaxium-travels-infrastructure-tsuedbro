# Manual Auth Check Using The Commandline

This guide shows how to verify the Galaxium Booking MCP server manually with the MCP Inspector CLI.

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
- `npx`

Check the tools:

```sh
docker --version
curl --version
jq --version
npx --version
```

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

### 2. Confirm the MCP server rejects unauthenticated Inspector access

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --verbose
```

Expected:

- the command fails
- the output contains `401`, `Missing bearer token`, or another unauthorized message

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

### 4. Call the MCP server with the bearer token

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --header "Authorization: Bearer ${ACCESS_TOKEN}" \
  --verbose
```

Expected:

- the command succeeds
- the output includes tool names such as:
  - `list_flights`
  - `book_flight`
  - `get_bookings`
  - `cancel_booking`
  - `register_user`
  - `get_user_id`

### 5. Optional: verify OAuth metadata and dynamic client registration manually

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

### 6. Stop the OAuth stack

```sh
docker compose -f local-container/docker_compose.yaml down
```

## Basic Auth MCP Check

Use this when the MCP server is running in Basic Auth mode.

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

### 3. Confirm the MCP server rejects Inspector access without headers

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --verbose
```

Expected:

- the command fails
- the output shows `401` or an unauthorized error

### 4. Build the Basic Auth header value

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

### 5. Call the MCP server with the Basic Auth header

```sh
npx -y @modelcontextprotocol/inspector \
  --cli http://localhost:8084/mcp \
  --transport http \
  --method tools/list \
  --header "Authorization: Basic ${BASIC_TOKEN}" \
  --verbose
```

Expected:

- the command succeeds
- the output includes the same booking tool names as the OAuth flow

### 6. Optional: compare with a direct curl call

The Inspector CLI is the main goal here, but a raw HTTP call makes the auth header visible:

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

### 7. Stop the Basic Auth stack

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth.yaml down
```

## Mixed Mode Note

The repo also supports `Keycloak UI -> MCP Basic Auth`.

That mode affects the browser UI, not the direct Inspector-to-MCP connection.
When you test the backend directly with Inspector CLI:

- use `Bearer <token>` for the OAuth MCP stack
- use `Basic <base64(username:password)>` for the Basic Auth MCP stack

Do not try to mix the browser login with the direct Inspector CLI header model.

## Common Problems

- `401 Missing bearer token`
  - You are hitting the OAuth MCP server without the bearer token header.
- `401` with Basic Auth
  - Rebuild `BASIC_TOKEN` from the current `basic-auth.env` values.
- metadata endpoint does not exist in Basic Auth mode
  - That is expected. `/.well-known/oauth-authorization-server` only applies to the OAuth MCP variant.
- Inspector cannot connect even with a token
  - Recheck that the stack is running and the transport is `http` with the MCP URL `http://localhost:8084/mcp`.

## Related Docs

- Local compose guide: [local-container/README.md](./local-container/README.md)
- Quickstart: [QUICKSTART.md](./QUICKSTART.md)
- Basic Auth example note: [watsonx_orchestrate_basic_auth_example_integration.md](./watsonx_orchestrate_basic_auth_example_integration.md)
