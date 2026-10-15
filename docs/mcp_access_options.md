# Booking MCP Server: Access Options

> **Only one service is provided as MCP: `booking_system_mcp`.**
> It is the single MCP server in this repository and the only service that external MCP clients such as watsonx Orchestrate connect to. The other services, listed below, are not MCP servers and are not part of the MCP integration. The three folders below start only `booking_system_mcp`, plus Keycloak for the OAuth option.
>
> | Service | Provided as MCP? |
> | --- | --- |
> | `booking_system_mcp` (port 8084) | **Yes**: the MCP server |
> | `booking_system_rest` (8082), `galaxium-booking-web-app` (8083), `galaxium-booking-web-app-mcp` (8085) | No: REST API and web UIs |
> | `hr_database_backend` (8081), `hr_database_backend_java` (8089), `hr_database_frontend_java` (8090) | No: HR demo services |

`booking_system_mcp` can run in three access modes. Each mode has its own ready-to-run folder under `local-container/`, named after the service. The server reads the mode from the `AUTH_MODE` variable.

| Option | Folder | `AUTH_MODE` | What the client sends | Extra infrastructure |
| --- | --- | --- | --- | --- |
| 1. No auth | [`local-container/booking_system_mcp_no_auth/`](../local-container/booking_system_mcp_no_auth/README.md) | `none` | nothing | none |
| 2. Basic Auth | [`local-container/booking_system_mcp_basic_auth/`](../local-container/booking_system_mcp_basic_auth/README.md) | `basic` | `Authorization: Basic <base64(user:password)>` | none |
| 3. OAuth 2.0, no implicit flow | [`local-container/booking_system_mcp_oauth2_no_implicit_flow/`](../local-container/booking_system_mcp_oauth2_no_implicit_flow/README.md) | `oauth2` | `Authorization: Bearer <access token>` | Keycloak (token issuer) |

All three options are tested against the same MCP endpoint and toolset:

- Endpoint: `<MCP base URL>/mcp`
- Transport: MCP Streamable HTTP
- Tools: `list_flights`, `book_flight`, `get_bookings`, `cancel_booking`, `register_user`, `get_user_id`

Only the authentication changes between them.

## Scope of This Repository

This repository only provides the base infrastructure. Each option runs on its own and is verified here, independent of any consumer.

