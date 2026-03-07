# Test Results

This folder documents the latest validated state of the repository.

## Layout

- `LATEST-VALIDATION.md`: human-readable summary of the most recent full validation run committed to the repository
- `generated/`: raw logs and generated reports from the automation scripts

## Generated Artifact Types

REST suite:

- `rest/rest-api-pytest-<timestamp>.log`

UI behavior suite:

- `ui/oauth-e2e-ui-rest-<timestamp>.log`
- `ui/oauth-e2e-ui-rest-<timestamp>.md`
- `ui/oauth-e2e-ui-rest-<timestamp>.json`
- `ui/oauth-e2e-ui-rest-<timestamp>.steps.tsv`

MCP integration suite:

- `mcp/oauth-e2e-mcp-<timestamp>.log`
- `mcp/oauth-e2e-mcp-<timestamp>.md`
- `mcp/oauth-e2e-mcp-<timestamp>.json`
- `mcp/oauth-e2e-mcp-<timestamp>.steps.tsv`

`generated/` is intentionally not tracked in git.
