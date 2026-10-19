# Path B — OAuth2 Deployment

This document is the complete, self-contained deployment guide for
`STACK_AUTH_MODE=oauth2`.

**Read this file if:** you want to deploy the Galaxium Travels stack with Keycloak
as the identity provider, OAuth2 Bearer token validation on the API backends, and
OIDC browser login on both web UIs.

| Property | Value |
|---|---|
| **Entrypoint** | `deploy-stack-oauth2.sh` |
| **Env file** | `deploy.env.oauth2` (copy from `deploy.env.oauth2.template`) |
| **Keycloak** | deployed inside the same Code Engine project by default |
| **Browser login** | OIDC login required (`FRONTEND_AUTH_REQUIRED=true` by default) |
| **Scripts that run** | `00 → 01 → 02 → [02b] → 03 → 04 → 05 → 06` |
| **[02b] skips when** | `DEPLOY_ARTIFACT_MODE=source_build` (the default) |
| **03 skips when** | `KEYCLOAK_BASE_URL_OVERRIDE` is set (external Keycloak) |
| **05 skips when** | `KEYCLOAK_BASE_URL_OVERRIDE` is set (external Keycloak) |

> **Why script order is enforced:**
> Code Engine generates public HTTPS URLs only after an application is first created.
> Script `04` reads back the Keycloak URL before configuring the backends, then reads
> back the backend URLs before deploying the web UIs. Script `05` reads back the final
> web UI URLs before updating the Keycloak client redirect URIs. Reordering the scripts
> would break this URL resolution chain.

← Back to overview: [`README.md`](./README.md)
← Basic Auth path: [`DEPLOY-PATH-A-BASIC-AUTH.md`](./DEPLOY-PATH-A-BASIC-AUTH.md)

---

## B-1 · Install Required Local Tools

| Tool | Required |
|---|---|
| `bash` | always |
| `ibmcloud` CLI | always |
| IBM Cloud Code Engine plugin | always |
| `curl` | always |
| `jq` | always |
| IBM Cloud Container Registry plugin | `prebuilt_images` mode only |
| `docker` or `podman` | `prebuilt_images` mode only |

Install the IBM Cloud CLI:

```sh
curl -fsSL https://clis.cloud.ibm.com/install/osx | sh    # macOS
curl -fsSL https://clis.cloud.ibm.com/install/linux | sh   # Linux
```

Install the Code Engine plugin:

```sh
ibmcloud plugin install code-engine
```

For `DEPLOY_ARTIFACT_MODE=prebuilt_images` only, also install:

```sh
ibmcloud plugin install container-registry
```

Verify:

```sh
ibmcloud version
ibmcloud plugin show code-engine
```

---

## B-2 · Log In to IBM Cloud

**Option A — API key (non-interactive, recommended for automation):**

```sh
ibmcloud login --apikey <YOUR_API_KEY> -r us-south -g default
```

Set `IBM_CLOUD_API_KEY` in `deploy.env.oauth2` and the scripts will log in automatically on each run.

**Option B — Interactive browser login:**

```sh
ibmcloud login --sso
```

Leave `IBM_CLOUD_API_KEY` empty in `deploy.env.oauth2` when using this option.

---

## B-3 · Create and Fill In the Env File

### B-3a — Copy the template

```sh
cd deployment/ibm-code-engine
cp deploy.env.oauth2.template deploy.env.oauth2
```

### B-3b — Generate the secrets you need

All three secrets must be generated before editing the file.

```sh
# 1. FLASK_SECRET_KEY — Flask session signing key
python3 -c "import secrets; print(secrets.token_hex(32))"
# example: 9d3e6a2c5f8b1d4e7a4a7f2c9e1b3d8a0f5e6c2d1b9a4f7e3c8b2d5a1e0f4c7b

# 2. KEYCLOAK_ADMIN_PASSWORD — Keycloak admin console password
#    Choose a strong value, e.g.:
python3 -c "import secrets, string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(24)))"
# example: Xk7mP2nRvQ9wLdF3aYcH8bJs

# 3. OIDC_CLIENT_SECRET — OAuth2 client secret for the web-app-proxy Keycloak client
#    This value MUST match the client secret configured in the Keycloak realm import.
#    Check and update the realm file before changing it:
#      local-container/keycloak/realm/galaxium-realm.json
#    The default value already present in that file is what the scripts expect.
#    Only generate a new one if you intentionally update both files together.
```

> **Important:** `OIDC_CLIENT_SECRET` must match what is in
> [`local-container/keycloak/realm/galaxium-realm.json`](../../local-container/keycloak/realm/galaxium-realm.json).
> If you change it here, you must update the realm file **before** running the deployment —
> the realm is imported at step 3 (`02-config-and-secrets.sh`) and Keycloak will reject
> tokens if the secret does not match.

