# Dependency License Transparency

Review date: 2026-05-29

This document maps the repository's observed direct dependencies by service and
runtime surface. It is based on the service `requirements.txt` files,
Dockerfiles, local-container compose files, verification scripts, and frontend
templates present in the repository at review time.

This is not a full SBOM. It does not enumerate transitive Python packages,
container OS packages, npm transitive dependencies, hosted service terms, or
runtime packages installed on a developer workstation.

## Scope and Assumptions

- The repository does not currently have a single root dependency manifest or
  lockfile.
- Several Python dependencies are not version pinned, so resolved versions and
  license metadata can drift between installs.
- Container image contents are summarized by base image only. Their full OS and
  language-package inventory should be generated from the built images before
  release.
- Tooling such as `npx`, MCP Inspector, `curl`, `jq`, Docker Desktop, Rancher
  Desktop, IBM Cloud CLI, and Code Engine is external to the repository unless
  explicitly vendored later.
- License values below reflect known project metadata or existing repository
  documentation and should be verified against package metadata during release.

## Service Dependency Mapping

### `booking_system_rest/`

| Dependency | Version constraint | License | Source |
| --- | --- | --- | --- |
| `python:3.11-slim` | Docker base image | Python/Debian image contents under separate licenses | `booking_system_rest/Dockerfile` |
| `fastapi` | Not pinned | MIT | `booking_system_rest/requirements.txt` |
| `uvicorn` | Not pinned | BSD-3-Clause | `booking_system_rest/requirements.txt` |
| `sqlalchemy` | Not pinned | MIT | `booking_system_rest/requirements.txt` |
| `databases` | Not pinned | BSD | `booking_system_rest/requirements.txt` |
| `pydantic[email]` | Not pinned | MIT | `booking_system_rest/requirements.txt` |
| `python-dotenv` | Not pinned | BSD-3-Clause | `booking_system_rest/requirements.txt` |
| `pytest` | Not pinned | MIT | `booking_system_rest/requirements.txt` |
| `pytest-asyncio` | Not pinned | Apache-2.0 | `booking_system_rest/requirements.txt` |
| `pytest-cov` | Not pinned | MIT | `booking_system_rest/requirements.txt` |
| `httpx` | Not pinned | BSD-3-Clause | `booking_system_rest/requirements.txt` |
| `pytest-mock` | Not pinned | MIT | `booking_system_rest/requirements.txt` |
| `PyJWT[crypto]` | Not pinned | MIT | `booking_system_rest/requirements.txt` |

### `booking_system_mcp/`

| Dependency | Version constraint | License | Source |
| --- | --- | --- | --- |
| `python:3.11-slim` | Docker base image | Python/Debian image contents under separate licenses | `booking_system_mcp/Dockerfile` |
| `fastapi` | Not pinned | MIT | `booking_system_mcp/requirements.txt` |
| `uvicorn` | Not pinned | BSD-3-Clause | `booking_system_mcp/requirements.txt` |
| `sqlalchemy` | Not pinned | MIT | `booking_system_mcp/requirements.txt` |
| `databases` | Not pinned | BSD | `booking_system_mcp/requirements.txt` |
| `pydantic` | Not pinned | MIT | `booking_system_mcp/requirements.txt` |
| `python-dotenv` | Not pinned | BSD-3-Clause | `booking_system_mcp/requirements.txt` |
| `fastmcp` | Not pinned | Apache-2.0 | `booking_system_mcp/requirements.txt` |
| `PyJWT[crypto]` | Not pinned | MIT | `booking_system_mcp/requirements.txt` |

### `galaxium-booking-web-app/`

| Dependency | Version constraint | License | Source |
| --- | --- | --- | --- |
| `python:3.12-slim` | Docker base image | Python/Debian image contents under separate licenses | `galaxium-booking-web-app/Dockerfile` |
| `Flask` | `3.1.1` | BSD-3-Clause | `galaxium-booking-web-app/app/requirements.txt` |
| `flask-cors` | `3.0.10` | MIT | `galaxium-booking-web-app/app/requirements.txt` |
| `requests` | `2.31.0` | Apache-2.0 | `galaxium-booking-web-app/app/requirements.txt` |
| IBM Plex Sans | Remote Google Fonts load | Verify font license and Google Fonts terms | `galaxium-booking-web-app/app/templates/*.html` |
| Space Grotesk | Remote Google Fonts load | Verify font license and Google Fonts terms | `galaxium-booking-web-app/app/templates/*.html` |

### `galaxium-booking-web-app-mcp/`

