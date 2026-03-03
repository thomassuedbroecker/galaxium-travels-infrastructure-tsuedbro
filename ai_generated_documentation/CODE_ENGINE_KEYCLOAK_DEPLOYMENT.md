# Keycloak Setup Without Docker Compose (IBM Cloud Code Engine Example)

This guide describes what is required to run the same authenticated setup as `local-container/docker_compose.yaml`, but without Docker Compose.

Target runtime example: IBM Cloud Code Engine.

## 1. Required Components

You need these running services:

1. **Keycloak** (realm: `galaxium`)
2. **Booking API** (`booking_system_rest`) with OIDC validation enabled
3. **Web App** (`galaxium-booking-web-app`) with OAuth2 client-credentials enabled

## 2. Keycloak Configuration (Must Match Compose Setup)

Create realm `galaxium` and these clients:

1. `booking-api`
2. `web-app-proxy`

Client settings:

1. `booking-api`:
   - Confidential client
   - Service accounts enabled
   - Standard flow disabled
   - Direct access grants disabled
   - Keep client secret (used only if needed for testing)
2. `web-app-proxy`:
   - Confidential client
   - Service accounts enabled
   - Standard flow enabled
   - Direct access grants enabled
   - Keep client secret (used by the web app)

Audience mapper on `web-app-proxy`:

1. Add mapper type `Audience`
2. Included client audience: `booking-api`
3. Add to access token: enabled

You can use [`local-container/keycloak/realm/galaxium-realm.json`](../local-container/keycloak/realm/galaxium-realm.json) as the reference configuration.

## 3. Environment Variables Required Outside Compose

These variables are the minimum needed to preserve Keycloak authentication behavior.

Important:

1. `AUTH_ENABLED` and `OAUTH2_ENABLED` are explicit feature toggles.
2. Outside Docker Compose, you must set both toggles to `true` to match the compose behavior.
3. Set `FRONTEND_AUTH_REQUIRED=true` to enforce traveler login in the browser UI.

### Booking API (`booking_system_rest`)

1. `AUTH_ENABLED=true`
2. `OIDC_ISSUER=https://<your-keycloak-host>/realms/galaxium`
3. `OIDC_AUDIENCE=booking-api`
4. `OIDC_JWKS_URL=https://<your-keycloak-host>/realms/galaxium/protocol/openid-connect/certs`

### Web App (`galaxium-booking-web-app`)

1. `BACKEND_URL=https://<your-booking-api-host>`
2. `OAUTH2_ENABLED=true`
3. `FRONTEND_AUTH_REQUIRED=true`
4. `OIDC_TOKEN_URL=https://<your-keycloak-host>/realms/galaxium/protocol/openid-connect/token`
5. `OIDC_CLIENT_ID=web-app-proxy`
6. `OIDC_CLIENT_SECRET=<web-app-proxy-client-secret>`
7. `FLASK_SECRET_KEY=<strong-random-secret>`
8. Optional: `OIDC_SCOPE=openid profile email`

## 4. IBM Cloud Code Engine Example

### Prerequisites

1. `ibmcloud` CLI installed
2. Code Engine plugin installed
3. Logged in and project selected

Example:

```bash
ibmcloud login --apikey <YOUR_API_KEY> -r us-south
ibmcloud target -g <YOUR_RESOURCE_GROUP>
ibmcloud ce project create --name <PROJECT_NAME>
ibmcloud ce project select --name <PROJECT_NAME>
```

### Deploy Booking API

```bash
ibmcloud ce application create \
  --name booking-system-rest \
  --build-source https://github.com/thomassuedbroecker/galaxium-travels-infrastructure.git \
  --build-context-dir booking_system_rest \
  --strategy dockerfile \
  --port 8082 \
  --env AUTH_ENABLED=true \
  --env OIDC_ISSUER=https://<your-keycloak-host>/realms/galaxium \
  --env OIDC_AUDIENCE=booking-api \
  --env OIDC_JWKS_URL=https://<your-keycloak-host>/realms/galaxium/protocol/openid-connect/certs
```

### Deploy Web App

```bash
ibmcloud ce application create \
  --name galaxium-booking-web-app \
  --build-source https://github.com/thomassuedbroecker/galaxium-travels-infrastructure.git \
  --build-context-dir galaxium-booking-web-app \
  --strategy dockerfile \
  --port 8083 \
  --env BACKEND_URL=https://<booking-system-rest-url> \
  --env OAUTH2_ENABLED=true \
  --env FRONTEND_AUTH_REQUIRED=true \
  --env OIDC_TOKEN_URL=https://<your-keycloak-host>/realms/galaxium/protocol/openid-connect/token \
  --env OIDC_CLIENT_ID=web-app-proxy \
  --env OIDC_CLIENT_SECRET=<web-app-proxy-client-secret> \
  --env FLASK_SECRET_KEY=<strong-random-secret>
```

## 5. Verification

### Manual checks

1. No token should fail:

```bash
curl -i https://<booking-system-rest-url>/flights
```

Expected: HTTP `401` with `Missing bearer token`.

2. Token request from Keycloak:

```bash
curl -s -X POST \
  https://<your-keycloak-host>/realms/galaxium/protocol/openid-connect/token \
  -d "grant_type=client_credentials" \
  -d "client_id=web-app-proxy" \
  -d "client_secret=<web-app-proxy-client-secret>"
```

3. Call booking API with bearer token:

```bash
curl -H "Authorization: Bearer <access_token>" \
  https://<booking-system-rest-url>/flights
```

Expected: HTTP `200` and flight data.

4. Browser app requires traveler login:

```bash
curl -i https://<galaxium-booking-web-app-url>/
```

Expected: HTTP `302` redirect to `/login`.

### Automated check script (works without Docker Compose)

Use [`local-container/verify-keycloak-auth-remote.sh`](../local-container/verify-keycloak-auth-remote.sh):

```bash
export BOOKING_API_BASE_URL=https://<booking-system-rest-url>
export KEYCLOAK_TOKEN_URL=https://<your-keycloak-host>/realms/galaxium/protocol/openid-connect/token
export OIDC_CLIENT_ID=web-app-proxy
export OIDC_CLIENT_SECRET=<web-app-proxy-client-secret>
export WEB_APP_BASE_URL=https://<galaxium-booking-web-app-url>
# Optional: verify post-login frontend call
# export TRAVELER_USERNAME=<traveler-username>
# export TRAVELER_PASSWORD=<traveler-password>
bash local-container/verify-keycloak-auth-remote.sh
```

## 6. Common Pitfalls

1. **Issuer mismatch (`Invalid issuer`)**:
   - `OIDC_ISSUER` in booking API and `iss` claim in token must use the same URL host.
2. **Audience mismatch**:
   - Ensure `booking-api` appears in token audience (audience mapper on `web-app-proxy`).
3. **Missing web-app client secret**:
   - Web app fails with `auth_error` when it cannot obtain token.