### B-3c — Fill in the required values

Open `deploy.env.oauth2` in your editor. The mandatory values to change from their defaults are:

| Variable | Required | Example value | Notes |
|---|---|---|---|
| `IBM_CLOUD_API_KEY` | if non-interactive | `abc123...` | Your IBM Cloud API key; leave empty for `ibmcloud login --sso` |
| `IBM_CLOUD_REGION` | yes | `us-south` | Region where the Code Engine project will be created |
| `IBM_CLOUD_RESOURCE_GROUP` | yes | `default` | Resource group that owns the project |
| `CE_PROJECT_NAME` | yes | `galaxium-travels-oauth2` | Project to create or reuse |
| `STACK_AUTH_MODE` | informational | `oauth2` | `deploy-stack-oauth2.sh` enforces this by export — value here is documentation only |
| `DEPLOY_ARTIFACT_MODE` | yes | `source_build` | `source_build` or `prebuilt_images` |
| `KEYCLOAK_ADMIN_PASSWORD` | yes | *(generated above)* | Keycloak admin console password |
| `OIDC_CLIENT_SECRET` | yes | *(from realm file)* | Must match `galaxium-realm.json` — see B-3b |
| `FLASK_SECRET_KEY` | yes | *(generated above)* | Random 64-char hex string — never reuse a placeholder |
| `KEYCLOAK_BASE_URL_OVERRIDE` | optional | *(leave empty)* | Empty = deploy Keycloak in-project; set an HTTPS URL to use an external Keycloak |
| `FRONTEND_AUTH_REQUIRED` | optional | *(leave empty)* | Empty = oauth2 default (`true`); set `false` for guest-mode UIs |

### B-3d — Filled-in example (`source_build` mode, in-project Keycloak)

After editing, the top of your `deploy.env.oauth2` should look similar to this:

```sh
IBM_CLOUD_API_KEY=abc123yourapikey
IBM_CLOUD_REGION=us-south
IBM_CLOUD_RESOURCE_GROUP=default
CE_PROJECT_NAME=galaxium-travels-oauth2
CE_PROJECT_TAG=galaxium
CE_ENDPOINT=public

STACK_AUTH_MODE=oauth2
FRONTEND_AUTH_REQUIRED=

DEPLOY_ARTIFACT_MODE=source_build
BUILD_SOURCE=
BUILD_COMMIT=

# --- prebuilt_images section: leave as-is for source_build ---
ICR_REGION=us-south
ICR_REGISTRY=us.icr.io
ICR_NAMESPACE=change-me
ICR_REGISTRY_SECRET_NAME=galaxium-icr-access
ICR_REGISTRY_USERNAME=iamapikey
ICR_REGISTRY_PASSWORD=
CONTAINER_CLIENT=docker
CONTAINER_PLATFORM=linux/amd64
IMAGE_TAG=latest
HR_IMAGE_REPOSITORY=galaxium-hr-api
BOOKING_API_IMAGE_REPOSITORY=galaxium-booking-api
MCP_IMAGE_REPOSITORY=galaxium-booking-mcp
WEB_APP_IMAGE_REPOSITORY=galaxium-web-ui
WEB_APP_MCP_IMAGE_REPOSITORY=galaxium-web-ui-mcp

KEYCLOAK_APP_NAME=galaxium-keycloak
HR_APP_NAME=galaxium-hr-api
BOOKING_API_APP_NAME=galaxium-booking-api
MCP_APP_NAME=galaxium-booking-mcp
WEB_APP_NAME=galaxium-web-ui
WEB_APP_MCP_APP_NAME=galaxium-web-ui-mcp

KEYCLOAK_REALM=galaxium
OIDC_AUDIENCE=booking-api
OIDC_CLIENT_ID=web-app-proxy
OIDC_SCOPE="openid profile email"
KEYCLOAK_BASE_URL_OVERRIDE=

KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=Xk7mP2nRvQ9wLdF3aYcH8bJs
OIDC_CLIENT_SECRET=<value-from-galaxium-realm.json>
FLASK_SECRET_KEY=9d3e6a2c5f8b1d4e7a4a7f2c9e1b3d8a0f5e6c2d1b9a4f7e3c8b2d5a1e0f4c7b

# NOT USED in oauth2 mode
BASIC_AUTH_USERNAME=
BASIC_AUTH_PASSWORD=
```

### B-3e — Variant: using an external Keycloak

If you set `KEYCLOAK_BASE_URL_OVERRIDE`, scripts 03 and 05 are skipped.
Set it to the public base URL of your existing Keycloak instance:

