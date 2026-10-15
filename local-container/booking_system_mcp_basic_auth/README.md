# Option 2: Booking MCP Server With Basic Auth

| | |
| --- | --- |
| **Server mode** | `AUTH_MODE=basic` |
| **Use for** | Machine-to-machine access with one shared credential pair, without an identity provider |
| **Client sends** | `Authorization: Basic <base64(username:password)>` on every request |
| **Containers** | `booking_system_mcp_basic_auth` (no Keycloak) |

> **Scope:** `booking_system_mcp` is the only service in this repository that is provided as MCP. This folder starts only that service and none of the REST, web UI, or HR services. For the comparison of all three access options, see [docs/mcp_access_options.md](../../docs/mcp_access_options.md).

## Start, Verify, Stop

Run from the repository root:

```sh
cp local-container/booking_system_mcp_basic_auth/mcp.env.template local-container/booking_system_mcp_basic_auth/mcp.env
# edit BASIC_AUTH_USERNAME / BASIC_AUTH_PASSWORD
bash local-container/booking_system_mcp_basic_auth/start.sh
bash local-container/booking_system_mcp_basic_auth/verify.sh
docker compose -f local-container/booking_system_mcp_basic_auth/docker_compose.yaml down
```

Without `mcp.env`, the demo credentials `demo-basic-user` / `demo-basic-password` are used.

`verify.sh` checks that:

- a request with no credentials, a wrong password, or a bearer token gets `401` with a `WWW-Authenticate: Basic` challenge
- an MCP session opens with the configured credentials, and `tools/list` returns the booking tools
- the OAuth metadata endpoints are disabled (`404`)

## Configuration

`mcp.env` is git-ignored, so real credentials are never committed.

| Variable | Default | Purpose |
| --- | --- | --- |
| `BASIC_AUTH_USERNAME` | `demo-basic-user` | Username the server accepts |
| `BASIC_AUTH_PASSWORD` | `demo-basic-password` | Password the server accepts |
| `BASIC_AUTH_REALM` | `Galaxium Booking MCP` | Realm in the `WWW-Authenticate` challenge |
| `MCP_HOST_PORT` | `8084` | Host port for the MCP server |

## Integration Handover

These are the values for the consuming side, for example the [watsonx Orchestrate guide repository](https://github.com/thomassuedbroecker/galaxium-travels-watsonx-orchestrate-mcp-bob-guide), which uses this option by default:

| Value | Setting |
| --- | --- |
| `MCP_REMOTE_BASE_SERVER_URL` (connection) | `http://<LAN IP>:8084` (no path) |
| `MCP_REMOTE_SERVER_URL` (toolkit import) | `http://<LAN IP>:8084/mcp` |
| Transport | `streamable_http` |
| Connection kind | `basic` |
| Username | value of `BASIC_AUTH_USERNAME` (demo: `demo-basic-user`) |
| Password | value of `BASIC_AUTH_PASSWORD` (demo: `demo-basic-password`) |
| Token URL, redirect URIs, scopes | not used |

The OAuth discovery endpoints (`/.well-known/...`) return `404` in this mode, so the client must send the Basic header directly. For why the LAN IP is used instead of `localhost`, see [docs/mcp_access_options.md](../../docs/mcp_access_options.md#reaching-the-server-from-watsonx-orchestrate-developer-edition).

The guide currently starts the full `docker_compose.basic-auth-vm.yaml` stack. Its MCP server has the same configuration as this folder, so either one works for the MCP integration.

Basic Auth sends the password with every request, so use HTTPS whenever the server is reachable beyond localhost.

## Client Example

[`mcp-client.json`](./mcp-client.json) is a generic `mcpServers` entry. It reads the encoded credentials from an environment variable:

```sh
export GALAXIUM_MCP_BASIC_TOKEN="$(printf '%s' 'demo-basic-user:demo-basic-password' | base64 | tr -d '\r\n')"
```

```json
{
  "type": "http",
  "url": "http://localhost:8084/mcp",
  "headers": { "Authorization": "Basic ${GALAXIUM_MCP_BASIC_TOKEN}" }
}
```

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `401` with `WWW-Authenticate: Basic` | Wrong username or password, or the client sent a `Bearer` header |
| Client tries `/.well-known/oauth-protected-resource` and fails | The client expects OAuth. Configure Basic Auth explicitly, or use option 3 |
