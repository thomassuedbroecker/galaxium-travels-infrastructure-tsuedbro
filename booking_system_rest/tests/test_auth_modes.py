import base64

import pytest
from fastapi.testclient import TestClient

from app import app
from auth import validate_auth_configuration
from db import get_db


def _basic_auth_headers(username: str, password: str) -> dict[str, str]:
    encoded = base64.b64encode(f"{username}:{password}".encode("utf-8")).decode("ascii")
    return {"Authorization": f"Basic {encoded}"}


@pytest.fixture
def basic_client(db_session, monkeypatch):
    monkeypatch.setenv("AUTH_MODE", "basic")
    monkeypatch.setenv("BASIC_AUTH_USERNAME", "demo-basic-user")
    monkeypatch.setenv("BASIC_AUTH_PASSWORD", "demo-basic-password")

    def override_get_db():
        try:
            yield db_session
        finally:
            pass

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_validate_auth_configuration_requires_basic_credentials(monkeypatch):
    monkeypatch.setenv("AUTH_MODE", "basic")
    monkeypatch.delenv("BASIC_AUTH_USERNAME", raising=False)
    monkeypatch.delenv("BASIC_AUTH_PASSWORD", raising=False)

    with pytest.raises(RuntimeError, match="BASIC_AUTH_USERNAME, BASIC_AUTH_PASSWORD"):
        validate_auth_configuration()


def test_basic_auth_rejects_missing_credentials(basic_client):
    response = basic_client.get("/flights")

    assert response.status_code == 401
    assert response.json()["detail"] == "Missing basic credentials"
    assert response.headers["www-authenticate"] == 'Basic realm="Galaxium Booking API"'


def test_basic_auth_rejects_wrong_credentials(basic_client):
    response = basic_client.get("/flights", headers=_basic_auth_headers("demo-basic-user", "wrong"))

    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid basic credentials"


def test_basic_auth_allows_access_with_valid_credentials(basic_client):
    response = basic_client.get(
        "/flights",
        headers=_basic_auth_headers("demo-basic-user", "demo-basic-password"),
    )

    assert response.status_code == 200
    assert isinstance(response.json(), list)
