# watsonx Orchestrate Setup Guide for the Booking MCP Server

Updated: 2026-03-08
Audience: Beginner and intermediate builders

This guide explains how to connect IBM watsonx Orchestrate to the Booking MCP server in this repository by using OAuth 2.0 Client Credentials.

It covers:

- what the Booking MCP server expects
- why Client Credentials is the correct flow for this step
- how to prepare Keycloak
- how to create the watsonx Orchestrate connection
- how to import the remote MCP toolkit
- how to test and troubleshoot the setup

## 1. What You Are Connecting

The Booking MCP server in this project runs as a remote MCP server over `streamable-http` on the `/mcp` path.

Repository references:

- MCP endpoint and auth variables: [`../booking_system_mcp/README.md`](../booking_system_mcp/README.md)
- JWT validation logic: [`../booking_system_mcp/auth.py`](../booking_system_mcp/auth.py)
- MCP transport and OAuth metadata endpoints: [`../booking_system_mcp/mcp_server.py`](../booking_system_mcp/mcp_server.py)
- Public deployment example for IBM Code Engine: [`../deployment/ibm-code-engine/README.md`](../deployment/ibm-code-engine/README.md)
- Local Keycloak realm example: [`../local-container/keycloak/realm/galaxium-realm.json`](../local-container/keycloak/realm/galaxium-realm.json)

Current behavior in this repo:

- The MCP server listens on `/mcp`.
- Auth is enabled when `AUTH_ENABLED=true`.
- The server validates bearer tokens against:
  - `OIDC_ISSUER`
  - `OIDC_AUDIENCE`
  - `OIDC_JWKS_URL`
- The default audience used in this project is `booking-api`.
- The server also publishes OAuth discovery endpoints and a local registration endpoint for MCP-aware clients.

Important: watsonx Orchestrate must be able to reach your MCP server and your OAuth token endpoint over a public HTTPS URL. A local `localhost` URL will not work from the hosted watsonx Orchestrate service.

## 2. Why OAuth Client Credentials Is the Right Flow Here

### Short answer

Use Client Credentials because this specific step is machine-to-machine:

- watsonx Orchestrate acts as the client
- Keycloak acts as the authorization server
- the Booking MCP server acts as the protected resource
- no human needs to log in during each MCP call

### Why this matches the current repo

This repository already shows multiple OAuth-related patterns:

- `authorization_code` is used for interactive Inspector-style browser login flows
- `password` exists only for local demo/testing flows
- `client_credentials` is the best fit for service-to-service access from watsonx Orchestrate to the Booking MCP server

The MCP server advertises several grant types in [`../booking_system_mcp/mcp_server.py`](../booking_system_mcp/mcp_server.py), but that does not mean every client should use every flow. Each client should use the flow that matches its runtime behavior.

For watsonx Orchestrate:

- it is a confidential client
- it can safely store a client secret
- it needs an access token for backend calls
- it does not need a browser redirect to a human user for this step

### Why not Authorization Code here

Authorization Code is correct when:

- a user signs in through a browser
- redirect URIs are part of the flow
- the token should represent a signed-in user

That is useful for the local MCP Inspector flow in this repo, but it is not the best choice for a server-to-server watsonx Orchestrate connection.

### Why not Password flow here

The Password grant requires the client to know a real user password. That is a poor security choice for this integration because:

- the Orchestrate connection should authenticate as an application, not as a person
- the user password becomes an operational secret
- the flow is not the modern default for new integrations

### Why not Dynamic Client Registration here

The Booking MCP server exposes `/oauth/register` because some MCP clients use dynamic registration during interactive discovery and testing.

For watsonx Orchestrate, IBM documents that remote MCP supports OAuth 2.0 without Dynamic Client Registration. In practice, that means:

- you pre-create a confidential client in Keycloak
- you give watsonx Orchestrate the `client_id`, `client_secret`, and `token_url`
- watsonx Orchestrate fetches the access token directly