```sh
KEYCLOAK_BASE_URL_OVERRIDE=https://keycloak.example.com
```

After deployment you must manually update the `web-app-proxy` client in that
Keycloak instance to add the Code Engine UI URLs to `redirectUris` and `webOrigins`.
Run `bash scripts/06-summary.sh` to get the URLs once the deployment finishes.

### B-3f — Additional values for `prebuilt_images` mode

If you chose `DEPLOY_ARTIFACT_MODE=prebuilt_images`, also fill in:

| Variable | Example value | Notes |
|---|---|---|
| `ICR_REGISTRY` | `us.icr.io` | IBM Cloud Container Registry host for your region |
| `ICR_NAMESPACE` | `my-galaxium-ns` | Namespace inside the registry — must exist or will be created |
| `IMAGE_TAG` | `latest` | Tag applied to every pushed Galaxium image |
| `CONTAINER_CLIENT` | `docker` | `docker` or `podman` |
| `CONTAINER_PLATFORM` | `linux/amd64` | Keep this value unless you have validated another platform |

> **Tip:** `deploy.env.oauth2.template` contains every variable with a
> `REQUIRED / DEFAULT OK / CONDITIONAL / OPTIONAL / NOT USED` legend.
> Only the variables in B-3c are mandatory for an oauth2 `source_build` deployment.

---

## B-4 · Run the Deployment

```sh
cd deployment/ibm-code-engine
bash deploy-stack-oauth2.sh
```

`deploy-stack-oauth2.sh` exports `STACK_AUTH_MODE=oauth2` before the first script runs,
so oauth2 mode is enforced regardless of what the env file contains.
It reads `deploy.env.oauth2` by default; override with `ENV_FILE=/path/to/other.env`.

| Step | Script | What it does | Result |
|---|---|---|---|
| 1 | `00-prereqs.sh` | Checks all required CLI tools; prints installed versions and the active auth mode | Pass or error with install hint |
| 2 | `01-project.sh` | Logs in to IBM Cloud; creates or selects the Code Engine project | Active CE project |
| 3 | `02-config-and-secrets.sh` | Creates the Keycloak realm configmap (imports `galaxium-realm.json`), the `keycloak-admin` secret (`KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD`), and the `web-ui-secrets` secret (`FLASK_SECRET_KEY` + `OIDC_CLIENT_SECRET`) | CE secrets and realm configmap in place |
| 4 | `02b-build-and-push-images.sh` | *(skipped for `source_build`)* Builds five Galaxium images locally; pushes them to IBM Cloud Container Registry | ICR images ready |
| 5 | `03-deploy-keycloak.sh` | Deploys `quay.io/keycloak/keycloak:26.0`; mounts the realm configmap at `/opt/keycloak/data/import`; starts in dev mode with `--import-realm`; captures the public Keycloak URL | Keycloak running at its Code Engine URL |
| 6 | `04-deploy-services.sh` | Resolves the Keycloak URL → derives JWKS URL and token URL → deploys HR API, Booking API (`AUTH_MODE=oauth2`, `OIDC_ISSUER`, `OIDC_JWKS_URL`), MCP server (`AUTH_MODE=oauth2`, `MCP_PUBLIC_BASE_URL`) → resolves their URLs → deploys REST Web UI (`BACKEND_AUTH_MODE=oauth2`, `OIDC_TOKEN_URL`, `OIDC_CLIENT_ID`, `OIDC_SCOPE`) and MCP Web UI (same) → writes config to `generated/` | All 5 services running with full OAuth2 wiring |
| 7 | `05-sync-keycloak-client.sh` | Waits for Keycloak readiness (polls up to 5 min); acquires an admin token; reads the `web-app-proxy` client; appends the final Code Engine UI URLs to `redirectUris` and `webOrigins` | Keycloak client accepts browser login callbacks from both web UIs |
| 8 | `06-summary.sh` | Reads back all public URLs; prints OAuth2 smoke-test commands including a token request and MCP OAuth discovery metadata URLs | All URLs and test commands on screen |

What each service receives at deploy time (injected via `04-deploy-services.sh`):

| Service | Auth config injected |
|---|---|
| Booking REST API | `AUTH_MODE=oauth2`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` via configmap |
| Booking MCP server | `AUTH_MODE=oauth2`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL`, `OIDC_AUTHORIZATION_SERVER_URL`, `MCP_PUBLIC_BASE_URL` via configmap |
| REST Web UI | `BACKEND_AUTH_MODE=oauth2`, `BACKEND_URL`, `FRONTEND_AUTH_REQUIRED`, `OIDC_TOKEN_URL`, `OIDC_CLIENT_ID`, `OIDC_SCOPE` via configmap; `FLASK_SECRET_KEY` + `OIDC_CLIENT_SECRET` via secret |
| MCP Web UI | `BACKEND_AUTH_MODE=oauth2`, `MCP_SERVER_URL`, `FRONTEND_AUTH_REQUIRED`, `OIDC_TOKEN_URL`, `OIDC_CLIENT_ID`, `OIDC_SCOPE` via configmap; `FLASK_SECRET_KEY` + `OIDC_CLIENT_SECRET` via secret |
| HR API | no auth |

