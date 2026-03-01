# Galaxium Booking Web App

This web application proxies requests to `booking_system_rest`.

![](/images/run-containers-02.gif)

## Security Behavior

The web app authentication is controlled by environment variable.

- `OAUTH2_ENABLED=false` (default): no Keycloak token is requested by this web app
- `OAUTH2_ENABLED=true`: web app requests a Keycloak token and forwards it to the backend API
- If OAuth2 is enabled and required OIDC settings are missing, startup fails fast

Important distinction:

1. `OAUTH2_ENABLED=true` enforces **service-to-service auth** (`web_app -> booking_system_rest`).
2. It does **not** enforce a browser-user login in the UI.
3. Therefore users can still use the UI without a login prompt, while backend calls are authenticated by the server-side client credentials flow.

Required environment variables when OAuth2 is enabled:

1. `BACKEND_URL`
2. `OIDC_TOKEN_URL`
3. `OIDC_CLIENT_ID`
4. `OIDC_CLIENT_SECRET`

Compose behavior:

1. `local-container/docker_compose.yaml` sets `OAUTH2_ENABLED=true` for the `web_app` container.
2. If you run outside compose (for example Code Engine), you must set `OAUTH2_ENABLED=true` yourself.

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
  -e OIDC_TOKEN_URL="${OIDC_TOKEN_URL}" \
  -e OIDC_CLIENT_ID="${OIDC_CLIENT_ID}" \
  -e OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET}" \
  galaxium-booking-web-app
```

4. Open `http://localhost:8083`.

## IBM Code Engine / Non-Compose Deployment

Use this guide for the complete setup (Keycloak realm + clients + booking API + web app + verification):

- [`../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`](../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)

Notebook-based deployment is still available:

- `deployment_web_application_server.ipynb`
