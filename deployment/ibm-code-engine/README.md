# IBM Code Engine Deployment Draft

This folder prepares the current Galaxium Travels stack for IBM Code Engine.

Default target model:

- one IBM Code Engine project
- Keycloak in the same Code Engine project
- HR API
- Booking REST API
- Booking MCP server
- REST web UI
- MCP web UI

Status:

- draft deployment package
- updated to match the current repository structure
- not executed against a live IBM Cloud account in this workspace

The current environment does not have the `ibmcloud` CLI or IBM Cloud credentials, so this folder was prepared and validated as a script package only.

## Automation Type

Current implementation in this folder:

- bash scripts
- IBM Cloud CLI with the Code Engine plugin

Not used in this folder:

- Terraform

So the current deployment package is `bash + ibmcloud ce ...`, not Terraform.
If you want a Terraform-based deployment, that would be a separate implementation and should be documented as a second option instead of being mixed into this one.

## What This Folder Supports

This package now supports two stack auth modes:

1. `STACK_AUTH_MODE=oauth2`
   - deploys Keycloak in the same Code Engine project by default
   - deploys REST and MCP backends with OAuth validation
   - deploys both web UIs with browser login enabled by default

2. `STACK_AUTH_MODE=basic`
   - skips Keycloak deployment
   - deploys REST and MCP backends with shared Basic Auth
   - deploys both web UIs in guest-traveler mode

Important:

- The MCP server must stay on `Streamable HTTP`.
- Public MCP clients must use the `/mcp` endpoint.
- In `oauth2` mode, Keycloak is deployed in the same Code Engine project unless you explicitly set `KEYCLOAK_BASE_URL_OVERRIDE`.
- Deployment order matters because Code Engine public URLs are only known after each app is created.

## Deployment Model

This draft uses:

1. local source builds for repository services with `ibmcloud ce application create --build-source ...`
2. direct image deployment for Keycloak with `quay.io/keycloak/keycloak:26.0`
3. Code Engine secrets for app credentials
4. a Code Engine configmap for the Keycloak realm import

All of these steps are executed through the IBM Cloud CLI from bash scripts in `scripts/`.
There is currently no Terraform state, Terraform module, or Terraform workflow in this folder.

Important build detail:

- This folder is intentionally centered on `Code Engine build from source`.
- For local source builds, Code Engine automatically pushes the resulting image to IBM Cloud Container Registry.
- This folder does not currently automate a separate `docker build` plus `docker push` flow for the Galaxium service images.
- That distinction matters because registry compatibility is stricter than just "an image exists somewhere".

The Keycloak realm file is reused from:

- [`../../local-container/keycloak/realm/galaxium-realm.json`](../../local-container/keycloak/realm/galaxium-realm.json)

## Container Build And Registry Constraints

The older repository concern is valid: container build and upload behavior is not interchangeable.

Current supported automation path in this folder:

1. Build from local or Git source with `ibmcloud ce application create|update --build-source ...`
2. Let Code Engine create the image and upload it to IBM Cloud Container Registry
3. Let the deployed application reference that resulting image automatically

Not currently automated in this folder:

1. build each Galaxium service image locally
2. push those images manually to IBM Cloud Container Registry
3. deploy the stack from those pushed image references

Why this is documented explicitly:

1. IBM Cloud Container Registry supports OCI-compliant images and Docker V2 schema 2 images.
2. Docker schema 1 images are not supported.
3. Registry tagging can fail with `CRI0302E` when the manifest type is not supported for tagging.
4. Because of that, "build an image somewhere and push it" is not a safe assumption for this deployment package.

Practical rule for this repository:

1. Keep using the Code Engine source-build path for the Galaxium services unless we add and validate a second prebuilt-image workflow.
2. If a prebuilt-image workflow is added later, it must be restricted to registry-supported image formats and tested against both IBM Cloud Container Registry and Code Engine pull behavior.

## Deployment Order

This package now uses an explicit phased order because some URLs are only known after Code Engine creates each app:

1. create or select the Code Engine project
2. create secrets and configmaps
3. deploy Keycloak in the same Code Engine project for `oauth2` mode
4. deploy HR, REST, and MCP first, then deploy both web UIs with the resolved public backend URLs
5. sync the Keycloak client with the final public UI URLs
6. print the final summary and smoke-test commands

