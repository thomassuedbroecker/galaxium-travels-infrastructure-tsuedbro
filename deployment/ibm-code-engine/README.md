# IBM Code Engine Deployment Draft

This folder prepares the current Galaxium Travels stack for IBM Code Engine.

Default target model:

- one IBM Code Engine project
- HR API
- Booking REST API
- Booking MCP server
- REST web UI
- MCP web UI
- shared Basic Auth as the current preconfigured deployment path
- optional Keycloak later when `STACK_AUTH_MODE=oauth2`

Status:

- draft deployment package
- updated to match the current repository structure
- preconfigured for the `basic` auth path first
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

This package now supports two stack auth modes.
The current preconfigured default is `basic`:

1. `STACK_AUTH_MODE=basic`
   - skips Keycloak deployment
   - deploys REST and MCP backends with shared Basic Auth
   - deploys both web UIs in guest-traveler mode

2. `STACK_AUTH_MODE=oauth2`
   - deploys Keycloak in the same Code Engine project by default
   - deploys REST and MCP backends with OAuth validation
   - deploys both web UIs with browser login enabled by default

Important:

- The MCP server must stay on `Streamable HTTP`.
- Public MCP clients must use the `/mcp` endpoint.
- `deploy.env.template` now defaults to `STACK_AUTH_MODE=basic`.
- In `oauth2` mode, Keycloak is deployed in the same Code Engine project unless you explicitly set `KEYCLOAK_BASE_URL_OVERRIDE`.
- Deployment order matters because Code Engine public URLs are only known after each app is created.

This package also supports two deployment artifact modes:

1. `DEPLOY_ARTIFACT_MODE=source_build`
   - Code Engine builds the Galaxium service images from local or Git source
   - Code Engine stores the resulting images in IBM Cloud Container Registry

2. `DEPLOY_ARTIFACT_MODE=prebuilt_images`
   - local container images are built for the Galaxium services
   - the images are pushed to IBM Cloud Container Registry
   - Code Engine deploys the applications from those pushed image references

## Deployment Model

This draft uses:

1. `source_build` mode with `ibmcloud ce application create --build-source ...`
2. `prebuilt_images` mode with local image build, IBM Cloud Container Registry push, and `ibmcloud ce application create --image ...`
3. direct image deployment for Keycloak with `quay.io/keycloak/keycloak:26.0` when `STACK_AUTH_MODE=oauth2`
4. Code Engine secrets for sensitive values such as Flask session keys, client secrets, and Basic Auth credentials
5. Code Engine configmaps for per-service non-secret runtime settings
6. a Code Engine configmap for the Keycloak realm import only when `STACK_AUTH_MODE=oauth2`

All of these steps are executed through the IBM Cloud CLI from bash scripts in `scripts/`.
There is currently no Terraform state, Terraform module, or Terraform workflow in this folder.

Runtime configuration model:

- `scripts/04-deploy-services.sh` renders env files for each deployed service variant and pushes them into Code Engine configmaps.
- The applications then consume those configmaps with `--env-from-configmap` instead of a long list of direct `--env` flags.
- Secrets stay in Code Engine secrets and are still attached with `--env-from-secret`.
- This keeps the Basic Auth-first path simple now and leaves room for future auth variants without turning the deploy command into a long list of inline variables.

Important build detail:

- `source_build` remains the simplest path because Code Engine handles the image build and registry push.
- `prebuilt_images` is now also automated in this folder for the five Galaxium service images.
- Keycloak still uses the public `quay.io/keycloak/keycloak:26.0` image by default.
- Registry compatibility is stricter than just "an image exists somewhere", so the prebuilt-image workflow keeps explicit registry settings and a default `linux/amd64` platform.

The Keycloak realm file is reused from:

- [`../../local-container/keycloak/realm/galaxium-realm.json`](../../local-container/keycloak/realm/galaxium-realm.json)

## Container Build And Registry Constraints

The older repository concern is valid: container build and upload behavior is not interchangeable.

Current supported automation paths in this folder:

