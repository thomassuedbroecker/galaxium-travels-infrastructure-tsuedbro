# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Coding Rules (Non-Obvious)

- **Error responses are HTTP 200**: Business-logic errors in `booking_system_rest/app.py` return `JSONResponse(status_code=200, content=ErrorResponse(...).model_dump())` via `create_error_response()`. Never raise `HTTPException` for business errors in REST routes — use the pattern. Tests check `response.json()["success"] == False`, not `response.status_code`.

- **Pydantic model name collision pattern**: SQLAlchemy ORM models must be imported as aliases (`from models import Booking as BookingModel`) because Pydantic schema classes share the same names. Always follow this when adding new schemas.

- **`ConfigDict(from_attributes=True)` not `class Config: orm_mode = True`**: The codebase uses Pydantic v2 ORM config. `booking_system_mcp/mcp_server.py` still uses the v1 pattern — do not follow it for new code in the REST service.

- **`seed()` wipes the DB on every startup**: Do not rely on DB state persisting between dev server restarts.

- **Tests must disable auth**: `conftest.py` automatically disables auth via `monkeypatch` on all tests. Never set auth env vars in individual test code — the `disable_auth` fixture is `autouse=True`.

- **MCP server entry point**: Always edit `booking_system_mcp/mcp_server.py`, not `booking_system_mcp/app.py` (legacy reference only).

- **Route metadata required**: Every FastAPI/MCP route must include `operation_id`, `summary`, and `description` kwargs. This is consumed by Watson Orchestrate and MCP Inspector.

- **Single-test run**: `python3 -m pytest tests/test_booking_system.py::TestClassName::test_method_name -v` from `booking_system_rest/`.
