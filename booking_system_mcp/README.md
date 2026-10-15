# Booking MCP Server

| | |
| --- | --- |
| **Port** | `8084` |
| **Entry point** | `mcp_server.py` |
| **Auth config** | `AUTH_MODE=none` (default) · `oauth2` · `basic` |
| **Local run** | `python mcp_server.py` |
| **Test command** | n/a (use compose smoke scripts) |
| **Compose service** | `booking_system_mcp` |

This directory contains the MCP version of the booking system. It is the **only service in this repository that is provided as MCP**. External MCP clients such as watsonx Orchestrate connect only to this service.

`mcp_server.py` is the active server entry point.
`app.py` is a legacy reference file and is not used by the compose stack.

## Run Locally

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python mcp_server.py
```

Default endpoint: `http://localhost:8084/mcp`

## Exposed Tools

- `list_flights`
- `book_flight`
- `get_bookings`
- `cancel_booking`
- `register_user`
- `get_user_id`

## Auth

Auth is off by default.

Ready-to-run configurations for each mode (compose file, env template, verify script, integration handover values) are in `../local-container/booking_system_mcp_no_auth/`, `booking_system_mcp_basic_auth/` and `booking_system_mcp_oauth2_no_implicit_flow/`. For which one to choose, see [../docs/mcp_access_options.md](../docs/mcp_access_options.md).

Use one of these modes:

- `AUTH_MODE=none`
- `AUTH_MODE=oauth2`
- `AUTH_MODE=basic`

For backward compatibility, `AUTH_ENABLED=true` still enables the OAuth mode when `AUTH_MODE` is not set.

Set these variables to require bearer tokens:

- `AUTH_MODE=oauth2`
- `OIDC_ISSUER=http://localhost:8086/realms/galaxium`
- `OIDC_AUDIENCE=booking-api`
- `OIDC_JWKS_URL=http://localhost:8086/realms/galaxium/protocol/openid-connect/certs`

Set these variables to require Basic Auth:

- `AUTH_MODE=basic`
- `BASIC_AUTH_USERNAME=demo-basic-user`
- `BASIC_AUTH_PASSWORD=demo-basic-password`
- `BASIC_AUTH_REALM` (optional; default `Galaxium Booking MCP`) — realm sent in the `WWW-Authenticate` challenge

Optional metadata overrides:

- `OIDC_AUTHORIZATION_SERVER_URL=http://localhost:8086/realms/galaxium`
- `OIDC_PUBLIC_ISSUER` — fallback for `OIDC_AUTHORIZATION_SERVER_URL` when that is unset
- `MCP_PUBLIC_BASE_URL=http://localhost:8084`

If neither authorization-server variable is set, the server derives it from `OIDC_ISSUER` and rewrites `keycloak:8080` to `localhost:8086`.

MCP Inspector dynamic client registration (`/oauth/register`, OAuth mode only):

| Variable | Default | Purpose |
|---|---|---|
| `OIDC_INSPECTOR_CLIENT_ID` | `OIDC_CLIENT_ID`, else `web-app-proxy` | Client ID returned to the Inspector |
| `OIDC_INSPECTOR_CLIENT_SECRET` | `OIDC_CLIENT_SECRET`, else `web-app-proxy-secret` | Client secret returned to the Inspector |
| `OIDC_INSPECTOR_REDIRECT_URIS` | `http://localhost:6274/oauth/callback`, `.../callback/debug`, and the same on `127.0.0.1` | Comma-separated redirect URIs |

CORS (applies to every auth mode):

| Variable | Default |
|---|---|
| `MCP_CORS_ALLOW_ORIGIN` | `*` |
| `MCP_CORS_ALLOW_HEADERS` | `Authorization, Content-Type, MCP-Protocol-Version, mcp-protocol-version` |
| `MCP_CORS_ALLOW_METHODS` | `GET, POST, OPTIONS` |
| `MCP_CORS_EXPOSE_HEADERS` | `WWW-Authenticate` |

OAuth metadata endpoints are only exposed in `AUTH_MODE=oauth2`. In Basic Auth mode, keep the MCP transport on `Streamable HTTP` and send the `Authorization: Basic ...` header directly.

## Quick Validation

- Start the local compose stack from `../local-container`.
- Run `bash ../local-container/verify-keycloak-auth-mcp.sh`.
- Optionally use `python ../local-container/mcp_test_app.py`.
- For the Basic Auth variant, run `bash ../local-container/verify-basic-auth-backends.sh`.
- For the Basic Auth frontend plus inspector path, run `bash ../local-container/verify-basic-auth-frontends-and-inspector.sh`.

## Compose Usage

Compose service name: `booking_system_mcp`

- Local compose stack: see [../QUICKSTART.md](../QUICKSTART.md), option 1.
- VM/LAN OAuth host stack: see [../QUICKSTART.md](../QUICKSTART.md), option 2.
- Local Basic Auth stack: see [../local-container/README.md](../local-container/README.md), option 3.
- MCP-backed frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.yaml up --build \
    keycloak booking_system_mcp web_app_mcp
  ```

- MCP Basic Auth path only:

  ```sh
  docker compose -f ../local-container/docker_compose.basic-auth.yaml up --build \
    booking_system_mcp
  ```

## Related Docs

- Error-handling notes: [../booking_system_rest/docs/error-handling-guide.md](../booking_system_rest/docs/error-handling-guide.md)
- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose flow: [../local-container/README.md](../local-container/README.md)

## Booking Data On Restart

Every backend startup calls `seed()`, which deletes existing bookings, users,
and flights before inserting demo data. Restarting a REST or MCP backend
therefore discards changes in that backend, even if its SQLite file survives.
The two backends maintain separate databases.