1. Build from local or Git source with `ibmcloud ce application create|update --build-source ...`
2. Let Code Engine create the image and upload it to IBM Cloud Container Registry
3. Let the deployed application reference that resulting image automatically
4. Or switch to `DEPLOY_ARTIFACT_MODE=prebuilt_images`, build the Galaxium images locally, push them to IBM Cloud Container Registry, and deploy from those pushed image references

Why this is documented explicitly:

1. IBM Cloud Container Registry supports OCI-compliant images and Docker V2 schema 2 images.
2. Docker schema 1 images are not supported.
3. Registry tagging can fail with `CRI0302E` when the manifest type is not supported for tagging.
4. Because of that, "build an image somewhere and push it" is not a safe assumption for this deployment package.

Practical rule for this repository:

1. Use `source_build` when you want the smallest operator workflow.
2. Use `prebuilt_images` when you need explicit image build, tagging, push, and reuse control.
3. Keep the prebuilt-image workflow on supported image formats and a validated target platform.

## Deployment Order

This package now uses an explicit phased order because some URLs are only known after Code Engine creates each app:

1. create or select the Code Engine project
2. create secrets and any static configmaps such as the Keycloak realm import
3. when `DEPLOY_ARTIFACT_MODE=prebuilt_images`, build and push the five Galaxium service images to IBM Cloud Container Registry
4. when `STACK_AUTH_MODE=oauth2`, deploy Keycloak in the same Code Engine project
5. deploy HR, REST, and MCP first, generating or updating the service runtime configmaps from env files as the public URLs become available
6. when `STACK_AUTH_MODE=oauth2`, sync the Keycloak client with the final public UI URLs
7. print the final summary and smoke-test commands

This follows the same practical issue from older Code Engine automation: public routes are deployment outputs, so later steps must read them back before configuring dependent apps.

## Current Service Mapping

| Component | Artifact Source | Container Port | Notes |
| --- | --- | --- | --- |
| Keycloak | `quay.io/keycloak/keycloak:26.0` | `8080` | `8080` is the in-container listen port only. Public access uses the generated Code Engine app URL, not `:8080` |
| HR API | local source `HR_database/` or prebuilt ICR image | `8081` | File-backed data is ephemeral without a mounted data store |
| Booking REST API | local source `booking_system_rest/` or prebuilt ICR image | `8082` | Supports `AUTH_MODE=oauth2` or `AUTH_MODE=basic` |
| Booking MCP server | local source `booking_system_mcp/` or prebuilt ICR image | `8084` | Public MCP endpoint stays `${MCP_URL}/mcp` with Streamable HTTP |
| REST Web UI | local source `galaxium-booking-web-app/` or prebuilt ICR image | `8083` | Supports OAuth browser login or Basic Auth guest mode |
| MCP Web UI | local source `galaxium-booking-web-app-mcp/` or prebuilt ICR image | `8085` | Uses the direct Python MCP client over Streamable HTTP |

## Port Model in Code Engine

The ports in the table above are container listen ports, not fixed public browser ports.

For Keycloak specifically:

- `scripts/03-deploy-keycloak.sh` deploys the container with `--port 8080` because Keycloak listens on `8080` inside the container.
- Code Engine then exposes that container through a generated public HTTPS application URL.
- The other Galaxium services do not call `https://...:8080`.
- They use the resolved public Keycloak base URL returned by Code Engine, for example from `ce_app_url "${KEYCLOAK_APP_NAME}"`.

So the Code Engine model is different from local Docker Compose:

- local compose uses host `8086` mapped to container `8080`
- Code Engine uses container `8080` behind a generated public route, with no separate public `8086`

## Files

- [`deploy.env.template`](./deploy.env.template)
  - Copy this to `deploy.env` and fill in the values.
- [`scripts/00-prereqs.sh`](./scripts/00-prereqs.sh)
  - Check required local commands, verify the Code Engine plugin, and show whether the deployment will use `IBM_CLOUD_API_KEY` or an existing interactive `ibmcloud login` session.
  - In `prebuilt_images` mode, also checks the Container Registry plugin and the selected container client.
- [`scripts/01-project.sh`](./scripts/01-project.sh)
  - Target IBM Cloud and create or select the Code Engine project.