---

## B-5 · Verify the Deployment

The summary printed by `06-summary.sh` contains ready-to-run commands.
Use them directly, or follow the numbered sequence below.

Replace placeholders with the URLs printed by the summary.

```sh
# 1. Keycloak realm metadata — confirms Keycloak is up and the realm was imported
curl -s <KEYCLOAK_URL>/realms/galaxium/.well-known/openid-configuration | jq .issuer

# 2. Request a client_credentials access token and capture it
TOKEN="$(curl -s -X POST \
  <KEYCLOAK_URL>/realms/galaxium/protocol/openid-connect/token \
  -d grant_type=client_credentials \
  -d client_id=web-app-proxy \
  -d client_secret=<OIDC_CLIENT_SECRET> | jq -r .access_token)"
echo "TOKEN=${TOKEN}"

# 3. Booking API health (no auth required)
curl -i <BOOKING_API_URL>/health

# 4. List available flights with the Bearer token
curl -i -H "Authorization: Bearer ${TOKEN}" <BOOKING_API_URL>/flights

# 5. REST Web UI health
curl -i <WEB_UI_URL>/api/health

# 6. MCP Web UI health
curl -i <MCP_WEB_UI_URL>/api/health

# 7. MCP OAuth2 discovery metadata
curl -s <MCP_BASE_URL>/.well-known/oauth-protected-resource | jq .
curl -s <MCP_BASE_URL>/.well-known/oauth-authorization-server | jq .

# 8. MCP initialize with Bearer token
curl -i <MCP_BASE_URL>/mcp \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0.0"}}}'

# 9. MCP tools/list — reuse the session id from the initialize response
#    Replace <MCP_SESSION_ID> with the value from the mcp-session-id header above
curl -sS <MCP_BASE_URL>/mcp \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -H "MCP-Session-Id: <MCP_SESSION_ID>" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

---

## B-6 · Debug Individual Steps

Each numbered script is self-contained.
When running scripts individually, you must pass both `ENV_FILE` and `STACK_AUTH_MODE`
because the orchestrator normally exports `STACK_AUTH_MODE=oauth2` — individual scripts
do not do this themselves.

```sh
cd deployment/ibm-code-engine

# Run a specific step against the oauth2 env file
ENV_FILE=deploy.env.oauth2 STACK_AUTH_MODE=oauth2 bash scripts/04-deploy-services.sh

# Stream full ibmcloud CLI output instead of the default quiet capture
CE_DEBUG=1 ENV_FILE=deploy.env.oauth2 STACK_AUTH_MODE=oauth2 bash scripts/04-deploy-services.sh

# Re-run Keycloak client sync after changing a UI URL (without full redeploy)
ENV_FILE=deploy.env.oauth2 STACK_AUTH_MODE=oauth2 bash scripts/05-sync-keycloak-client.sh

# Re-print the summary without redeploying
ENV_FILE=deploy.env.oauth2 STACK_AUTH_MODE=oauth2 bash scripts/06-summary.sh
```

Inspect the rendered service config files written by step 6:

```sh
ls -1 generated/
cat generated/booking-api.oauth2.env
cat generated/mcp.oauth2.env
cat generated/web-ui.oauth2.env
cat generated/web-ui-mcp.oauth2.env
```

These files show the exact env vars pushed into each Code Engine configmap.
They are git-ignored but kept locally for inspection and debugging.

---

## Related

- Overview and architecture diagrams: [`README.md`](./README.md)
- Source build packaging ignore rules: [`.ceignore`](../../.ceignore)
- Basic Auth path: [`DEPLOY-PATH-A-BASIC-AUTH.md`](./DEPLOY-PATH-A-BASIC-AUTH.md)
- OAuth2 env template: [`deploy.env.oauth2.template`](./deploy.env.oauth2.template)
- Entrypoint script: [`deploy-stack-oauth2.sh`](./deploy-stack-oauth2.sh)
- Keycloak realm file: [`../../local-container/keycloak/realm/galaxium-realm.json`](../../local-container/keycloak/realm/galaxium-realm.json)
- Reference — all env variables: [`README.md#key-environment-variables`](./README.md#key-environment-variables)
