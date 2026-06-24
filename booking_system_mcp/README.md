# Booking MCP Server

| | |
| --- | --- |
| **Port** | `8084` |
| **Entry point** | `mcp_server.py` |
| **Auth config** | `AUTH_MODE=none` (default) · `oauth2` · `basic` |
| **Local run** | `python mcp_server.py` |
| **Test command** | n/a (use compose smoke scripts) |
| **Compose service** | `booking_system_mcp` |

This directory contains the MCP version of the booking system.

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

Optional metadata overrides:

- `OIDC_AUTHORIZATION_SERVER_URL=http://localhost:8086/realms/galaxium`
- `MCP_PUBLIC_BASE_URL=http://localhost:8084`

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