The watsonx Orchestrate integration lives in a separate repository: [galaxium-travels-watsonx-orchestrate-mcp-bob-guide](https://github.com/thomassuedbroecker/galaxium-travels-watsonx-orchestrate-mcp-bob-guide). That guide clones this repository into `infrastructure/`, starts one of these configurations, and registers the MCP server in watsonx Orchestrate Developer Edition.

Each folder README ends with an **Integration handover** table. It lists the values the consuming side needs and uses the guide's variable names (`MCP_REMOTE_BASE_SERVER_URL`, `MCP_REMOTE_SERVER_URL`).

## Which Option Fits Which Usage

| Usage | Option | Why |
| --- | --- | --- |
| Local development, demos, quick tool tests | 1. No auth | No setup. Never expose it beyond your machine. |
| Machine-to-machine integration with one shared service identity, no identity provider available | 2. Basic Auth | Simple. One static credential pair that every MCP request carries. |
| Machine-to-machine integration with an identity provider (for example watsonx Orchestrate with an OAuth connection) | 3. OAuth 2.0 `client_credentials` | Short-lived, signed tokens; secrets stay with the identity provider and can be rotated there. |
| Interactive user login in an MCP client (for example MCP Inspector) | 3. OAuth 2.0 `authorization_code` + PKCE | Browser login; the client discovers Keycloak through the server's OAuth metadata. |

## How a Request Is Checked

```text
Option 1  client ──POST /mcp──────────────────────────────▶ MCP server (no check)

Option 2  client ──POST /mcp + Basic header───────────────▶ MCP server
                                                              compares user:password
                                                              with BASIC_AUTH_USERNAME / _PASSWORD

Option 3  client ──client_credentials──▶ Keycloak ──token──▶ client
          client ──POST /mcp + Bearer token───────────────▶ MCP server
                                                              checks signature (Keycloak JWKS),
                                                              issuer and audience (booking-api)
```

A missing or wrong credential returns `401 Unauthorized` with a `WWW-Authenticate` challenge (`Basic` or `Bearer`). Business errors inside tool calls are returned as MCP tool results with `isError: true`, never as HTTP errors.

## Why "No Implicit Flow"

The OAuth 2.0 implicit grant returns tokens in the browser URL. OAuth 2.0 Security Best Current Practice (RFC 9700) deprecates it, and this repository does not allow it:

- Every Keycloak client in `local-container/keycloak/realm/galaxium-realm.json` has `implicitFlowEnabled: false`.
- The MCP server's OAuth metadata advertises only `response_types_supported: ["code"]`.
- `booking_system_mcp_oauth2_no_implicit_flow/verify.sh` asserts both points.

Use `client_credentials` for services and agents, and `authorization_code` with PKCE for interactive login. If an integrating platform offers an implicit-flow connection type, do not choose it.

## Quick Start (Any Option)

Run these from the repository root. Replace `<option>` with one of the three folder names.

```sh
cp local-container/<option>/mcp.env.template local-container/<option>/mcp.env   # optional, overrides defaults
bash local-container/<option>/start.sh
bash local-container/<option>/verify.sh
docker compose -f local-container/<option>/docker_compose.yaml down
```

All three folders publish the MCP server on host port `8084`, so run only one at a time, and not alongside the full stack in `local-container/docker_compose.yaml`. To use another port, set `MCP_HOST_PORT` in `mcp.env`. For option 3, also set `MCP_PUBLIC_BASE_URL` to match.

## Reaching the Server From watsonx Orchestrate Developer Edition

watsonx Orchestrate Developer Edition runs in its own containers. For those containers, `localhost` is the container itself, not your machine. The guide repository therefore addresses the MCP server through the host's LAN IP address:

```sh
export LOCAL_NET_IP="$(ipconfig getifaddr en0)"   # macOS; on Linux, use: hostname -I | awk '{print $1}'
export MCP_REMOTE_BASE_SERVER_URL="http://${LOCAL_NET_IP}:8084"       # connection URL (no path)
export MCP_REMOTE_SERVER_URL="${MCP_REMOTE_BASE_SERVER_URL}/mcp"      # toolkit import URL
```

| Option | What to do on this side |
| --- | --- |
| 1. No auth | Nothing; the server listens on all interfaces. |
| 2. Basic Auth | Nothing beyond the credentials; the server listens on all interfaces. |
| 3. OAuth 2.0 | Set `KEYCLOAK_PUBLIC_BASE_URL=http://<LAN IP>:8086` and `MCP_PUBLIC_BASE_URL=http://<LAN IP>:8084` in `mcp.env`, then restart. watsonx Orchestrate requests its token from the LAN IP. The token's issuer must therefore be the LAN IP URL, and the server only accepts tokens with that issuer. |

After the change, run `verify.sh` again; it checks against the configured URLs. If the LAN IP changes (for example, on another Wi-Fi network), repeat the option 3 step.

Replace the demo credentials before the server is reachable by anyone but you. For anything beyond a local network, use HTTPS. For IBM Code Engine deployments, see [`deployment/ibm-code-engine/`](../deployment/ibm-code-engine/); its default auth mode is `basic`.

## Related Documents

- Keycloak configuration, usage, and how to adjust it: [`local-container/keycloak/README.md`](../local-container/keycloak/README.md)
- Server configuration reference: [`booking_system_mcp/README.md`](../booking_system_mcp/README.md)
- Manual command-line auth checks: [`docs/manual_auth_check_using_the_commandline.md`](./manual_auth_check_using_the_commandline.md)
- Full stack compose variants: [`local-container/README.md`](../local-container/README.md)