- [`scripts/02-config-and-secrets.sh`](./scripts/02-config-and-secrets.sh)
  - Create the Keycloak realm configmap when needed, the application secrets, and the Code Engine registry secret for prebuilt-image mode.
- [`scripts/02b-build-and-push-images.sh`](./scripts/02b-build-and-push-images.sh)
  - In `prebuilt_images` mode, build the five Galaxium service images locally and push them to IBM Cloud Container Registry.
- [`scripts/03-deploy-keycloak.sh`](./scripts/03-deploy-keycloak.sh)
  - Deploy Keycloak inside the same Code Engine project for `oauth2` mode.
- [`scripts/04-deploy-services.sh`](./scripts/04-deploy-services.sh)
  - Deploy HR, REST, and MCP first, then deploy REST UI and MCP UI with the resolved URLs.
  - Renders per-service env files, updates the runtime configmaps, and binds them to the apps with `--env-from-configmap`.
  - Uses either `--build-source` or `--image` depending on `DEPLOY_ARTIFACT_MODE`.
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

Additional local installs for `DEPLOY_ARTIFACT_MODE=prebuilt_images`:

1. IBM Cloud Container Registry plugin for the CLI
2. `docker` or `podman`

IBM Cloud login options:

1. Non-interactive automation
   Set `IBM_CLOUD_API_KEY` in `deploy.env`.
   The scripts will run `ibmcloud login --apikey ... -r <region> -g <resource-group>` automatically.
2. Interactive operator session
   Leave `IBM_CLOUD_API_KEY` empty and run `ibmcloud login` yourself before `scripts/01-project.sh`.

Operator preparation:

1. Copy `deploy.env.template` to `deploy.env`.
2. Fill in the real secret values before running any script.
3. Keep the current default `STACK_AUTH_MODE=basic` for the first deployment, or switch to `STACK_AUTH_MODE=oauth2` when you are ready for the Keycloak-dependent variant.
4. Decide whether you will use `DEPLOY_ARTIFACT_MODE=source_build` or `DEPLOY_ARTIFACT_MODE=prebuilt_images`.
5. If you use `oauth2`, decide whether Keycloak will be deployed in the same Code Engine project or provided externally through `KEYCLOAK_BASE_URL_OVERRIDE`.
6. If you use `prebuilt_images`, fill in the IBM Cloud Container Registry values such as `ICR_NAMESPACE`, `ICR_REGISTRY`, `IMAGE_TAG`, and the image repository names.

Example:

```sh
cd deployment/ibm-code-engine
cp deploy.env.template deploy.env
bash scripts/00-prereqs.sh
```

## Current Default Path

The folder is currently preconfigured for the Basic Auth deployment option.

That means:

- `deploy.env.template` starts with `STACK_AUTH_MODE=basic`
- `FRONTEND_AUTH_REQUIRED` resolves to `false` unless you change it
- `scripts/03-deploy-keycloak.sh` and `scripts/05-sync-keycloak-client.sh` skip automatically
- the non-secret runtime settings are expected to flow through the service configmaps, not through direct `ibmcloud ce application ... --env ...` flags
- the first live validation path should be the Basic Auth REST and MCP checks printed by `scripts/06-summary.sh`

Switch to `STACK_AUTH_MODE=oauth2` only when you are ready to configure the Keycloak-dependent variant.

Required CLI checks:

```sh
ibmcloud version
ibmcloud plugin show code-engine
ibmcloud plugin list
```

Additional CLI checks for `DEPLOY_ARTIFACT_MODE=prebuilt_images`:

```sh
ibmcloud plugin show container-registry
docker version
```