This follows the same practical issue from older Code Engine automation: public routes are deployment outputs, so later steps must read them back before configuring dependent apps.

## Current Service Mapping

| Component | Source | Port | Notes |
| --- | --- | --- | --- |
| Keycloak | `quay.io/keycloak/keycloak:26.0` | `8080` | Deployed in the same Code Engine project by default for `oauth2` mode |
| HR API | local source `HR_database/` | `8081` | File-backed data is ephemeral without a mounted data store |
| Booking REST API | local source `booking_system_rest/` | `8082` | Supports `AUTH_MODE=oauth2` or `AUTH_MODE=basic` |
| Booking MCP server | local source `booking_system_mcp/` | `8084` | Public MCP endpoint stays `${MCP_URL}/mcp` with Streamable HTTP |
| REST Web UI | local source `galaxium-booking-web-app/` | `8083` | Supports OAuth browser login or Basic Auth guest mode |
| MCP Web UI | local source `galaxium-booking-web-app-mcp/` | `8085` | Uses the direct Python MCP client over Streamable HTTP |

## Files

- [`deploy.env.template`](./deploy.env.template)
  - Copy this to `deploy.env` and fill in the values.
- [`scripts/00-prereqs.sh`](./scripts/00-prereqs.sh)
  - Check required local commands, verify the Code Engine plugin, and show whether the deployment will use `IBM_CLOUD_API_KEY` or an existing interactive `ibmcloud login` session.
- [`scripts/01-project.sh`](./scripts/01-project.sh)
  - Target IBM Cloud and create or select the Code Engine project.
- [`scripts/02-config-and-secrets.sh`](./scripts/02-config-and-secrets.sh)
  - Create the Keycloak realm configmap and the required secrets.
- [`scripts/03-deploy-keycloak.sh`](./scripts/03-deploy-keycloak.sh)
  - Deploy Keycloak inside the same Code Engine project for `oauth2` mode.
- [`scripts/04-deploy-services.sh`](./scripts/04-deploy-services.sh)
  - Deploy HR, REST, and MCP first, then deploy REST UI and MCP UI with the resolved URLs.
- [`scripts/05-sync-keycloak-client.sh`](./scripts/05-sync-keycloak-client.sh)
  - Update the Keycloak `web-app-proxy` client with the final Code Engine UI origins and redirect URI patterns.
- [`scripts/06-summary.sh`](./scripts/06-summary.sh)
  - Print public URLs and suggested smoke-test commands.

## Prerequisites

Required local installs:

1. `bash`
2. IBM Cloud CLI: `ibmcloud`
3. IBM Cloud Code Engine plugin for the CLI
4. `curl`
5. `jq`

IBM Cloud login options:

1. Non-interactive automation
   Set `IBM_CLOUD_API_KEY` in `deploy.env`.
   The scripts will run `ibmcloud login --apikey ... -r <region> -g <resource-group>` automatically.
2. Interactive operator session
   Leave `IBM_CLOUD_API_KEY` empty and run `ibmcloud login` yourself before `scripts/01-project.sh`.

Operator preparation:

1. Copy `deploy.env.template` to `deploy.env`.
2. Fill in the real secret values before running any script.
3. Decide whether you will use `STACK_AUTH_MODE=oauth2` or `STACK_AUTH_MODE=basic`.
4. If you use `oauth2`, decide whether Keycloak will be deployed in the same Code Engine project or provided externally through `KEYCLOAK_BASE_URL_OVERRIDE`.

Example:

```sh
cd deployment/ibm-code-engine
cp deploy.env.template deploy.env
bash scripts/00-prereqs.sh
```

Required CLI checks:

```sh
ibmcloud version
ibmcloud plugin show code-engine
ibmcloud plugin list
```

## CLI Compatibility Check

This folder was checked against the current IBM documentation on `2026-03-18`.

Verified command families used by these scripts:

1. `ibmcloud login --apikey ... -r <region> -g <resource-group>`
2. `ibmcloud plugin install code-engine`
3. `ibmcloud plugin show code-engine`
4. `ibmcloud ce project create` and `ibmcloud ce project select`
5. `ibmcloud ce application create`, `update`, and `get --output url`
6. `ibmcloud ce configmap create` and `update`
7. `ibmcloud ce secret create` and `update`

