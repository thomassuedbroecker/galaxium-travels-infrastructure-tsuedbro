# Option 1: Booking MCP Server Without Authentication

| | |
| --- | --- |
| **Server mode** | `AUTH_MODE=none` |
| **Use for** | Local development, demos, quick tool tests |
| **Do not use for** | Anything reachable from outside your machine |
| **Containers** | `booking_system_mcp_no_auth` |

> **Scope:** `booking_system_mcp` is the only service in this repository that is provided as MCP. This folder starts only that service and none of the REST, web UI, or HR services. For the comparison of all three access options, see [docs/mcp_access_options.md](../../docs/mcp_access_options.md).

## Start, Verify, Stop

Run from the repository root:

```sh
bash local-container/booking_system_mcp_no_auth/start.sh
bash local-container/booking_system_mcp_no_auth/verify.sh
docker compose -f local-container/booking_system_mcp_no_auth/docker_compose.yaml down
```

`verify.sh` checks that:

- an MCP session opens without credentials
- `tools/list` returns the booking tools
- the OAuth metadata endpoints are disabled (`404`)

## Configuration

Optional: `cp mcp.env.template mcp.env`. `start.sh` and `verify.sh` load the file automatically.

| Variable | Default | Purpose |
| --- | --- | --- |
| `MCP_HOST_PORT` | `8084` | Host port for the MCP server |

## Integration Handover

These are the values for the consuming side, for example the [watsonx Orchestrate guide repository](https://github.com/thomassuedbroecker/galaxium-travels-watsonx-orchestrate-mcp-bob-guide):

| Value | Setting |
| --- | --- |
| `MCP_REMOTE_SERVER_URL` (toolkit import) | `http://<LAN IP>:8084/mcp` |
| `MCP_REMOTE_BASE_SERVER_URL` (connection) | not needed, because no connection is used |
| Transport | `streamable_http` |
| Authentication | none |

In watsonx Orchestrate, this means importing the remote MCP toolkit without `--app-id`. Use it only in a local test setup. For why the LAN IP is used instead of `localhost`, see [docs/mcp_access_options.md](../../docs/mcp_access_options.md#reaching-the-server-from-watsonx-orchestrate-developer-edition).

## Client Example

[`mcp-client.json`](./mcp-client.json) is a generic `mcpServers` entry in the format used by MCP clients such as Claude Code and Cursor:

```json
{ "type": "http", "url": "http://localhost:8084/mcp" }
```