If you use `CONTAINER_CLIENT=podman`, replace `docker version` with `podman version`.

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
8. `ibmcloud cr region-set`, `namespace-list`, `namespace-add`, and `login`

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
bash scripts/02b-build-and-push-images.sh
bash scripts/03-deploy-keycloak.sh
bash scripts/04-deploy-services.sh
bash scripts/05-sync-keycloak-client.sh
bash scripts/06-summary.sh
```

Notes:

- In `DEPLOY_ARTIFACT_MODE=source_build`, `scripts/02b-build-and-push-images.sh` exits with a skip message.
- In `DEPLOY_ARTIFACT_MODE=prebuilt_images`, run `scripts/02b-build-and-push-images.sh` before `scripts/04-deploy-services.sh`.
- In the current default `STACK_AUTH_MODE=basic`, the practical operator flow is `00 -> 01 -> 02 -> 02b optional -> 04 -> 06`.
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

- `DEPLOY_ARTIFACT_MODE`
  - `source_build` or `prebuilt_images`
  - `source_build` uses `--build-source`
  - `prebuilt_images` uses local image build plus IBM Cloud Container Registry push

- `ICR_REGION`
  - Target IBM Cloud Container Registry region for the prebuilt-image workflow

- `ICR_REGISTRY`
  - Registry host such as `us.icr.io`

- `ICR_NAMESPACE`
  - Namespace that stores the pushed Galaxium images

- `ICR_REGISTRY_SECRET_NAME`
  - Code Engine registry secret used to pull the private images

- `ICR_REGISTRY_USERNAME`
  - Defaults to `iamapikey`
  - Used only in `prebuilt_images` mode when the Code Engine registry secret is created

- `ICR_REGISTRY_PASSWORD`
  - Optional
  - Leave it empty to reuse `IBM_CLOUD_API_KEY`
  - Set it explicitly when registry authentication must differ from the IBM Cloud login credential

- `IMAGE_TAG`
  - Shared tag that is applied to all pushed Galaxium service images

- `CONTAINER_CLIENT`
  - `docker` or `podman`
  - Used only in `prebuilt_images` mode

- `CONTAINER_PLATFORM`
  - Defaults to `linux/amd64`
  - Used only in `prebuilt_images` mode to reduce registry and Code Engine compatibility risk

- `HR_IMAGE_REPOSITORY`, `BOOKING_API_IMAGE_REPOSITORY`, `MCP_IMAGE_REPOSITORY`, `WEB_APP_IMAGE_REPOSITORY`, `WEB_APP_MCP_IMAGE_REPOSITORY`
  - Repository names inside the selected IBM Cloud Container Registry namespace
  - Used only in `prebuilt_images` mode

- `STACK_AUTH_MODE`
  - `oauth2` or `basic`
  - current template default: `basic`
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

1. The Keycloak deployment is still demo-oriented because it uses `start-dev` when you choose `STACK_AUTH_MODE=oauth2`.
2. Keycloak and HR state are ephemeral unless you add persistent storage.
3. In Code Engine, the listed service ports are container ports. Public access always uses the generated application URL.
4. The MCP server public base URL must point to the Code Engine public app URL, and public clients must call `/mcp`.
5. The MCP transport must not be changed from `Streamable HTTP`.
6. The web UIs depend on public service URLs. This is simple, but it is not the most private or cost-efficient production setup.
7. The imported Keycloak realm is local-dev shaped, so the client URL sync step is needed after the Code Engine UI URLs exist.
8. The prebuilt-image path assumes a supported image manifest format and defaults to `CONTAINER_PLATFORM=linux/amd64` to reduce Code Engine compatibility risk.

## What Is Not Automated Yet

This folder does not currently automate:

1. IBM Cloud CLI installation
2. Code Engine plugin installation
3. IBM Cloud Container Registry plugin installation
4. custom domains
5. managed TLS certificate setup
6. persistent data store creation and binding
7. mirroring the Keycloak base image into IBM Cloud Container Registry
8. Terraform-based deployment
9. production hardening of the Keycloak runtime

## Local Validation Done In This Workspace

These checks were completed locally:

- all deployment scripts were updated to the current service set
- the env template was updated so the current default is `STACK_AUTH_MODE=basic`
- the README was synced with the scripts
- shell syntax validation was run on the deployment scripts
- dry environment validation was run for both `source_build` and `prebuilt_images`

These checks were not completed here:

- live `ibmcloud` CLI execution
- live Code Engine source builds
- live local image build and push to IBM Cloud Container Registry
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
