# Galaxium Booking Web App

This web application proxies requests to `booking_system_rest`.

![](/images/run-containers-02.gif)

## Security Behavior

The web app authentication is controlled by environment variable.

- `OAUTH2_ENABLED=true`: web app can request Keycloak tokens for backend calls.
- `FRONTEND_AUTH_REQUIRED` defaults to `OAUTH2_ENABLED` if unset.
- `FRONTEND_AUTH_REQUIRED=true`: traveler login is mandatory in the browser UI.
- If OAuth2 is enabled and required OIDC settings are missing, startup fails fast.

Expected authenticated flow:

1. Unauthenticated browser access to `/` is redirected to `/login`.
2. Traveler logs in with Keycloak credentials in the frontend.
3. Web app stores traveler session and syncs traveler profile to booking backend.
4. Booking backend APIs are called with Keycloak bearer token.
5. Booking/list/cancel operations are available only with authenticated traveler session.

Required environment variables when OAuth2 is enabled:

1. `BACKEND_URL`
2. `OIDC_TOKEN_URL`
3. `OIDC_CLIENT_ID`
4. `OIDC_CLIENT_SECRET`
5. `FRONTEND_AUTH_REQUIRED` (`true` to require traveler login in UI)
6. `FLASK_SECRET_KEY` (required when `FRONTEND_AUTH_REQUIRED=true`)

Compose behavior:

1. `local-container/docker_compose.yaml` sets:
   - `OAUTH2_ENABLED=true`
   - `FRONTEND_AUTH_REQUIRED=true`
2. If you run outside compose (for example Code Engine), you must set these explicitly.

## Local Run With Docker

1. Go to the web app directory:

```sh
cd galaxium-booking-web-app
```

2. Create a local env file:

```sh
cp .env-template .env
source .env
```

3. Build and run:

```sh
docker build -t galaxium-booking-web-app .
docker run --rm -p 8083:8083 \
  -e BACKEND_URL="${BACKEND_URL}" \
  -e OAUTH2_ENABLED="${OAUTH2_ENABLED}" \
  -e FRONTEND_AUTH_REQUIRED="${FRONTEND_AUTH_REQUIRED}" \
  -e OIDC_TOKEN_URL="${OIDC_TOKEN_URL}" \
  -e OIDC_CLIENT_ID="${OIDC_CLIENT_ID}" \
  -e OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET}" \
  -e OIDC_SCOPE="${OIDC_SCOPE}" \
  -e FLASK_SECRET_KEY="${FLASK_SECRET_KEY}" \
  galaxium-booking-web-app
```

4. Open `http://localhost:8083` and login as traveler.

## IBM Code Engine / Non-Compose Deployment

Use this guide for the complete setup (Keycloak realm + clients + booking API + web app + verification):

- [`../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`](../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)

Notebook-based deployment is still available:

- `deployment_web_application_server.ipynb`
