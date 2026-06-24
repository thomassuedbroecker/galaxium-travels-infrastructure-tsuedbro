# AI Engineer & Agent Integration Guide

This guide is for AI engineers, agent developers, and LLM tool integrators who want to connect to the Galaxium Travels MCP server.

## What Is Available

The Galaxium MCP server exposes a booking domain as explicit MCP tools over **Streamable HTTP**. You can call it from any MCP-compatible client — Watson Orchestrate, a custom agent, or the MCP Inspector CLI.

**MCP endpoint:** `http://localhost:8084/mcp`
**Alternate alias:** `http://localhost:8084/msp` (307 redirect to `/mcp`, for Watson Discovery compatibility)

## Available Tools

| Tool | What it does |
| --- | --- |
| `list_flights` | Return all available flights |
| `book_flight` | Book a flight for a registered traveler |
| `get_bookings` | Return all bookings for a traveler |
| `cancel_booking` | Cancel an existing booking |
| `register_user` | Register a new traveler |
| `get_user_id` | Look up the traveler ID for a given name |

Each tool includes `operation_id`, `summary`, and `description` metadata consumable by Watson Orchestrate and the MCP Inspector.

## Auth Options

Choose the auth mode that matches your deployment:

| Mode | How to authenticate | When to use |
| --- | --- | --- |
| `none` | No `Authorization` header required | Local dev, no security needed |
| `oauth2` | `Authorization: Bearer <token>` from Keycloak | Full OAuth flow (local or LAN) |
| `basic` | `Authorization: Basic <base64(user:pass)>` | No Keycloak; shared credentials |

The active mode is set via `AUTH_MODE` on the MCP server. The compose stacks set this automatically.

## Option A — Connect Over OAuth (local stack)

### 1. Start the stack

```sh
docker compose -f local-container/docker_compose.yaml up --build \
  keycloak booking_system_mcp
```

### 2. Get a bearer token

```sh
export LOCAL_NET_IP=localhost
curl -s -X POST \
  http://localhost:8086/realms/galaxium/protocol/openid-connect/token \
  -d "grant_type=password&client_id=booking-app&username=demo-user&password=demo-user-password" \
  | jq -r .access_token
```

### 3. Call a tool

```sh
TOKEN=<token from step 2>
curl -s http://localhost:8084/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_flights","arguments":{}}}'
```

### 4. Use the Python test client

```sh
python3 local-container/mcp_test_app.py \
  --mcp-url http://localhost:8084/mcp \
  --token-source http \
  --token-url http://localhost:8086/realms/galaxium/protocol/openid-connect/token
```

## Option B — Connect Over Basic Auth

### 1. Start the Basic Auth stack

```sh
cp local-container/basic-auth.env.template local-container/basic-auth.env
docker compose --env-file local-container/basic-auth.env \
  -f local-container/docker_compose.basic-auth.yaml \
  up --build booking_system_mcp
```

Default credentials: `demo-basic-user` / `demo-basic-password`

### 2. Call a tool

```sh
curl -s http://localhost:8084/mcp \
  -u demo-basic-user:demo-basic-password \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_flights","arguments":{}}}'
```

## Option C — Connect From a VM or LAN Machine (OAuth)

Set your host IP and use the VM client env template:

```sh
export LOCAL_NET_IP=$(ipconfig getifaddr en0)   # macOS
# export LOCAL_NET_IP=$(ip route get 1.1.1.1 | awk '{print $NF; exit}')  # Linux

cp local-container/vm-client.env.template local-container/vm-client.env
# Edit vm-client.env — replace placeholders with $LOCAL_NET_IP
```

Key variables:

```sh
KEYCLOAK_BASE_URL=http://${LOCAL_NET_IP}:8086
KEYCLOAK_TOKEN_URL=http://${LOCAL_NET_IP}:8086/realms/galaxium/protocol/openid-connect/token
MCP_SERVER_URL=http://${LOCAL_NET_IP}:8084/mcp
```

Then run the test client from the VM side:

```sh
python3 local-container/mcp_test_app.py \
  --mcp-url http://${LOCAL_NET_IP}:8084/mcp \
  --token-source http \
  --token-url http://${LOCAL_NET_IP}:8086/realms/galaxium/protocol/openid-connect/token
```

## Option D — Connect From a VM or LAN Machine (Basic Auth)

```sh
cp local-container/vm-client-basic-auth.env.template local-container/vm-client-basic-auth.env
# Edit: set MCP_SERVER_URL=http://${LOCAL_NET_IP}:8084/mcp
```

## OAuth Metadata Endpoints

When `AUTH_MODE=oauth2` the server exposes standard OAuth discovery endpoints:

```sh
curl -s http://localhost:8084/.well-known/oauth-authorization-server | jq .
curl -s http://localhost:8084/.well-known/oauth-protected-resource | jq .
```

These are used by Watson Orchestrate and automated clients to discover the token URL and registration endpoint.

## MCP Inspector (manual exploration)

```sh
bash local-container/start-mcp-inspector-ui.sh
```

Open the URL printed by the script, then set:
- Transport: `Streamable HTTP`
- URL: `http://localhost:8084/mcp`
- Connection type: `Via Proxy`

For Basic Auth mode:

```sh
MCP_AUTH_SCHEME=basic \
BASIC_AUTH_USERNAME=demo-basic-user \
BASIC_AUTH_PASSWORD=demo-basic-password \
bash local-container/start-mcp-inspector-ui.sh
```

## Watson Orchestrate

See the full Watson Orchestrate setup guide:
[docs/reference/WATSONX_ORCHESTRATE_BOOKING_MCP_SETUP_GUIDE.md](./reference/WATSONX_ORCHESTRATE_BOOKING_MCP_SETUP_GUIDE.md)

For a Basic Auth variant example:
[docs/watsonx_orchestrate_basic_auth_example_integration.md](./watsonx_orchestrate_basic_auth_example_integration.md)

## Manual CLI Walkthrough

Step-by-step command-line walkthrough covering both OAuth and Basic Auth variants, including raw MCP protocol calls:
[docs/manual_auth_check_using_the_commandline.md](./manual_auth_check_using_the_commandline.md)

## Related Docs

- Architecture overview: [../ARCHITECTURE.md](../ARCHITECTURE.md)
- Full quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose file reference: [../local-container/README.md](../local-container/README.md)
- MCP server source: [../booking_system_mcp/README.md](../booking_system_mcp/README.md)
