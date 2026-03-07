# Galaxium HR API

Small FastAPI service backed by `data/employees.md`.

## Run Locally

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install pandas
python app.py
```

Docs: `http://localhost:8081/docs`

## Endpoints

- `GET /employees`
- `GET /employees/{employee_id}`
- `POST /employees`
- `PUT /employees/{employee_id}`
- `DELETE /employees/{employee_id}`

## Notes

- Data is stored directly in `data/employees.md`.
- This service is intentionally simple and demo-oriented.
- Error responses are written to be readable by people and agents.

## Related Docs

- Repository quickstart: [../QUICKSTART.md](../QUICKSTART.md)
- Shared error-handling notes: [../booking_system_rest/docs/error-handling-guide.md](../booking_system_rest/docs/error-handling-guide.md)