### Technical references

- OAuth 2.0 Authorization Framework, RFC 6749: Client Credentials flow is defined in Section 4.4.
  - https://www.rfc-editor.org/rfc/rfc6749
- OAuth 2.0 Bearer Token Usage, RFC 6750: bearer tokens are sent in the `Authorization: Bearer <token>` header.
  - https://www.rfc-editor.org/rfc/rfc6750
- OAuth 2.0 Authorization Server Metadata, RFC 8414: standard metadata for token, authorization, and related endpoints.
  - https://www.rfc-editor.org/rfc/rfc8414
- OAuth 2.0 Protected Resource Metadata, RFC 9728: standard metadata for protected resources such as the MCP server resource URL.
  - https://www.rfc-editor.org/rfc/rfc9728
- OAuth 2.0 Dynamic Client Registration, RFC 7591: useful background for understanding why `/oauth/register` exists, even though watsonx Orchestrate does not require it here.
  - https://www.rfc-editor.org/rfc/rfc7591

## 3. Recommended Architecture for This Step

```text
watsonx Orchestrate
    |
    | 1. POST token request (client_id + client_secret)
    v
Keycloak / OAuth server
    |
    | 2. access_token
    v
watsonx Orchestrate
    |
    | 3. POST /mcp with Authorization: Bearer <access_token>
    v
Booking MCP server
    |
    | 4. Validate token signature, issuer, and audience with JWKS
    v
Booking tools
```

In this project, the resource server check is:

- issuer must match `OIDC_ISSUER`
- token must validate against `OIDC_JWKS_URL`
- audience should include `booking-api`

## 4. Prerequisites

Before you start, make sure you have all of these:

1. A public Booking MCP server URL
   - Example: `https://<mcp-host>/mcp`
2. A public Keycloak realm URL
   - Example: `https://<keycloak-host>/realms/galaxium`
3. A public token endpoint
   - Example: `https://<keycloak-host>/realms/galaxium/protocol/openid-connect/token`
4. TLS certificates trusted by watsonx Orchestrate
5. A deployed MCP server with auth enabled
6. A Keycloak confidential client for watsonx Orchestrate
7. watsonx Orchestrate access with permission to manage connections and toolkits

Channel note:

- IBM documents OAuth-based connections for agents in the integrated watsonx Orchestrate web chat UI. Use that channel for validation unless your target environment explicitly documents broader support.

If you deploy this stack on IBM Code Engine, the repo already shows the main environment settings for the MCP server:

- `AUTH_ENABLED=true`
- `OIDC_ISSUER=https://<keycloak-host>/realms/galaxium`
- `OIDC_AUDIENCE=booking-api`
- `OIDC_JWKS_URL=https://<keycloak-host>/realms/galaxium/protocol/openid-connect/certs`
- `OIDC_AUTHORIZATION_SERVER_URL=https://<keycloak-host>/realms/galaxium`
- `MCP_PUBLIC_BASE_URL=https://<mcp-host>`

Important details:

- `MCP_PUBLIC_BASE_URL` should be the service base URL, not the `/mcp` path.
- The remote toolkit URL in watsonx Orchestrate must include `/mcp`.
- Do not use `localhost` for hosted watsonx Orchestrate.

## 5. Step 1: Create a Dedicated Keycloak Client for watsonx Orchestrate

You can technically reuse the demo client `web-app-proxy`, but that is not recommended for a shared or production-like Orchestrate setup.

Recommended new client:

- Client ID: `wxo_booking_mcp`

Why a separate client is better:

- separates Orchestrate credentials from the demo web app
- reduces accidental coupling between UI and agent integrations
- makes auditing easier
- follows least privilege more closely

### Keycloak settings

Create a confidential OpenID Connect client with these settings:

