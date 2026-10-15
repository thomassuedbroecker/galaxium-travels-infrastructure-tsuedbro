# Option 3: Booking MCP Server With OAuth 2.0 (No Implicit Flow)

| | |
| --- | --- |
| **Server mode** | `AUTH_MODE=oauth2` |
| **Use for** | Machine-to-machine access with an identity provider (`client_credentials`), and interactive login (`authorization_code` + PKCE) |
| **Not allowed** | Implicit flow (disabled in Keycloak and absent from the server's metadata) |
| **Client sends** | `Authorization: Bearer <access token>` on every request |
| **Containers** | `keycloak_mcp_oauth2` (port `8086`), `booking_system_mcp_oauth2` (port `8084`) |

> **Scope:** `booking_system_mcp` is the only service in this repository that is provided as MCP. This folder starts only that service and none of the REST, web UI, or HR services. For the comparison of all three access options, see [docs/mcp_access_options.md](../../docs/mcp_access_options.md).

## Which Grant to Use

| Client | Grant | How the client gets the token |
| --- | --- | --- |
| Service, agent, or integration platform (for example watsonx Orchestrate) | `client_credentials` | Posts its client ID and secret to the token URL |
| Interactive MCP client (for example MCP Inspector) | `authorization_code` + PKCE | Discovers Keycloak through `/.well-known/oauth-protected-resource`, then performs a browser login |
| — | implicit | **Not allowed**, so never configure it |

## Start, Verify, Stop

Run from the repository root:

```sh
cp local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env.template \
   local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env          # optional
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/start.sh
bash local-container/booking_system_mcp_oauth2_no_implicit_flow/verify.sh
docker compose -f local-container/booking_system_mcp_oauth2_no_implicit_flow/docker_compose.yaml down
```

Keycloak imports the realm from `../keycloak/realm/galaxium-realm.json`. **What is configured there, and how to adjust it (for example, a dedicated watsonx Orchestrate client), is documented in [../keycloak/README.md](../keycloak/README.md).** On first start it needs about 30 seconds before it issues tokens. `verify.sh` waits for it.

`verify.sh` checks that:

- every Keycloak client in the realm import has `implicitFlowEnabled: false`
- the MCP OAuth metadata advertises `response_types_supported: ["code"]`, includes `client_credentials` and `authorization_code`, and contains no implicit grant
- a request with no token, a Basic header, or an invalid token gets `401` with a `WWW-Authenticate: Bearer` challenge
- a `client_credentials` token is issued with issuer `KEYCLOAK_PUBLIC_BASE_URL/realms/galaxium`
- an MCP session opens with that token, and `tools/list` returns the booking tools

To get a token for manual tests:

```sh
export GALAXIUM_MCP_ACCESS_TOKEN="$(bash local-container/booking_system_mcp_oauth2_no_implicit_flow/get-token.sh)"
```

## How Token Validation Works

The MCP server accepts a bearer token only when all of these hold:

1. The signature verifies against Keycloak's JWKS keys, which the server fetches internally from `http://keycloak:8080/...`.
2. `iss` equals `OIDC_ISSUER`, which is `KEYCLOAK_PUBLIC_BASE_URL/realms/galaxium`.
3. `aud` contains `booking-api`. The realm's `web-app-proxy` client adds this audience through a protocol mapper.

Keycloak runs with `--hostname=KEYCLOAK_PUBLIC_BASE_URL`, so it always issues tokens with that public issuer, whether the token is requested from the host or from inside the Docker network. **`KEYCLOAK_PUBLIC_BASE_URL` must therefore be the Keycloak URL your clients actually call.** Otherwise every token is rejected with an issuer mismatch.

## Configuration

`mcp.env` is git-ignored.

| Variable | Default | Purpose |
| --- | --- | --- |
| `KEYCLOAK_PUBLIC_BASE_URL` | `http://localhost:8086` | Keycloak URL that clients use; it defines the token issuer |
| `MCP_PUBLIC_BASE_URL` | `http://localhost:8084` | MCP URL that clients use; it is advertised in the OAuth metadata |
| `KEYCLOAK_REALM_DIR` | `../keycloak/realm` | Realm import folder; supply your own to change clients or secrets without editing this repo |
| `OIDC_CLIENT_ID` | `web-app-proxy` | Client for `client_credentials` (used by `get-token.sh` and `verify.sh`) |
| `OIDC_CLIENT_SECRET` | `web-app-proxy-secret` | Secret of that client |
| `MCP_HOST_PORT` | `8084` | Host port for the MCP server |
| `KEYCLOAK_HOST_PORT` | `8086` | Host port for Keycloak |

Fixed in `docker_compose.yaml`: `AUTH_MODE=oauth2`, `OIDC_AUDIENCE=booking-api`, and `OIDC_JWKS_URL` (internal Keycloak URL). For every server variable, see [booking_system_mcp/README.md](../../booking_system_mcp/README.md#auth).

## Integration Handover (client_credentials)

These are the values for the consuming side, for example the [watsonx Orchestrate guide repository](https://github.com/thomassuedbroecker/galaxium-travels-watsonx-orchestrate-mcp-bob-guide).

watsonx Orchestrate Developer Edition runs in containers and cannot use `localhost`. First point both public URLs at the host's LAN IP and restart:

```sh
LOCAL_NET_IP="$(ipconfig getifaddr en0)"   # macOS; on Linux, use: hostname -I | awk '{print $1}'
# in local-container/booking_system_mcp_oauth2_no_implicit_flow/mcp.env:
export KEYCLOAK_PUBLIC_BASE_URL=http://${LOCAL_NET_IP}:8086
export MCP_PUBLIC_BASE_URL=http://${LOCAL_NET_IP}:8084
```

Write the actual IP into `mcp.env`. Then run `start.sh` and `verify.sh` again; `verify.sh` confirms that tokens now carry the LAN IP issuer.

| Value | Setting |
| --- | --- |
| `MCP_REMOTE_BASE_SERVER_URL` (connection) | `http://<LAN IP>:8084` (no path) |
| `MCP_REMOTE_SERVER_URL` (toolkit import) | `http://<LAN IP>:8084/mcp` |
| Transport | `streamable_http` |
| Connection kind | `oauth_auth_client_credentials_flow`, team credentials |
| Token URL | `http://<LAN IP>:8086/realms/galaxium/protocol/openid-connect/token`; the host must match `KEYCLOAK_PUBLIC_BASE_URL` exactly |
| Client ID / secret | demo: `web-app-proxy` / `web-app-proxy-secret`; for your own setup, a confidential Keycloak client with service accounts enabled and an audience mapper for `booking-api` |
| Send credentials via | `header` (`client_secret_basic`); `body` (`client_secret_post`) also works |
| Scope | not required |

Do not choose the `oauth_auth_implicit_flow` or `oauth_auth_password_flow` connection kinds. For a dedicated Keycloak client instead of the demo client, follow the tested recipe in [../keycloak/README.md](../keycloak/README.md#recipe-dedicated-client-for-watsonx-orchestrate).

## Client Examples

| File | Grant | Notes |
| --- | --- | --- |
| [`mcp-client.client-credentials.json`](./mcp-client.client-credentials.json) | `client_credentials` | Sends `Bearer ${GALAXIUM_MCP_ACCESS_TOKEN}`; get the token with `get-token.sh`. Keycloak tokens expire after a few minutes. |
| [`mcp-client.authorization-code.json`](./mcp-client.authorization-code.json) | `authorization_code` + PKCE | URL only; the client discovers Keycloak through the server metadata and opens a browser login. The redirect URIs allowed in the realm are `http://localhost:6274/oauth/callback` and `http://127.0.0.1:6274/oauth/callback` (MCP Inspector). |

## Known Limitations

- The demo client `web-app-proxy` still has the password grant (`directAccessGrantsEnabled`) enabled, and the server's metadata lists `password` in `grant_types_supported`. Some legacy verify scripts in `local-container/` need it. Do not use the password grant for new integrations.
- The dynamic client registration endpoint (`/oauth/register`) only serves MCP Inspector. It returns the configured demo client and does not create Keycloak clients.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `401` with `Token validation failed: Invalid issuer` | The token was requested from a Keycloak URL other than `KEYCLOAK_PUBLIC_BASE_URL` |
| `401` with `Invalid audience` | The client has no `booking-api` audience mapper |
| Token request fails right after start | Keycloak is still importing the realm; wait about 30 seconds |
| Interactive login fails with `invalid redirect_uri` | The client's callback is not in the realm's `redirectUris` |
