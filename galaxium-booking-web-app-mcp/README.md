# Galaxium Booking Web App MCP

Flask UI that preserves the existing traveler experience but invokes booking tools through a direct Python MCP client integration.

The existing REST-backed app in `../galaxium-booking-web-app/` remains unchanged.
This MCP-backed app always requires OAuth and traveler login. Insecure local mode is not supported.

## Run Locally

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r app/requirements.txt
source .env-template
cd app
python app.py
```

Default URL: `http://localhost:8085`

## Security Model

- OAuth is mandatory.
- Traveler login is mandatory.
- MCP tool calls always reuse the authenticated traveler bearer token.

## Implementation Overview

This application is the MCP-backed variant of the booking UI. It keeps the same traveler-facing web experience, but replaces the previous booking backend integration with direct MCP tool calls from the application service layer.

### Main Components

- `app/app.py`
  - Runs the Flask web application.
  - Handles routes, login redirects, session state, and authenticated traveler context.
  - Calls the booking service layer for booking operations instead of talking to a REST booking backend.
- `app/booking_mcp_service.py`
  - Implements the explicit MCP integration required by this application.
  - Opens the Python MCP client connection to the booking MCP server.
  - Passes the traveler bearer token to the MCP server on every tool call.
  - Calls fixed MCP tools directly. No agent, planner, or autonomous tool selection is used.

### Why The Service Layer Exists

`booking_mcp_service.py` is required because this application must invoke MCP tools explicitly from the application service layer. That service centralizes:

- MCP client session setup and cleanup
- OAuth bearer token forwarding
- explicit tool-to-method mapping
- normalization of MCP SDK response payloads
- translation of MCP/tool failures into stable application errors

Without this layer, the Flask routes would need to duplicate MCP transport logic, token handling, and error handling.

### MCP Tools Used

The service layer calls these booking backend tools directly:

- `list_flights`
- `get_user_id`
- `register_user`
- `book_flight`
- `get_bookings`
- `cancel_booking`

### Request Flow

1. The traveler signs in through Keycloak.
2. Flask stores the authenticated session and access token.
3. A UI action calls a Flask route in `app.py`.
4. The route calls `BookingMcpService`.
5. `BookingMcpService` invokes the required MCP tool explicitly with the traveler token.
6. The tool result is normalized and returned to the UI response.

### Implementation Constraints

- OAuth is always enabled.
- Frontend authentication is always required.
- The booking backend is the MCP server and its tools.
- No insecure mode is supported for this app.
- No agent-based orchestration is allowed in the booking path.

## Required Environment Variables

- Always:
  - `MCP_SERVER_URL`
  - `OAUTH2_ENABLED=true`
  - `FRONTEND_AUTH_REQUIRED=true`
  - `OIDC_TOKEN_URL`
  - `OIDC_CLIENT_ID`
  - `OIDC_CLIENT_SECRET`
  - `FLASK_SECRET_KEY`
  - `PORT` optional, defaults to `8085`
  - `MCP_TIMEOUT_SECONDS` optional
  - `OIDC_SCOPE` optional

The local compose stack sets the Keycloak-enabled values automatically.

## Compose Usage

Compose service name: `web_app_mcp`

- Local compose stack: see [../QUICKSTART.md](../QUICKSTART.md), option 1.
- VM/LAN OAuth host stack: see [../QUICKSTART.md](../QUICKSTART.md), option 2.
- MCP-backed frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.yaml up --build \
    keycloak booking_system_mcp web_app_mcp
  ```

Default compose URL: `http://localhost:8085`

## Related Docs

- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose flow: [../local-container/README.md](../local-container/README.md)
- Advanced deployment notes: [../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md](../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)
