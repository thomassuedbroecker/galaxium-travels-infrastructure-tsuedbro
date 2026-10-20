# Path A — Basic Auth Deployment

This document is the complete, self-contained deployment guide for
`STACK_AUTH_MODE=basic`.

**Read this file if:** you want to deploy the Galaxium Travels stack with shared
Basic Auth credentials — no Keycloak, no browser login screen.

| Property | Value |
|---|---|
| **Entrypoint** | `deploy-stack.sh` |
| **Env file** | `deploy.env` (copy from `deploy.env.template`) |
| **Keycloak** | not deployed |
| **Browser login** | no login screen — services are accessible without login |
| **Scripts that run** | `00 → 01 → 02 → [02b] → 04 → 06` |
| **03 and 05** | self-skip — not applicable to Basic Auth |

← Back to overview: [`README.md`](./README.md)
→ OAuth2 path: [`DEPLOY-PATH-B-OAUTH2.md`](./DEPLOY-PATH-B-OAUTH2.md)

---

## A-1 · Install Required Local Tools

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

## A-2 · Log In to IBM Cloud

**Option A — API key (non-interactive, recommended for automation):**

```sh
ibmcloud login --apikey <YOUR_API_KEY> -r us-south -g default
```

Set `IBM_CLOUD_API_KEY` in `deploy.env` and the scripts will log in automatically on each run.

**Option B — Interactive browser login:**

```sh
ibmcloud login --sso
```

Leave `IBM_CLOUD_API_KEY` empty in `deploy.env` when using this option.

---

## A-3 · Create and Fill In the Env File

### A-3a — Copy the template

```sh
cd deployment/ibm-code-engine
cp deploy.env.template deploy.env
```

### A-3b — Generate the secrets you need

Generate `FLASK_SECRET_KEY` before editing the file:

```sh
python3 -c "import secrets; print(secrets.token_hex(32))"
# example output: 4a7f2c9e1b3d8a0f5e6c2d1b9a4f7e3c8b2d5a1e0f4c7b9d3e6a2c5f8b1d4e7a
```

### A-3c — Fill in the required values

Open `deploy.env` in your editor. The mandatory values to change from their defaults are:

| Variable | Required | Example value | Notes |
|---|---|---|---|
| `IBM_CLOUD_API_KEY` | if non-interactive | `abc123...` | Your IBM Cloud API key; leave empty for `ibmcloud login --sso` |
| `IBM_CLOUD_REGION` | yes | `us-south` | Region where the Code Engine project will be created |
| `IBM_CLOUD_RESOURCE_GROUP` | yes | `default` | Resource group that owns the project |
| `CE_PROJECT_NAME` | yes | `galaxium-travels` | Project to create or reuse |
| `STACK_AUTH_MODE` | yes | `basic` | Must remain `basic` for this path |
| `DEPLOY_ARTIFACT_MODE` | yes | `source_build` | `source_build` or `prebuilt_images` |
| `FLASK_SECRET_KEY` | yes | *(generated above)* | Random 64-char hex string — never reuse a placeholder |
| `BASIC_AUTH_USERNAME` | yes | `galaxium-user` | Shared username injected into all services |
| `BASIC_AUTH_PASSWORD` | yes | `change-me-strong` | Shared password injected into all services |

### A-3d — Filled-in example (`source_build` mode)

After editing, the top of your `deploy.env` should look similar to this:

```sh
IBM_CLOUD_API_KEY=abc123yourapikey
IBM_CLOUD_REGION=us-south
IBM_CLOUD_RESOURCE_GROUP=default
CE_PROJECT_NAME=galaxium-travels
CE_PROJECT_TAG=galaxium
CE_ENDPOINT=public

STACK_AUTH_MODE=basic
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

KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=change-me
OIDC_CLIENT_SECRET=change-me
FLASK_SECRET_KEY=4a7f2c9e1b3d8a0f5e6c2d1b9a4f7e3c8b2d5a1e0f4c7b9d3e6a2c5f8b1d4e7a
BASIC_AUTH_USERNAME=galaxium-user
BASIC_AUTH_PASSWORD=change-me-strong
```

### A-3e — Additional values for `prebuilt_images` mode

If you chose `DEPLOY_ARTIFACT_MODE=prebuilt_images`, also fill in:

| Variable | Example value | Notes |
|---|---|---|
| `ICR_REGISTRY` | `us.icr.io` | IBM Cloud Container Registry host for your region |
| `ICR_NAMESPACE` | `my-galaxium-ns` | Namespace inside the registry — must exist or will be created |
| `IMAGE_TAG` | `latest` | Tag applied to every pushed Galaxium image |
| `CONTAINER_CLIENT` | `docker` | `docker` or `podman` |
| `CONTAINER_PLATFORM` | `linux/amd64` | Keep this value unless you have validated another platform |

> **Tip:** `deploy.env.template` contains every variable with inline documentation.
> Only the variables in A-3c are mandatory for a Basic Auth `source_build` deployment.

---

## A-4 · Run the Deployment

```sh
cd deployment/ibm-code-engine
bash deploy-stack.sh
```

The orchestrator runs every numbered script in order.
Scripts that do not apply to Basic Auth mode exit immediately with a skip message.