1. `Client ID`: `wxo_booking_mcp`
2. `Client authentication`: `On`
3. `Service accounts roles`: `On`
4. `Standard flow`: `Off`
5. `Direct access grants`: `Off`
6. `Valid redirect URIs`: not required for Client Credentials
7. Save the generated client secret

### Add the audience mapper

The Booking MCP server validates the `aud` claim against `booking-api`. That means the token used by watsonx Orchestrate must include `booking-api` as audience.

Important:

- Even though you are calling the Booking MCP server, the current repository configuration still expects the audience value `booking-api`.
- That is not a typo in this guide. It comes from the current server configuration in this repository.

In Keycloak:

1. Open client `wxo_booking_mcp`
2. Go to protocol mappers
3. Add mapper type `Audience`
4. Set included client audience to `booking-api`
5. Enable `Add to access token`

### Beginner note: client ID vs audience

These are different concepts:

- `client_id` identifies the application requesting the token
  - Example: `wxo_booking_mcp`
- `audience` identifies the target API or protected resource
  - Example: `booking-api`

watsonx Orchestrate authenticates as `wxo_booking_mcp`, but the token must still be valid for the Booking MCP server, so the audience must include `booking-api`.

## 6. Step 2: Verify the OAuth Token Before You Touch watsonx Orchestrate

Do this first. It saves time.

### Request a token manually

```bash
curl -s -X POST \
  "https://<keycloak-host>/realms/galaxium/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=wxo_booking_mcp" \
  -d "client_secret=<client-secret>"
```

Expected result:

- HTTP `200`
- JSON containing `access_token`

### Check the token payload

Verify these claims:

- `iss` matches `https://<keycloak-host>/realms/galaxium`
- `aud` includes `booking-api`
- `exp` is in the future

One simple local decode command:

```bash
python -c 'import base64, json, sys; p=sys.argv[1].split(".")[1]; p += "=" * (-len(p) % 4); print(json.dumps(json.loads(base64.urlsafe_b64decode(p)), indent=2))' "<access_token>"
```

### Test the MCP server directly

```bash
curl -i -X POST "https://<mcp-host>/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -H "Authorization: Bearer <access_token>" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"manual-check","version":"1.0.0"}}}'
```

Expected result:

- HTTP `200`
- JSON-RPC response with `serverInfo`
- an `mcp-session-id` response header

If this direct test fails, do not continue to watsonx Orchestrate yet. Fix the token or server configuration first.

## 7. Step 3: Create the watsonx Orchestrate Connection Definition

IBM watsonx Orchestrate connections have three parts:

- an `app_id`
- environment configuration (`draft`, optionally `live`)
- credentials

Recommended connection ID:

- `booking_mcp_keycloak`

Use only letters, numbers, and underscores in `app_id`.

### Connection YAML

Create a file such as `booking_mcp_keycloak.yaml`:

```yaml
spec_version: v1
kind: connection
app_id: booking_mcp_keycloak
environments:
  draft:
    kind: oauth_auth_client_credentials_flow
    type: team
    server_url: https://<mcp-host>
  live:
    kind: oauth_auth_client_credentials_flow
    type: team
    server_url: https://<mcp-host>
```

Why these values:

- `kind: oauth_auth_client_credentials_flow`
  - tells watsonx Orchestrate to obtain an access token by using the Client Credentials grant
- `type: team`
  - IBM recommends Team credentials for remote MCP OAuth imports
- `server_url`
  - use the MCP server base URL, not the token URL

Developer Edition note:

- Developer Edition only uses `draft`
- SaaS and on-prem can use both `draft` and `live`

## 8. Step 4: Import the Connection and Set Credentials

### CLI path

Import the connection:

```bash
orchestrate connections import -f booking_mcp_keycloak.yaml
```

Set credentials for `draft`:

```bash
orchestrate connections set-credentials -a booking_mcp_keycloak \
  --env draft \
  --client-id "wxo_booking_mcp" \
  --client-secret "<client-secret>" \
  --token-url "https://<keycloak-host>/realms/galaxium/protocol/openid-connect/token" \
  --send-via header
```

