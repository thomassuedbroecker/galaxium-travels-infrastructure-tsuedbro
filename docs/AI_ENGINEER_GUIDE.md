# AI Engineer & Agent Integration Guide

This guide is for AI engineers, agent developers, and LLM tool integrators who want to connect to the Galaxium Travels MCP server.

## What Is Available

The Galaxium MCP server exposes a booking domain as explicit MCP tools over **Streamable HTTP**. You can call it from any MCP-compatible client — watsonx Orchestrate, a custom agent, or the MCP Inspector.

**MCP endpoint:** `http://localhost:8084/mcp`
**Alternate alias:** `http://localhost:8084/msp` (307 redirect to `/mcp`, for watsonx Orchestrate compatibility)

## Available Tools

| Tool | Arguments | Returns |
| --- | --- | --- |
| `list_flights` | — | All flights with origin, destination, times, price, `seats_available` |
| `register_user` | `name`, `email` | The new traveler, including `user_id` (email must be unique) |
| `get_user_id` | `name`, `email` (both required) | The matching traveler, including `user_id` |
| `book_flight` | `user_id`, `name`, `flight_id` | The booking; `name` must match the registered name for `user_id` |
| `get_bookings` | `user_id` | All bookings for that traveler |
| `cancel_booking` | `booking_id` | The booking with status `cancelled`; seat is released |

Clients discover each tool's name, description (the Python docstring), and JSON input schema (from the typed parameters) through `tools/list`.

### Typical booking flow

```text
list_flights                       → pick a flight_id
register_user(name, email)         → user_id   (first visit)
  or get_user_id(name, email)      → user_id   (returning traveler)
book_flight(user_id, name, flight_id) → booking_id
get_bookings(user_id)              → confirm
cancel_booking(booking_id)         → optional
```

### How errors come back

Business errors (unknown flight, no seats, name mismatch, duplicate email, already cancelled) do **not** produce a JSON-RPC error. The call succeeds and the result carries `"isError": true` with a readable message the agent can act on:

```json
{"jsonrpc":"2.0","id":3,"result":{"isError":true,"content":[{"type":"text",
 "text":"Error calling tool 'cancel_booking': Booking with ID 9999 not found. ..."}]}}
```

Note: the server reseeds its SQLite database at every startup, so bookings and registered users do not survive a restart.

## Auth Options

Choose the auth mode that matches your deployment:

| Mode | How to authenticate | When to use |
| --- | --- | --- |
| `none` | No `Authorization` header required | Local dev, no security needed |
| `oauth2` | `Authorization: Bearer <token>` from Keycloak | Full OAuth flow (local or LAN) |
| `basic` | `Authorization: Basic <base64(user:pass)>` | No Keycloak; shared credentials |

The active mode is set via `AUTH_MODE` on the MCP server. The compose stacks set this automatically. To run only the MCP server in one of these modes, use the standalone folders described in [mcp_access_options.md](./mcp_access_options.md). Each has `start.sh`, `verify.sh`, and the values to hand over to an MCP client.

Supported OAuth grant types for this demo:

| Grant | Use it for |
| --- | --- |
| `client_credentials` | Agents and services calling the MCP server (this guide, watsonx Orchestrate) |
| `authorization_code` | Interactive browser login, e.g. MCP Inspector |

The implicit flow is **disabled** on every Keycloak client and must not be used.

## Calling the MCP Server With curl

Streamable HTTP is session-based. A raw `tools/call` without a session is rejected with `400 Bad Request: Missing session ID`. Every request needs:

- `Content-Type: application/json`
- `Accept: application/json, text/event-stream`
- your auth header (`AUTH` below; leave it empty when `AUTH_MODE=none`)
- after `initialize`: the `Mcp-Session-Id` header the server returned

```sh
MCP=http://localhost:8084/mcp
AUTH="Authorization: Bearer $TOKEN"     # or: AUTH="Authorization: Basic $(printf '%s' 'demo-basic-user:demo-basic-password' | base64)"
H=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" -H "$AUTH")

# 1. initialize — capture the session ID from the response header
SID=$(curl -s -D - -o /dev/null "$MCP" "${H[@]}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1.0"}}}' \
  | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}' | tr -d '\r')

# 2. confirm initialization (returns 202)
curl -s "$MCP" "${H[@]}" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

# 3. call a tool (the response is a Server-Sent Event: "event: message / data: {...}")
curl -s "$MCP" "${H[@]}" -H "Mcp-Session-Id: $SID" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_flights","arguments":{}}}'
```