Version handling note:

- This repository does not hard-pin a single `ibmcloud` CLI or `code-engine` plugin version in the README.
- `scripts/00-prereqs.sh` prints the locally installed `ibmcloud` and `code-engine` plugin versions so you can compare your workstation with the current IBM documentation before deployment.
- The command syntax in this folder was checked against the current IBM documentation on `2026-03-18`, but your local installed versions should still be verified before a real deployment run.

## Recommended Order

Run the scripts in this order:

```sh
bash scripts/00-prereqs.sh
bash scripts/01-project.sh
bash scripts/02-config-and-secrets.sh
bash scripts/03-deploy-keycloak.sh
bash scripts/04-deploy-services.sh
bash scripts/05-sync-keycloak-client.sh
bash scripts/06-summary.sh
```

Notes:

- In `STACK_AUTH_MODE=basic`, `scripts/03-deploy-keycloak.sh` exits with a skip message.
- In `STACK_AUTH_MODE=basic`, `scripts/05-sync-keycloak-client.sh` also exits with a skip message.
- In `STACK_AUTH_MODE=oauth2`, Keycloak is deployed in the same Code Engine project by default.
- Only use `KEYCLOAK_BASE_URL_OVERRIDE` when you intentionally connect to an existing external Keycloak deployment.

## Key Environment Choices

Main variables in `deploy.env`:

- `IBM_CLOUD_API_KEY`
  - Optional
  - Set it when you want the scripts to log in to IBM Cloud automatically
  - Leave it empty when you prefer an existing interactive `ibmcloud login` session

- `STACK_AUTH_MODE`
  - `oauth2` or `basic`
- `FRONTEND_AUTH_REQUIRED`
  - Leave empty to use the mode default
  - `oauth2` default: `true`
  - `basic` default: `false`
- `KEYCLOAK_BASE_URL_OVERRIDE`
  - Leave empty for the normal same-project Keycloak deployment
- `WEB_APP_MCP_APP_NAME`
  - Code Engine app name for the MCP-backed web UI
- `BASIC_AUTH_SECRET_NAME`
  - Shared Basic Auth secret for both backends and both web UIs
- `MCP_TIMEOUT_SECONDS`
  - Timeout used by the MCP-backed web UI service layer

## Important Constraints

1. The Keycloak deployment is still demo-oriented because it uses `start-dev`.
2. Keycloak and HR state are ephemeral unless you add persistent storage.
3. The MCP server public base URL must point to the Code Engine public app URL, and public clients must call `/mcp`.
4. The MCP transport must not be changed from `Streamable HTTP`.
5. The web UIs depend on public service URLs. This is simple, but it is not the most private or cost-efficient production setup.
6. The imported Keycloak realm is local-dev shaped, so the client URL sync step is needed after the Code Engine UI URLs exist.

## What Is Not Automated Yet

This folder does not currently automate:

1. IBM Cloud CLI installation
2. Code Engine plugin installation
3. custom domains
4. managed TLS certificate setup
5. persistent data store creation and binding
6. a prebuilt-image workflow that first pushes Galaxium service images to IBM Cloud Container Registry
7. Terraform-based deployment
8. production hardening of the Keycloak runtime

## Local Validation Done In This Workspace

These checks were completed locally:

- all deployment scripts were updated to the current service set
- the env template was updated to the current auth modes
- the README was synced with the scripts
- shell syntax validation was run on the deployment scripts

These checks were not completed here:

- live `ibmcloud` CLI execution
- live Code Engine builds
- live Keycloak rollout on IBM Cloud
- live public URL smoke tests on IBM Cloud

Terraform checks were also not run because this folder does not contain a Terraform implementation.

## Suggested Next Step

After you fill in `deploy.env`, run the scripts in order and then use:

```sh
bash scripts/06-summary.sh
```

That summary prints the public URLs and the smoke-test commands for the selected auth mode.

## Related Docs

- Existing repo note: [`../../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`](../../ai_generated_documentation/CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md)
- Local stack guide: [`../../local-container/README.md`](../../local-container/README.md)
- Main repository guide: [`../../README.md`](../../README.md)
