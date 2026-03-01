# Start all server applications

>**Custom Docker-Compose** in watsonx Orchestrate it not official supported: https://developer.watson-orchestrate.ibm.com/developer_edition/custom_yaml
>**Important Note**: _Before starting watsonx Orchestrate Developer Edition with a custom Docker Compose file, make sure you understand every change in your configuration. The ADK doesn’t offers official support to custom Compose setups, so you’re responsible for troubleshooting any issues that arise._

* Simplified Architecture local containers in compose

![](/images/run-containers-03.png)

1. Insert followling commands

```sh
cd local-container
bash start-build-containers.sh
```

* Example output:

```sh
...
[+] Running 4/4
 ✔ Container keycloak             Created                                                                  0.0s 
 ✔ Container web_app              Created                                                                  0.0s 
 ✔ Container booking_system_rest  Created                                                                  0.0s 
 ✔ Container hr_database          Created                                                                  0.0s 
Attaching to keycloak, booking_system_rest, hr_database, web_app
web_app              |  * Serving Flask app 'app'
web_app              |  * Debug mode: on
web_app              | WARNING: This is a development server. Do not use it in a production deployment. Use a production WSGI server instead.
web_app              |  * Running on all addresses (0.0.0.0)
web_app              |  * Running on http://127.0.0.1:8083
web_app              |  * Running on http://172.18.0.2:8083
web_app              | Press CTRL+C to quit
web_app              |  * Restarting with stat
web_app              |  * Debugger is active!
web_app              |  * Debugger PIN: 626-306-471
booking_system_rest  | INFO:     Started server process [1]
booking_system_rest  | INFO:     Waiting for application startup.
booking_system_rest  | INFO:     Application startup complete.
booking_system_rest  | INFO:     Uvicorn running on http://0.0.0.0:8082 (Press CTRL+C to quit)
hr_database          | INFO:     Started server process [1]
hr_database          | INFO:     Waiting for application startup.
hr_database          | INFO:     Application startup complete.
hr_database          | INFO:     Uvicorn running on http://0.0.0.0:8081 (Press CTRL+C to quit)
...
```

The following image show the running server applications.

![](/images/run-containers-01.png)

## OAuth2/OIDC with Keycloak

The compose setup now starts a local Keycloak server for OAuth2/OIDC:

- URL: `http://localhost:8080`
- Admin user: `admin`
- Admin password: `admin`
- Realm imported at startup: `galaxium`

### Automated setup (default)

The setup is automated through realm import:

- Compose mounts [`keycloak/realm/galaxium-realm.json`](./keycloak/realm/galaxium-realm.json) into Keycloak.
- Keycloak starts with `start-dev --import-realm`.
- Realm `galaxium` and the required clients are created automatically.

Verify realm import:

```sh
curl -s http://localhost:8080/realms/galaxium/.well-known/openid-configuration
```

If this returns JSON, import worked.
If this returns `Realm does not exist`, follow the manual setup below.

### Verify Keycloak Is Enforced (Automated Test)

From `local-container/` run:

```sh
bash verify-keycloak-auth.sh
```

What this script verifies:

1. Keycloak and the booking API are reachable.
2. Calling `GET /flights` without a bearer token fails with `401`.
3. Calling `GET /flights` with a Keycloak-issued token succeeds with `200`.
4. The web app proxy (`/api/flights`) can obtain a token and call the booking API successfully.

If all checks pass, Keycloak is actively used to protect the booking API endpoints.

> Note: Tokens requested from `http://localhost:8080` may have an issuer mismatch with the booking API (`Invalid issuer`) because the API validates the in-network issuer (`http://keycloak:8080/...`). The script requests a token from inside the Docker network to avoid this mismatch.

### Manual setup fallback (if import fails)

Open `http://localhost:8080/admin` and log in with:

- user: `admin`
- password: `admin`

Create the realm:

1. Create realm `galaxium`.

Create client `booking-api`:

1. Create client with `Client ID = booking-api`.
2. Set `Client authentication = On`.
3. Set `Service accounts roles = On`.
4. Set `Standard flow = Off`.
5. Set `Direct access grants = Off`.
6. Save and keep the generated client secret (or set `booking-api-secret`).

Create client `web-app-proxy`:

1. Create client with `Client ID = web-app-proxy`.
2. Set `Client authentication = On`.
3. Set `Service accounts roles = On`.
4. Set `Standard flow = Off`.
5. Set `Direct access grants = Off`.
6. Set client secret to `web-app-proxy-secret` (Credentials tab).

Add audience mapper to `web-app-proxy`:

1. Open `web-app-proxy` client.
2. Add mapper type `Audience`.
3. Set included client audience to `booking-api`.
4. Enable `Add to access token`.

Optional demo user:

1. Create user `demo-user`.
2. Set password to `demo-user-password` and disable temporary password.

Configured OAuth2 clients:

- `booking-api`
- `web-app-proxy` (used by the Flask proxy to obtain client credentials tokens)

Test token request:

```sh
curl -s -X POST \
  http://localhost:8080/realms/galaxium/protocol/openid-connect/token \
  -d "grant_type=client_credentials" \
  -d "client_id=web-app-proxy" \
  -d "client_secret=web-app-proxy-secret"
```

The booking REST API now validates bearer tokens when `AUTH_ENABLED=true`.

* Simplified Architecture on Code Engine

![](/images/run-containers-on-code-engine-01.png)

## Deploying Without Docker Compose (Code Engine Example)

For a full non-compose setup guide (including Keycloak realm/client setup and required environment variables for both services), see:

- [`../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`](../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)

Important:

1. In this compose file, auth toggles are set to `AUTH_ENABLED=true` and `OAUTH2_ENABLED=true`.
2. Outside compose (for example Code Engine), you must set these toggles explicitly to keep the same behavior.

For an automated auth verification against deployed URLs (no Docker needed), run:

```sh
export BOOKING_API_BASE_URL=https://<booking-api-url>
export KEYCLOAK_TOKEN_URL=https://<keycloak-url>/realms/galaxium/protocol/openid-connect/token
export OIDC_CLIENT_ID=web-app-proxy
export OIDC_CLIENT_SECRET=<web-app-proxy-client-secret>
export WEB_APP_BASE_URL=https://<web-app-url>
bash verify-keycloak-auth-remote.sh
```
