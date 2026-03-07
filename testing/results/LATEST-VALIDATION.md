# Latest Validation

- Run date: `2026-03-07`
- Command: `bash testing/automation/run-all-tests.sh`
- Overall status: `PASS`

## Suite Results

- REST API tests: `PASS`
  - Result: `33 passed`
  - Log: `testing/results/generated/rest/rest-api-pytest-20260307T112311Z.log`

- UI behavior checks: `PASS`
  - Coverage: login redirect, unauthenticated API rejection, traveler session flow, authenticated flights/bookings/book calls
  - Markdown report: `testing/results/generated/ui/oauth-e2e-ui-rest-20260307T112326Z.md`
  - JSON report: `testing/results/generated/ui/oauth-e2e-ui-rest-20260307T112326Z.json`
  - Log: `testing/results/generated/ui/oauth-e2e-ui-rest-20260307T112326Z.log`

- MCP integration checks: `PASS`
  - Coverage: OAuth metadata discovery, unauthenticated `initialize`, authenticated `initialize`, authenticated `tools/list`
  - Markdown report: `testing/results/generated/mcp/oauth-e2e-mcp-20260307T112338Z.md`
  - JSON report: `testing/results/generated/mcp/oauth-e2e-mcp-20260307T112338Z.json`
  - Log: `testing/results/generated/mcp/oauth-e2e-mcp-20260307T112338Z.log`

## Notes

- The REST suite still emits existing deprecation warnings from FastAPI, SQLAlchemy, and Pydantic, but the tests pass.
- The UI and MCP suites run against the docker-compose stack and clean it up after execution.
