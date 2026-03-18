# Testing Guide for Enhanced Error Handling

This guide explains how to validate the current error-handling behavior across the active Galaxium services.

## Scope

This repository currently checks error behavior in three ways:

1. folder-local REST pytest coverage in `booking_system_rest/tests/`
2. compose-based OAuth and Basic Auth smoke checks in `local-container/`
3. manual spot checks for the small HR API

## REST API Validation

Run the REST suite from `booking_system_rest/`:

```sh
python3 -m pytest tests -q
```

The REST tests cover:

- booking validation and error payloads
- user lookup and duplicate-registration errors
- flight lookup and seat-availability errors
- database initialization behavior
- Basic Auth request rejection and acceptance paths

Manual REST checks with auth off:

```sh
cd booking_system_rest
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --reload --port 8082
```

Example error-path checks:

```sh
curl -X POST http://localhost:8082/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"demo-user@example.com"}'

curl -X POST http://localhost:8082/book \
  -H "Content-Type: application/json" \
  -d '{"user_id":999,"name":"Test User","flight_id":1}'

curl -X POST http://localhost:8082/cancel/999
```

## MCP Server Validation

The MCP server exposes the same business errors through MCP tools instead of REST endpoints.

Use the compose-based checks from `local-container/`:

```sh
bash verify-keycloak-auth-mcp.sh
python3 mcp_test_app.py
```

For the Basic Auth backend variant:

```sh
bash verify-basic-auth-backends.sh
```

Important:

- keep the public MCP endpoint on `http://localhost:8084/mcp`
- keep the transport on `Streamable HTTP`

## HR API Validation

Run the HR service from `HR_database/`:

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install pandas
python app.py
```

Manual HR error checks:

```sh
curl http://localhost:8081/employees/999
curl -X DELETE http://localhost:8081/employees/999
```

## Validation Checklist

- Error messages explain what went wrong
- Next steps are clearly suggested
- REST and MCP variants stay aligned on the business meaning of failures
- Basic Auth and OAuth enforcement still return the correct status codes
- Manual HR checks still show the more descriptive file and employee errors

## Related Docs

- REST testing details: [../TESTING.md](../TESTING.md)
- Repository-wide testing guide: [../../testing/README.md](../../testing/README.md)
- Local compose verification: [../../local-container/README.md](../../local-container/README.md)
