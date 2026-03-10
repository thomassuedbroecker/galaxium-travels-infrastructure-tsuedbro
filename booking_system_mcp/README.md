# Booking MCP Server

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

Set these variables to require bearer tokens:

- `AUTH_ENABLED=true`
- `OIDC_ISSUER=http://localhost:8080/realms/galaxium`
- `OIDC_AUDIENCE=booking-api`
- `OIDC_JWKS_URL=http://localhost:8080/realms/galaxium/protocol/openid-connect/certs`

Optional metadata overrides:

- `OIDC_AUTHORIZATION_SERVER_URL=http://localhost:8080/realms/galaxium`
- `MCP_PUBLIC_BASE_URL=http://localhost:8084`

## Quick Validation

- Start the local compose stack from `../local-container`.
- Run `bash ../local-container/verify-keycloak-auth-mcp.sh`.
- Optionally use `python ../local-container/mcp_test_app.py`.

## Compose Usage

Compose service name: `booking_system_mcp`

- Local compose stack: see [../QUICKSTART.md](../QUICKSTART.md), option 1.
- VM/LAN OAuth host stack: see [../QUICKSTART.md](../QUICKSTART.md), option 2.
- MCP-backed frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.yaml up --build \
    keycloak booking_system_mcp web_app_mcp
  ```

## Related Docs

- Error-handling notes: [../booking_system_rest/docs/error-handling-guide.md](../booking_system_rest/docs/error-handling-guide.md)
- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose flow: [../local-container/README.md](../local-container/README.md)