| Step | Script | What it does | Result |
|---|---|---|---|
| 1 | `00-prereqs.sh` | Checks all required CLI tools; prints installed versions | Pass or error with install hint |
| 2 | `01-project.sh` | Logs in to IBM Cloud; creates or selects the Code Engine project | Active CE project |
| 3 | `02-config-and-secrets.sh` | Creates `basic-auth` secret (`BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD`) and `web-ui-secrets` secret (`FLASK_SECRET_KEY`) | CE secrets in place |
| 4 | `02b-build-and-push-images.sh` | *(skipped for `source_build`)* Builds five Galaxium images locally; pushes them to IBM Cloud Container Registry | ICR images ready |
| 5 | `03-deploy-keycloak.sh` | **Skipped** — Basic Auth does not use Keycloak | skip message printed |
| 6 | `04-deploy-services.sh` | Deploys HR API → Booking API → MCP server → REST Web UI → MCP Web UI; writes auth config to `generated/` and pushes it as CE configmaps | All 5 services running |
| 7 | `05-sync-keycloak-client.sh` | **Skipped** — no Keycloak to sync | skip message printed |
| 8 | `06-summary.sh` | Reads back all public URLs; prints smoke-test commands | URLs and test commands on screen |

What each service receives at deploy time (injected via `04-deploy-services.sh`):

| Service | Auth config injected |
|---|---|
| Booking REST API | `AUTH_MODE=basic` via configmap; `BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD` via secret |
| Booking MCP server | `AUTH_MODE=basic` via configmap; `BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD` via secret |
| REST Web UI | `BACKEND_AUTH_MODE=basic`, `BACKEND_URL`, `FRONTEND_AUTH_REQUIRED=false` via configmap; `FLASK_SECRET_KEY` via secret; `BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD` via secret |
| MCP Web UI | `BACKEND_AUTH_MODE=basic`, `MCP_SERVER_URL`, `FRONTEND_AUTH_REQUIRED=false` via configmap; `FLASK_SECRET_KEY` via secret; `BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD` via secret |
| HR API | no auth |

---

## A-5 · Verify the Deployment

The summary printed by `06-summary.sh` contains ready-to-run commands.
Use them directly, or follow the numbered sequence below.

Replace placeholders with the URLs printed by the summary.

```sh
# 1. Booking API health (no auth required)
curl -i <BOOKING_API_URL>/health

# 2. Build the Basic Auth header
BASIC_TOKEN="$(printf '%s' '<BASIC_AUTH_USERNAME>:<BASIC_AUTH_PASSWORD>' | base64 | tr -d '\r\n')"

# 3. List available flights (requires Basic Auth)
curl -i -H "Authorization: Basic ${BASIC_TOKEN}" <BOOKING_API_URL>/flights

# 4. REST Web UI health
curl -i <WEB_UI_URL>/api/health

# 5. MCP Web UI health
curl -i <MCP_WEB_UI_URL>/api/health

# 6. MCP initialize — smoke test without auth
curl -i <MCP_BASE_URL>/mcp \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0.0"}}}'

# 7. MCP initialize with Basic Auth
curl -i <MCP_BASE_URL>/mcp \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0.0"}}}'

# 8. MCP tools/list — reuse the session id from the initialize response
#    Replace <MCP_SESSION_ID> with the value from the mcp-session-id header above
curl -sS <MCP_BASE_URL>/mcp \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -H "MCP-Session-Id: <MCP_SESSION_ID>" \
  -H "Authorization: Basic ${BASIC_TOKEN}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
```

---

## A-6 · Debug Individual Steps

Each numbered script is self-contained and reads the same `deploy.env` file.
Run any step directly without re-running the full orchestrator:

```sh
cd deployment/ibm-code-engine

# Run a specific step
bash scripts/04-deploy-services.sh

# Stream full ibmcloud CLI output (default is quiet with error capture on failure)
CE_DEBUG=1 bash scripts/04-deploy-services.sh

# Re-print the summary without redeploying
bash scripts/06-summary.sh

# Export the live links and configuration to generated/exports/ (read-only, no secret values)
bash export-deployment.sh --basic

# Point at a non-default env file
ENV_FILE=/path/to/other.env bash scripts/04-deploy-services.sh
```

Inspect the rendered service config files written by step 6:

```sh
ls -1 generated/
cat generated/booking-api.basic.env
cat generated/mcp.basic.env
cat generated/web-ui.basic.env
cat generated/web-ui-mcp.basic.env
```

These files show the exact env vars pushed into each Code Engine configmap.
They are git-ignored but kept locally for inspection and debugging.

---

## Related

- Overview and architecture diagrams: [`README.md`](./README.md)
- Source build packaging ignore rules: [`.ceignore`](../../.ceignore)
- OAuth2 path: [`DEPLOY-PATH-B-OAUTH2.md`](./DEPLOY-PATH-B-OAUTH2.md)
- Basic Auth env template: [`deploy.env.template`](./deploy.env.template)
- Entrypoint script: [`deploy-stack.sh`](./deploy-stack.sh)
- Reference — all env variables: [`README.md#key-environment-variables`](./README.md#key-environment-variables)
