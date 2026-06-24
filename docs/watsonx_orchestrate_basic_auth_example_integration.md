# watsonx Orchestrate Example Integration for the Basic Auth MCP Server

This note explains the repository's Basic Auth MCP variant for direct server-to-server style access.

Use this when you want a client such as watsonx Orchestrate to call the Booking MCP server with a shared `Authorization: Basic ...` header instead of Keycloak OAuth.

If you need the Keycloak OAuth 2.0 client-credentials path instead, use [docs/reference/WATSONX_ORCHESTRATE_BOOKING_MCP_SETUP_GUIDE.md](./docs/reference/WATSONX_ORCHESTRATE_BOOKING_MCP_SETUP_GUIDE.md).

## What Changes Compared With OAuth

In the Basic Auth variant:

- there is no Keycloak dependency
- there is no token URL
- there are no redirect URIs
- there is no OAuth metadata discovery
- every MCP request carries the same Basic Auth header

The public MCP endpoint stays the same shape:

- `http://<HOST>:8084/mcp`

What changes is only the authentication method.

## Start the Basic Auth Stack

1. Prepare the shared Basic Auth credentials:

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
```

2. Start the Basic Auth compose variant:

```sh
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth.yaml \
  up --build -d booking_system booking_system_mcp
```

Default demo credentials:

- username: `demo-basic-user`
- password: `demo-basic-password`

## Connection Values

For a local machine setup:

- MCP URL: `http://localhost:8084/mcp`
- Auth scheme: `Basic`
- Username: `demo-basic-user`
- Password: `demo-basic-password`

For a VM or second machine in the LAN, use the matching client template:

```sh
cp local-container/vm-client-basic-auth.env.template local-container/vm-client-basic-auth.env
```

Edit `local-container/vm-client-basic-auth.env`:

```sh
MCP_SERVER_URL=http://<HOST_IP_OR_DNS>:8084/mcp
BASIC_AUTH_USERNAME=demo-basic-user
BASIC_AUTH_PASSWORD=demo-basic-password
```

## Required Request Shape

The Booking MCP server expects:

- `POST` to `/mcp`
- `Authorization: Basic <base64(username:password)>`
- `Content-Type: application/json`
- `Accept: application/json, text/event-stream`
- `MCP-Protocol-Version: 2025-11-25`

Example header generation:

```sh
BASIC_TOKEN="$(printf '%s' 'demo-basic-user:demo-basic-password' | base64 | tr -d '\r\n')"
echo "${BASIC_TOKEN}"
```

Example initialize request:

```sh
curl -fsS http://localhost:8084/mcp \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"wxo-basic-auth-check","version":"1.0.0"}}}'
```

For a real MCP session, follow the returned `Mcp-Session-Id` on later `tools/list` and `tools/call` requests. The helper script below already handles that sequence.

## Verification Before You Touch watsonx Orchestrate

Use the repo helper to verify the exact Basic Auth MCP flow first:

```sh
python3 local-container/mcp_test_app.py \
  --mcp-url http://localhost:8084/mcp \
  --auth-scheme basic \
  --basic-username demo-basic-user \
  --basic-password demo-basic-password
```

For a VM or LAN host, replace `localhost` with the reachable host IP or DNS name.

If you want the repo's compose-backed smoke test instead:

```sh
bash local-container/verify-basic-auth-backends.sh
```

## Mapping This to watsonx Orchestrate

The repo side is ready when your client can send the equivalent of:

```http
Authorization: Basic <base64(username:password)>
```

and connect to:

```text
http://<HOST>:8084/mcp
```

How you enter that in watsonx Orchestrate depends on the connection model available in your environment. The important repo-side contract is:

- no OAuth token exchange is required
- no Keycloak redirect URI setup is required
- no `/oauth/register` call is required
- the MCP transport remains `Streamable HTTP`

## MCP Inspector Equivalence

If you want to compare the same Basic Auth connection manually in MCP Inspector:

```sh
INSPECTOR_AUTO_START=0 \
MCP_AUTH_SCHEME=basic \
BASIC_AUTH_USERNAME=demo-basic-user \
BASIC_AUTH_PASSWORD=demo-basic-password \
bash local-container/start-mcp-inspector-ui.sh
```

That generates the same `Authorization: Basic ...` header shape used by the Basic Auth smoke tests.

## Common Errors

- `401 Unauthorized`: the Basic Auth username or password is wrong
- connection works against `localhost` but not from another machine: use `vm-client-basic-auth.env.template` and replace `localhost` with the host IP or DNS name
- trying OAuth metadata URLs such as `/.well-known/oauth-authorization-server`: those do not apply to the Basic Auth variant
- trying to configure redirect URIs in Keycloak: that is only needed for the OAuth variant

## Related Files

- Basic Auth compose file: `local-container/docker_compose.basic-auth.yaml`
- Shared Basic Auth env template: `local-container/basic-auth.env.template`
- VM/LAN Basic Auth client template: `local-container/vm-client-basic-auth.env.template`
- Direct MCP verification helper: `local-container/mcp_test_app.py`
- Basic Auth backend smoke test: `local-container/verify-basic-auth-backends.sh`
- Inspector config helper: `local-container/start-mcp-inspector-ui.sh`
