# Galaxium Booking Web App

| | |
| --- | --- |
| **Port** | `8083` |
| **Entry point** | `app/app.py` |
| **Auth config** | `BACKEND_AUTH_MODE=none\|basic\|oauth2` · `FRONTEND_AUTH_REQUIRED=true\|false` |
| **Local run** | `cd app && python app.py` |
| **Test command** | n/a (use compose smoke scripts) |
| **Compose service** | `web_app` |

Flask UI that proxies requests to `booking_system_rest`.

## Run Locally

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r app/requirements.txt
source .env-template
cd app
python app.py
```

Default URL: `http://localhost:8083`

## Runtime Modes

- `BACKEND_AUTH_MODE=none` and `FRONTEND_AUTH_REQUIRED=false`
  - Simplest local mode.
  - Requests go straight to the backend without traveler login.
  - The UI can store a guest traveler profile in the browser session.

- `BACKEND_AUTH_MODE=basic` and `FRONTEND_AUTH_REQUIRED=false`
  - Shared Basic Auth mode.
  - The UI stores a guest traveler profile in the browser session and sends the shared Basic Auth header to the backend.

- `BACKEND_AUTH_MODE=oauth2` and `FRONTEND_AUTH_REQUIRED=false`
  - Service-to-service mode.
  - The web app requests backend tokens itself.
  - The UI can still store a guest traveler profile in the browser session.

- `BACKEND_AUTH_MODE=oauth2` and `FRONTEND_AUTH_REQUIRED=true`
  - Traveler login mode.
  - The browser is redirected to `/login` until the user authenticates.

## Required Environment Variables

- Always:
  - `BACKEND_URL`
  - `BACKEND_AUTH_MODE` optional

- When `BACKEND_AUTH_MODE=basic`:
  - `BASIC_AUTH_USERNAME`
  - `BASIC_AUTH_PASSWORD`

- When `BACKEND_AUTH_MODE=oauth2`:
  - `OIDC_TOKEN_URL`
  - `OIDC_CLIENT_ID`
  - `OIDC_CLIENT_SECRET`
  - `OIDC_SCOPE` optional

- When `FRONTEND_AUTH_REQUIRED=true`:
  - `FLASK_SECRET_KEY`

If `BACKEND_AUTH_MODE` is not set, the legacy `OAUTH2_ENABLED` flag is still supported for backward compatibility.

The local compose stacks set the required values automatically.

## Compose Usage

Compose service name: `web_app`

- Local compose stack: see [../QUICKSTART.md](../QUICKSTART.md), option 1.
- VM/LAN OAuth host stack: see [../QUICKSTART.md](../QUICKSTART.md), option 2.
- Local Basic Auth stack: see [../local-container/README.md](../local-container/README.md), option 3.
- REST-backed frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.yaml up --build \
    keycloak booking_system web_app
  ```

- REST-backed Basic Auth frontend path only:

  ```sh
  docker compose -f ../local-container/docker_compose.basic-auth.yaml up --build \
    booking_system web_app
  ```

Default compose URL: `http://localhost:8083`

## Related Docs

- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose flow: [../local-container/README.md](../local-container/README.md)
- Advanced deployment notes: [../docs/reference/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md](../docs/reference/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)