If you also use a live environment:

```bash
orchestrate connections set-credentials -a booking_mcp_keycloak \
  --env live \
  --client-id "wxo_booking_mcp" \
  --client-secret "<client-secret>" \
  --token-url "https://<keycloak-host>/realms/galaxium/protocol/openid-connect/token" \
  --send-via header
```

If your IdP requires a scope, add:

```bash
--scope "<scope-value>"
```

For the Keycloak setup described in this guide, scope is often not required for Client Credentials, so you can usually omit it.

### Why `--send-via header`

The Booking MCP server metadata advertises support for:

- `client_secret_basic`
- `client_secret_post`

`--send-via header` is the natural first choice because it maps to sending client credentials in the authorization header to the token endpoint. If your Keycloak policy requires posting credentials in the request body instead, switch to:

```bash
--send-via body
```

### UI path

IBM documents that connection credentials can also be managed in the UI under `Manage -> Connections`, but there is an important limitation:

- in watsonx Orchestrate Developer Edition, OAuth credentials must be set by CLI
- full UI credential management is available in SaaS and on-prem offerings

If you use the UI, enter the same values:

| UI Field | Value |
| --- | --- |
| Authentication type | OAuth Client Credentials |
| Connection scope | Team |
| Server URL | `https://<mcp-host>` |
| Client ID | `wxo_booking_mcp` |
| Client Secret | `<client-secret>` |
| Token URL | `https://<keycloak-host>/realms/galaxium/protocol/openid-connect/token` |
| Send credentials via | `header` |
| Scope | blank unless your IdP requires one |

## 9. Step 5: Import the Remote MCP Toolkit

Creating the connection alone is not enough. You still need to add the remote MCP toolkit and associate it with the connection `app_id`.

This project uses:

- transport: `streamable_http`
- server URL: `https://<mcp-host>/mcp`

CLI example:

```bash
orchestrate toolkits add --kind mcp \
  --name galaxium_booking \
  --description "Galaxium Booking MCP toolkit" \
  --url "https://<mcp-host>/mcp" \
  --transport "streamable_http" \
  --tools "*" \
  --app-id booking_mcp_keycloak
```

Expected result:

- watsonx Orchestrate connects to the remote MCP server
- it acquires an OAuth token by using the associated connection
- it imports the exposed Booking MCP tools

If the import fails with a 401 or 403 error:

- the token request likely failed
- the token audience is wrong
- the MCP URL is wrong
- the MCP server is not reachable from watsonx Orchestrate

## 10. Step 6: Attach the Toolkit to an Agent and Test It

Once the toolkit is imported:

1. Open your agent in watsonx Orchestrate
2. Add the imported toolkit or its tools
3. Save the agent
4. Test from the integrated watsonx Orchestrate web chat UI

Good first tests:

- `list_flights`
- `get_bookings`

Reason:

- they are easier to validate
- they do not change booking data as aggressively as `book_flight` or `cancel_booking`

## 11. What Flow Should You Use at Each Stage?

Use this as a quick decision table:

| Situation | Recommended Flow | Reason |
| --- | --- | --- |
| watsonx Orchestrate to Booking MCP server | Client Credentials | machine-to-machine, shared service identity |
| Local MCP Inspector with browser redirect | Authorization Code | interactive login with redirect URI |
| Demo user login in local web app | Authorization Code or app-specific login flow | user-facing browser session |
| Password-based demo shortcut | Password | local demo only, not preferred for new integrations |

## 12. Troubleshooting

### Problem: `401 Unauthorized` during toolkit import

Likely causes:

- wrong `client_id` or `client_secret`
- wrong token URL
- token audience does not include `booking-api`
- token issuer does not match `OIDC_ISSUER`

What to check:

