# Third-Party Notices

Review date: 2026-05-29

This project is licensed under the Apache License 2.0 as described in
`LICENSE`. This notice documents known third-party components, tools,
services, media, fonts, and generated documentation used by the repository.
It is a transparency aid and not legal advice. Package metadata, hosted
service terms, and container image contents can change over time; verify them
again before redistribution, public release, or enterprise procurement review.

## Python Dependencies

The repository contains multiple Python services with service-local
`requirements.txt` files. Known direct Python dependencies include:

| Component | Observed use | Declared license |
| --- | --- | --- |
| `fastapi` | REST API, MCP API, HR service | MIT |
| `uvicorn` | REST API, MCP API, HR service | BSD-3-Clause |
| `sqlalchemy` | REST API, MCP API | MIT |
| `databases` | REST API, MCP API | BSD |
| `pydantic` / `pydantic[email]` | REST API, MCP API, HR service | MIT |
| `python-dotenv` | REST API, MCP API | BSD-3-Clause |
| `fastmcp` | MCP API | Apache-2.0 |
| `PyJWT[crypto]` | REST API, MCP API | MIT |
| `python-multipart` | HR service | Apache-2.0 |
| `pandas` | HR service container build | BSD-3-Clause |
| `Flask` | Web frontends | BSD-3-Clause |
| `flask-cors` | Web frontends | MIT |
| `requests` | Web frontends | Apache-2.0 |
| `httpx` | MCP web frontend and REST tests | BSD-3-Clause |
| `mcp` | MCP web frontend | MIT |
| `pytest`, `pytest-asyncio`, `pytest-cov`, `pytest-mock` | REST test tooling | MIT / Apache-2.0 |

See `docs/DEPENDENCY_LICENSE_TRANSPARENCY.md` for the per-service dependency
mapping. This project does not currently include a root lockfile, generated
SBOM, or transitive dependency license report.

## Containers, Base Images, and Runtime Tools

| Component | Observed use | License or terms note |
| --- | --- | --- |
| `quay.io/keycloak/keycloak:26.0` | Local identity provider in `local-container/docker_compose.yaml` | Keycloak is Apache-2.0 licensed. Container layers may include additional third-party and OS packages under their own licenses. |
| `python:3.11-slim` | REST API, MCP API, HR service base image | Python image content includes Python, Debian packages, and image build artifacts under their own licenses. |
| `python:3.12-slim` | Web frontend base images | Python image content includes Python, Debian packages, and image build artifacts under their own licenses. |
| Docker Desktop | Optional local container runtime | Subject to Docker subscription and product terms. Not vendored in this repository. |
| Rancher Desktop | Optional local container runtime alternative | Rancher Desktop is Apache-2.0 licensed; bundled components may have additional notices. Not vendored in this repository. |
| `curl` | Verification scripts and setup commands | curl license. Installed on the host or container environment; not vendored here. |
| `jq` | Verification scripts and JSON assertions | MIT license for `jq`; related documentation and embedded components can carry separate notices. Installed on the host or container environment; not vendored here. |

## IBM Cloud and Code Engine

This repository contains deployment and operations guidance for IBM Cloud and
IBM Cloud Code Engine. IBM Cloud, Code Engine, IBM Container Registry, IBM
Cloud CLI, and any IBM CLI plugins are external services/tools governed by
their IBM license agreements, service descriptions, acceptable-use terms, and
cloud subscription terms. They are not redistributed by this repository.

Before publishing deployment instructions for production use, validate the
current IBM Cloud terms, region-specific requirements, quota limits, and any
required notices for IBM tooling used by the deployment path.

## MCP Inspector and Node Tooling

The local verification scripts can invoke MCP Inspector through:

```text
npx @modelcontextprotocol/inspector
```

`@modelcontextprotocol/inspector` is fetched at runtime through the npm
ecosystem and is not vendored in this repository. Verify the package version,
license metadata, dependencies, and transitive notices at the time it is used.
`npx` is provided by npm tooling; npm CLI is distributed separately and access
to the npm registry or hosted services may be subject to separate terms.

## Images, Screenshots, GIFs, and Diagrams

The repository includes demonstration media under `images/` and architecture
diagrams under `architecture/`, including screenshots, GIFs, Draw.io sources,
SVG, PNG, and JPG files. Unless a file states otherwise, these assets should be
treated as project documentation assets covered by the repository license only
to the extent the project owner has rights to license them.

Some images may show third-party UIs, product names, logos, web pages, cloud
consoles, Keycloak screens, MCP Inspector screens, or other trademarked
interfaces. Those screenshots do not grant rights in the underlying
third-party products, trademarks, service marks, UI designs, or hosted content.
Do not reuse these assets outside this project without confirming provenance
and trademark permissions.

Draw.io diagrams may use built-in shape libraries or icons. Those source
libraries can carry their own terms. Retain diagram source files and exported
images together when redistributing documentation.

## Fonts

The web frontend templates load fonts from Google Fonts:

| Font | Observed use | Notes |
| --- | --- | --- |
| IBM Plex Sans | Web frontend templates and CSS font stack | Loaded remotely from Google Fonts; not vendored in this repository. Verify the font license and Google Fonts terms before bundling or redistributing font files. |
| Space Grotesk | Web frontend templates and CSS font stack | Loaded remotely from Google Fonts; not vendored in this repository. Verify the font license and Google Fonts terms before bundling or redistributing font files. |

If the project later vendors font files, add the exact font license files and
copyright notices.

## Generated and AI-Assisted Documentation

The `docs/reference/` directory contains supplemental generated or
AI-assisted documentation. These files should be treated as project-maintained
documentation artifacts that require human review before release. Keep a record
of generation provenance, reviewer approval, source inputs, and any copied
third-party excerpts for future auditability.

Generated documentation does not remove the need to verify third-party license
metadata, container image contents, diagrams, screenshots, or external service
terms.

## Maintenance Rule

Update this file when:

- A dependency, base image, external CLI, hosted service, font, image, diagram,
  or generated documentation source is added or removed.
- A dependency version is pinned, upgraded, or moved between services.
- A container image, npm package, or Python dependency is redistributed rather
  than fetched at install/runtime.
- A generated SBOM or license scan becomes available.

