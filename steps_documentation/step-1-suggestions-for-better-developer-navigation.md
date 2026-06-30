# Step 1 — Suggestions for Better Developer Navigation

**Galaxium Travels Infrastructure · Repository structure & developer experience review**

> **Context:** The repository had 5 services, 4 runtime options, 3 auth modes, 30+ Markdown files, 9 Compose files, and 6 verification scripts spread across 7+ directories. The documentation was accurate and detailed, but a developer arriving for the first time faced a flat list of files with no clear entry-path map. The same options (Option 1–4) were repeated across `README.md`, `QUICKSTART.md`, `local-container/README.md`, and `ARCHITECTURE.md` with slightly different command forms — creating cognitive load without adding clarity.

---

## Suggestion 1 — Add a single-page Navigation Hub (`NAVIGATOR.md`) `new file` · **high impact**

*Addresses: first-run disorientation and scattered entry points*

**Problem:** `README.md`, `QUICKSTART.md`, `ARCHITECTURE.md`, and `local-container/README.md` all started users in different places. A developer scanning the repo root saw 7 top-level Markdown files with no explicit priority order.

**Suggestion:** Create a `NAVIGATOR.md` at the repo root that acts as a single-page decision tree: "What do you want to do?" → one link. Four clear paths: *Run it locally*, *Understand the architecture*, *Integrate an agent / AI engineer*, *Deploy to IBM Code Engine*. Each path links directly to the correct section — not to another guide's top level.

**Status:** ✅ Implemented — [`NAVIGATOR.md`](../NAVIGATOR.md)

---

## Suggestion 2 — Create an "AI Engineer Fast Lane" section `AI-focused` · **high impact**

*Addresses: AI/agent integration buried inside the general quickstart*

**Problem:** AI engineers (Watson Orchestrate, agent developers, LLM tool integrators) wanted to know: what is the MCP endpoint URL, what auth do I send, what tools exist, and where is the OpenAPI/MCP schema? That answer was spread across `QUICKSTART.md`, `manual_auth_check_using_the_commandline.md`, the MCP server README, and the `ai_generated_documentation/` folder.

**Suggestion:** Add a dedicated `docs/AI_ENGINEER_GUIDE.md` that consolidates: MCP endpoint, available tools, credential options, inspector workflow, vm-client env templates, and pointer to Watson Orchestrate guide.

**Status:** ✅ Implemented — [`docs/AI_ENGINEER_GUIDE.md`](../docs/AI_ENGINEER_GUIDE.md)

---

## Suggestion 3 — Replace 4-option prose repetition with a single Auth × Deployment matrix table `refactor` · **high impact**

*Addresses: Option 1–4 listed in 3 different files with slightly different command syntax*

**Problem:** `QUICKSTART.md`, `local-container/README.md`, and `ARCHITECTURE.md` each described Option 1–4 with nearly identical text. Keeping them in sync manually is error-prone.

**Suggestion:** Consolidate into one canonical **configuration matrix table** in `ARCHITECTURE.md`. `QUICKSTART.md` references that section and only adds the command-line steps. `local-container/README.md` becomes the command reference, not the decision guide.