| Dependency | Version constraint | License | Source |
| --- | --- | --- | --- |
| `python:3.12-slim` | Docker base image | Python/Debian image contents under separate licenses | `galaxium-booking-web-app-mcp/Dockerfile` |
| `Flask` | `3.1.1` | BSD-3-Clause | `galaxium-booking-web-app-mcp/app/requirements.txt` |
| `flask-cors` | `3.0.10` | MIT | `galaxium-booking-web-app-mcp/app/requirements.txt` |
| `httpx` | `0.28.1` | BSD-3-Clause | `galaxium-booking-web-app-mcp/app/requirements.txt` |
| `mcp` | `>=1.26.0,<2` | MIT | `galaxium-booking-web-app-mcp/app/requirements.txt` |
| `requests` | `2.31.0` | Apache-2.0 | `galaxium-booking-web-app-mcp/app/requirements.txt` |
| IBM Plex Sans | Remote Google Fonts load | Verify font license and Google Fonts terms | `galaxium-booking-web-app-mcp/app/templates/*.html` |
| Space Grotesk | Remote Google Fonts load | Verify font license and Google Fonts terms | `galaxium-booking-web-app-mcp/app/templates/*.html` |

### `HR_database/`

| Dependency | Version constraint | License | Source |
| --- | --- | --- | --- |
| `python:3.11-slim` | Docker base image | Python/Debian image contents under separate licenses | `HR_database/Dockerfile` |
| `fastapi` | `0.104.1` | MIT | `HR_database/requirements.txt` |
| `uvicorn` | `0.24.0` | BSD-3-Clause | `HR_database/requirements.txt` |
| `python-multipart` | `0.0.6` | Apache-2.0 | `HR_database/requirements.txt` |
| `pydantic` | `2.4.2` | MIT | `HR_database/requirements.txt` |
| `pandas` | Not pinned | BSD-3-Clause | `HR_database/Dockerfile` |

## Shared Runtime, Verification, and Deployment Dependencies

| Component | Version / source | Observed use | License or terms note |
| --- | --- | --- | --- |
| Keycloak | `quay.io/keycloak/keycloak:26.0` | Local OAuth/OIDC identity provider | Keycloak is Apache-2.0 licensed; image layers may include additional packages and notices. |
| Docker Desktop | Host-installed runtime | Local container execution | Subject to Docker product and subscription terms. Not vendored. |
| Rancher Desktop | Host-installed runtime alternative | Local container execution | Apache-2.0 project with bundled component notices. Not vendored. |
| IBM Cloud / Code Engine | External cloud service | Deployment target and documentation | Governed by IBM Cloud service terms, subscription agreements, regional terms, CLI/plugin terms, and service documentation. |
| IBM Container Registry | External cloud service | Container image registry path for cloud deployment | Governed by IBM Cloud service terms. |
| MCP Inspector | `npx @modelcontextprotocol/inspector` | Optional MCP verification UI/CLI | Fetched through npm at runtime; verify current npm package version, license, and dependencies. |
| `npx` / npm CLI | Host-installed Node tooling | Runtime package execution for MCP Inspector | npm CLI/tooling is distributed separately; registry access may be subject to npm service terms. |
| `curl` | Host or container tool | Verification scripts, setup checks, API calls | curl license. Not vendored. |
| `jq` | Host or container tool | JSON verification in scripts | MIT license for `jq`; related documentation/components can have separate notices. Not vendored. |
| Images and GIFs | `images/` | README and documentation screenshots/demos | Treat as project documentation assets with embedded third-party UI/trademark rights retained by their owners. |
| Draw.io diagrams | `architecture/` | Architecture documentation | Project diagram sources/exports; built-in shapes/icons may carry separate terms. |
| Generated docs | `docs/reference/` | Supplemental documentation | AI-assisted/generated docs requiring human review and provenance tracking. |

## Known Compliance Gaps

| Gap | Impact | Recommended remediation |
| --- | --- | --- |
| No root lockfile or generated dependency report | Install-time drift can change resolved dependencies and license obligations. | Pin service dependencies or generate per-service lockfiles before release. |
| No transitive dependency license inventory | Direct-license table is not enough for redistribution or audit review. | Generate `pip-licenses` or CycloneDX reports for each service environment. |
| No container image SBOM | Base image and OS package obligations are not fully visible. | Generate SBOMs for built images using `syft`, `docker scout sbom`, or equivalent. |
| MCP Inspector fetched dynamically with `npx` | Runtime package version and license can change. | Pin the npm package version in scripts or document the verified version in release evidence. |
| `pandas` installed separately and unpinned in `HR_database/Dockerfile` | Build output can drift independently from `requirements.txt`. | Move `pandas` into `HR_database/requirements.txt` with an explicit version constraint. |
| Generated docs lack explicit provenance metadata | Future audits may not distinguish human-authored, AI-assisted, copied, or generated content. | Add provenance notes, human-review evidence, and source attribution for generated documentation. |

## Suggested Release-Time Verification Commands

Run these in isolated service environments before publication:

```bash
python -m pip install pip-licenses
python -m piplicenses --format=markdown --with-urls --with-system
npm view @modelcontextprotocol/inspector version license dependencies
docker scout sbom <built-image>
syft <built-image>
curl --version
jq --version
docker --version
```

Store generated reports as release artifacts or in a dedicated compliance
directory if this repository is redistributed or used for customer-facing
delivery.