In real agents, use an MCP client library (Python `mcp`/`fastmcp`, TypeScript `@modelcontextprotocol/sdk`) — it handles the session for you.

## Option A — Connect Over OAuth (local stack)

### 1. Start the stack

```sh
docker compose -f local-container/docker_compose.yaml up --build \
  keycloak booking_system_mcp
```

### 2. Get a bearer token (client credentials)

```sh
TOKEN=$(curl -s -X POST \
  http://localhost:8086/realms/galaxium/protocol/openid-connect/token \
  -d grant_type=client_credentials \
  -d client_id=web-app-proxy \
  -d client_secret=web-app-proxy-secret \
  | jq -r .access_token)
```

This is the same client and grant the web UIs use to call the MCP server. The secret is a local demo value.

### 3. Call a tool

Run the three steps in [Calling the MCP Server With curl](#calling-the-mcp-server-with-curl) with `AUTH="Authorization: Bearer $TOKEN"`.

### 4. Use the Python test client

```sh
python3 local-container/mcp_test_app.py \
  --mcp-url http://localhost:8084/mcp \
  --token "$TOKEN"
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

Run the three steps in [Calling the MCP Server With curl](#calling-the-mcp-server-with-curl) with:

```sh
AUTH="Authorization: Basic $(printf '%s' 'demo-basic-user:demo-basic-password' | base64)"
```

Or use the Python test client:

```sh
python3 local-container/mcp_test_app.py --auth-scheme basic
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

Then get a client-credentials token and run the test client from the VM side:

```sh
TOKEN=$(curl -s -X POST "http://${LOCAL_NET_IP}:8086/realms/galaxium/protocol/openid-connect/token" \
  -d grant_type=client_credentials -d client_id=web-app-proxy -d client_secret=web-app-proxy-secret \
  | jq -r .access_token)

python3 local-container/mcp_test_app.py \
  --mcp-url "http://${LOCAL_NET_IP}:8084/mcp" \
  --token "$TOKEN"
```

## Option D — Connect From a VM or LAN Machine (Basic Auth)

```sh
cp local-container/vm-client-basic-auth.env.template local-container/vm-client-basic-auth.env
# Edit: set MCP_SERVER_URL=http://${LOCAL_NET_IP}:8084/mcp

python3 local-container/mcp_test_app.py \
  --mcp-url "http://${LOCAL_NET_IP}:8084/mcp" \
  --auth-scheme basic
```

## OAuth Metadata Endpoints

When `AUTH_MODE=oauth2` the server exposes standard OAuth discovery endpoints:

```sh
curl -s http://localhost:8084/.well-known/oauth-authorization-server | jq .
curl -s http://localhost:8084/.well-known/oauth-protected-resource | jq .
```

These are used by watsonx Orchestrate and automated clients to discover the token URL and registration endpoint.

## MCP Inspector (manual exploration)

```sh
bash local-container/start-mcp-inspector-ui.sh
```

Open the URL printed by the script, then set:
- Transport: `Streamable HTTP`
- URL: `http://localhost:8084/mcp`
- Connection type: `Via Proxy`

In OAuth mode the Inspector uses the browser-based `authorization_code` flow.

For Basic Auth mode:

```sh
MCP_AUTH_SCHEME=basic \
BASIC_AUTH_USERNAME=demo-basic-user \
BASIC_AUTH_PASSWORD=demo-basic-password \
bash local-container/start-mcp-inspector-ui.sh
```

## watsonx Orchestrate

The watsonx Orchestrate integration itself lives in the [galaxium-travels-watsonx-orchestrate-mcp-bob-guide](https://github.com/thomassuedbroecker/galaxium-travels-watsonx-orchestrate-mcp-bob-guide) repository. This repository provides the MCP server configurations it uses: see [mcp_access_options.md](./mcp_access_options.md), including how watsonx Orchestrate Developer Edition reaches the server over the LAN IP. For the OAuth option, [the Keycloak guide](../local-container/keycloak/README.md) explains how to adjust clients and the issuer.

Background reading in this repository:
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