**Status:** ✅ Implemented — canonical tables in [`ARCHITECTURE.md — Authentication Variants`](../ARCHITECTURE.md#authentication-variants) and [`ARCHITECTURE.md — Deployment View`](../ARCHITECTURE.md#deployment-view); `QUICKSTART.md` and `local-container/README.md` reference them.

---

## Suggestion 4 — Add a "Compose file → purpose" reference table to `local-container/README.md` `docs` · **medium impact**

*Addresses: 5 Compose files with similar names, no summary of which to use when*

**Problem:** `docker_compose.yaml`, `docker_compose.vm-oauth.yaml`, `docker_compose.basic-auth.yaml`, `docker_compose.basic-auth-vm.yaml`, and `docker_compose.mcp-ui-keycloak-basic.yaml` were all in the same flat directory with no at-a-glance explanation of the layering model.

**Suggestion:** Add a quick-reference table: file name | role (base / overlay) | use case | required env file.

**Status:** ✅ Implemented — [`local-container/README.md — Compose Files At A Glance`](../local-container/README.md#compose-files-at-a-glance)

---

## Suggestion 5 — Add a "verification script → what it checks" reference table `docs` · **medium impact**

*Addresses: 9 verify-*.sh scripts with no summary in one place*

**Problem:** There were 9 shell verification scripts in `local-container/` and 6 in `testing/automation/`. A developer who wanted to validate a specific scenario had to grep through README files to find the right command.

**Suggestion:** Add a single reference table to `testing/README.md`: script name | scenario | requires Docker stack | typical run time. Place an identical condensed version in `local-container/README.md` for local-only scripts.

**Status:** ✅ Implemented — [`testing/README.md — Automation Scripts At A Glance`](../testing/README.md#automation-scripts-at-a-glance) and [`local-container/README.md — Verification Scripts At A Glance`](../local-container/README.md#verification-scripts-at-a-glance)

---

## Suggestion 6 — Move loose top-level docs into a `docs/` subdirectory `refactor` · **medium impact**

*Addresses: 7 Markdown files cluttering the root alongside LICENSE, .gitignore, etc.*

**Problem:** The root directory contained `manual_auth_check_using_the_commandline.md`, `watsonx_orchestrate_basic_auth_example_integration.md`, `QUALITY-CHECK.md`, `DEPENDENCY_LICENSE_TRANSPARENCY.md`, `THIRD_PARTY_NOTICES.md`, and `ARCHITECTURE.md` alongside code, making it harder to distinguish "things you run" from "things you read".

**Suggestion:** Move secondary reference docs into a `docs/` folder. Keep only `README.md`, `QUICKSTART.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `AGENTS.md`, and `LICENSE` at the root.

**Status:** ✅ Implemented — `docs/` folder contains moved files.

---

## Suggestion 7 — Rename `ai_generated_documentation/` → `docs/reference/` `refactor` · **low impact**

*Addresses: folder name implied low authority; content is actually useful*

**Problem:** `ai_generated_documentation/` contained setup guides for Watson Orchestrate, deployment changelogs, and suggested implementation changes. The folder name signalled "ignore this" to engineers, but some content was genuinely useful reference material.

**Suggestion:** Rename to `docs/reference/`. Move Watson Orchestrate guide and Code Engine Keycloak guide into `docs/` as first-class documents. Move changelogs and implementation suggestions into `docs/changelog/`.

**Status:** ✅ Implemented — [`docs/reference/`](../docs/reference/) contains `WATSONX_ORCHESTRATE_BOOKING_MCP_SETUP_GUIDE.md` and `CODE_ENGINE_KEYCLOAK_DEPLOYMENT.md`.

---

## Suggestion 8 — Add per-service README standard header blocks `docs` · **low impact**

*Addresses: each service README had different depth and structure*

**Problem:** Service READMEs had inconsistent depth. Some had testing guides, some did not. This made it hard to use the services independently.

**Suggestion:** Standardize each service README with a minimal consistent header block: port, entry point, auth config, local run command, test command, compose service name. Identical shape across all services.

**Status:** ✅ Implemented — all five service READMEs ([`booking_system_rest`](../booking_system_rest/README.md), [`booking_system_mcp`](../booking_system_mcp/README.md), [`galaxium-booking-web-app`](../galaxium-booking-web-app/README.md), [`galaxium-booking-web-app-mcp`](../galaxium-booking-web-app-mcp/README.md), [`HR_database`](../HR_database/README.md)) have the standard header table.

---

## Suggestion 9 — Add a `LLMS.txt` machine-readable summary `AI-focused` · **medium impact**

*Addresses: AI agents and LLM-powered tools had no compact codebase summary to start from*

**Problem:** When an AI engineer pasted the repository URL into an LLM coding assistant or Watson Orchestrate, the assistant had to read and summarize from scratch. `AGENTS.md` was agent-workflow-focused, not codebase-summary-focused.

**Suggestion:** Create a `LLMS.txt` (following the [llmstxt.org](https://llmstxt.org) convention) providing a machine-readable, concise overview: services, ports, auth modes, key files, test commands, and non-obvious patterns.

**Status:** ✅ Implemented — [`LLMS.txt`](../LLMS.txt)

---

## Summary by priority and effort

| # | Suggestion | Impact | Effort | File changes | Status |
|---|---|---|---|---|---|
| 1 | NAVIGATOR.md — single decision-tree hub | High | Low | 1 new file | ✅ Done |
| 2 | AI Engineer Fast Lane guide | High | Low | 1 new file | ✅ Done |
| 3 | Auth × Deployment matrix (eliminate Option repetition) | High | Medium | 3 existing files updated | ✅ Done |
| 4 | Compose file reference table in `local-container/README.md` | Medium | Low | 1 existing file updated | ✅ Done |
| 5 | Verification script reference table | Medium | Low | 2 existing files updated | ✅ Done |
| 6 | Move secondary docs to `docs/` subdirectory | Medium | Medium | ~6 files moved + links updated | ✅ Done |
| 7 | Rename `ai_generated_documentation/` → `docs/reference/` | Low | Low | 1 directory rename + links | ✅ Done |
| 8 | Standardize per-service README header blocks | Low | Medium | 5 existing files updated | ✅ Done |
| 9 | LLMS.txt / CONTEXT.md machine-readable summary | Medium | Low | 1 new file | ✅ Done |

**All 9 suggestions have been implemented.** This document serves as the decision record for the developer-navigation improvement sprint.
