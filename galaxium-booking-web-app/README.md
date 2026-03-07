# Galaxium Booking Web App

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

- `OAUTH2_ENABLED=false` and `FRONTEND_AUTH_REQUIRED=false`
  - Simplest local mode.
  - Requests go straight to the backend without traveler login.

- `OAUTH2_ENABLED=true` and `FRONTEND_AUTH_REQUIRED=false`
  - Service-to-service mode.
  - The web app requests backend tokens itself.

- `OAUTH2_ENABLED=true` and `FRONTEND_AUTH_REQUIRED=true`
  - Traveler login mode.
  - The browser is redirected to `/login` until the user authenticates.

## Required Environment Variables

- Always:
  - `BACKEND_URL`

- When `OAUTH2_ENABLED=true`:
  - `OIDC_TOKEN_URL`
  - `OIDC_CLIENT_ID`
  - `OIDC_CLIENT_SECRET`
  - `OIDC_SCOPE` optional

- When `FRONTEND_AUTH_REQUIRED=true`:
  - `FLASK_SECRET_KEY`

The local compose stack sets the Keycloak-enabled values automatically.

## Related Docs

- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Compose flow: [../local-container/README.md](../local-container/README.md)
- Advanced deployment notes: [../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md](../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)