1. Request a token manually
2. Decode the token
3. Verify `iss` and `aud`
4. Retry the direct `/mcp` `initialize` call with curl

### Problem: watsonx Orchestrate cannot reach the server

Likely causes:

- using `localhost`
- private-only URL
- invalid TLS certificate
- firewall or ingress rule blocks public access

### Problem: toolkit import times out

IBM documents a 30-second import wait for remote MCP tool discovery. Check:

- network reachability
- MCP server startup latency
- reverse proxy timeouts
- whether the server responds correctly on `/mcp`

### Problem: metadata points to the wrong host

Likely cause:

- `MCP_PUBLIC_BASE_URL` is wrong
- `OIDC_AUTHORIZATION_SERVER_URL` is wrong

In this repo, those values are important because the MCP server generates discovery metadata from them.

### Problem: audience mismatch

Symptom:

- token is valid in Keycloak, but MCP returns unauthorized

Fix:

- add an audience mapper so the token includes `booking-api`

### Problem: using the wrong URL in the wrong place

Use these exact patterns:

- Connection `server_url`: `https://<mcp-host>`
- Toolkit `--url`: `https://<mcp-host>/mcp`
- OAuth `token_url`: `https://<keycloak-host>/realms/galaxium/protocol/openid-connect/token`
- MCP public base URL env var: `https://<mcp-host>`

## 13. Security Recommendations

For a safer setup:

1. Use a dedicated confidential client for watsonx Orchestrate
2. Do not reuse the demo web client in shared environments
3. Rotate the client secret regularly
4. Restrict client scopes and roles to only what the MCP server needs
5. Use public HTTPS with trusted certificates
6. Keep `team` credentials only if shared server identity is acceptable
7. If you later need per-user downstream identity, move to a user-oriented flow instead of reusing Client Credentials

## 14. Minimal End-to-End Checklist

Use this checklist before you call the setup complete:

- Booking MCP server is deployed on public HTTPS
- `AUTH_ENABLED=true` on the MCP server
- `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` are correct
- `MCP_PUBLIC_BASE_URL` is the service root URL
- Keycloak client `wxo_booking_mcp` exists
- its service account is enabled
- its token includes audience `booking-api`
- manual token request works
- manual `/mcp` initialize works
- watsonx Orchestrate connection imported successfully
- credentials set successfully
- remote MCP toolkit imported successfully
- tools appear in the agent

## 15. Official References

IBM watsonx Orchestrate:

- Creating connections:
  - https://developer.watson-orchestrate.ibm.com/connections/build_connections
- Connection overview and auth support matrix:
  - https://developer.watson-orchestrate.ibm.com/connections/overview
- Importing remote MCP toolkits:
  - https://developer.watson-orchestrate.ibm.com/tools/toolkits/remote_mcp_toolkits

OAuth and related RFCs:

- RFC 6749, OAuth 2.0 Authorization Framework:
  - https://www.rfc-editor.org/rfc/rfc6749
- RFC 6750, Bearer Token Usage:
  - https://www.rfc-editor.org/rfc/rfc6750
- RFC 8414, Authorization Server Metadata:
  - https://www.rfc-editor.org/rfc/rfc8414
- RFC 9728, Protected Resource Metadata:
  - https://www.rfc-editor.org/rfc/rfc9728
- RFC 7591, Dynamic Client Registration:
  - https://www.rfc-editor.org/rfc/rfc7591

## 16. Final Recommendation

For the current step in this project, the cleanest setup is:

1. deploy the Booking MCP server publicly
2. create a dedicated Keycloak confidential client for watsonx Orchestrate
3. ensure the token audience includes `booking-api`
4. create a watsonx Orchestrate `oauth_auth_client_credentials_flow` connection with `team` credentials
5. import the remote MCP toolkit by using the connection `app_id`

That matches both:

- the current Booking MCP server implementation in this repo
- IBM watsonx Orchestrate remote MCP support for OAuth without Dynamic Client Registration
