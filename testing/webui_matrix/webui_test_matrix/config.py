from __future__ import annotations

import json
import os
from itertools import product
from pathlib import Path

from .models import BackendProfile, Credentials, EnvironmentProfile, OAuthProfile, Variant


class ConfigurationError(ValueError):
    """Raised when a requested test matrix variant is incomplete or invalid."""


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def matrix_file() -> Path:
    return repo_root() / "testing" / "webui_matrix" / "matrix.json"


def load_matrix() -> dict[str, object]:
    with matrix_file().open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _ordered_keys(section_name: str) -> list[str]:
    matrix = load_matrix()
    section = matrix.get(section_name)
    if not isinstance(section, dict):
        raise ConfigurationError(f"matrix section '{section_name}' is missing or invalid")
    return list(section.keys())


def _build_credentials(matrix: dict[str, object]) -> Credentials:
    payload = matrix.get("credentials")
    if not isinstance(payload, dict):
        raise ConfigurationError("matrix credentials are missing")
    return Credentials(
        traveler_username=str(payload["traveler_username"]),
        traveler_password=str(payload["traveler_password"]),
        oidc_client_id=str(payload["oidc_client_id"]),
        oidc_client_secret=str(payload["oidc_client_secret"]),
        oidc_scope=str(payload["oidc_scope"]),
    )


def _build_environment(matrix: dict[str, object], environment_id: str) -> EnvironmentProfile:
    payload = matrix.get("environments", {}).get(environment_id)
    if not isinstance(payload, dict):
        raise ConfigurationError(f"unknown environment '{environment_id}'")
    return EnvironmentProfile(
        id=environment_id,
        label=str(payload["label"]),
        description=str(payload["description"]),
        public_host_default=str(payload.get("public_host_default", "")),
        uses_vm_oauth_override=bool(payload.get("uses_vm_oauth_override", False)),
        public_host_env=str(payload.get("public_host_env", "")),
    )


def _build_backend(matrix: dict[str, object], backend_id: str) -> BackendProfile:
    payload = matrix.get("backends", {}).get(backend_id)
    if not isinstance(payload, dict):
        raise ConfigurationError(f"unknown backend '{backend_id}'")
    return BackendProfile(
        id=backend_id,
        label=str(payload["label"]),
        frontend_service=str(payload["frontend_service"]),
        backend_service=str(payload["backend_service"]),
        frontend_port=int(payload["frontend_port"]),
        backend_port=int(payload["backend_port"]),
        frontend_login_path=str(payload["frontend_login_path"]),
        frontend_health_path=str(payload["frontend_health_path"]),
        backend_health_path=str(payload["backend_health_path"]),
        backend_flights_path=str(payload["backend_flights_path"]),
        mcp_endpoint_path=str(payload.get("mcp_endpoint_path", "/mcp")),
        mcp_openid_configuration_path=str(
            payload.get("mcp_openid_configuration_path", "/.well-known/openid-configuration")
        ),
        mcp_authorization_server_path=str(
            payload.get("mcp_authorization_server_path", "/.well-known/oauth-authorization-server")
        ),
        mcp_protected_resource_path=str(
            payload.get("mcp_protected_resource_path", "/.well-known/oauth-protected-resource")
        ),
    )


def _build_oauth(matrix: dict[str, object], oauth_id: str) -> OAuthProfile:
    payload = matrix.get("oauth_modes", {}).get(oauth_id)
    if not isinstance(payload, dict):
        raise ConfigurationError(f"unknown oauth mode '{oauth_id}'")
    return OAuthProfile(
        id=oauth_id,
        label=str(payload["label"]),
        backend_auth_enabled=bool(payload["backend_auth_enabled"]),
        frontend_oauth_enabled=bool(payload["frontend_oauth_enabled"]),
        frontend_auth_required=bool(payload["frontend_auth_required"]),
    )


def _resolve_public_host(environment: EnvironmentProfile, explicit_public_host: str | None) -> str:
    candidate = (explicit_public_host or "").strip()
    if candidate:
        return candidate

    if environment.public_host_env:
        env_value = (os.getenv(environment.public_host_env) or "").strip()
        if env_value:
            return env_value
        if environment.uses_vm_oauth_override:
            raise ConfigurationError(
                "{name} requires {env_name} so the stack can advertise LAN-reachable issuer URLs".format(
                    name=environment.label,
                    env_name=environment.public_host_env,
                )
            )

    if environment.public_host_default:
        return environment.public_host_default

    raise ConfigurationError(
        "No public host is configured for environment '{environment_id}'".format(
            environment_id=environment.id
        )
    )


def build_variant(
    environment_id: str,
    backend_id: str,
    oauth_id: str,
    public_host: str | None = None,
) -> Variant:
    matrix = load_matrix()
    environment = _build_environment(matrix, environment_id)
    backend = _build_backend(matrix, backend_id)
    oauth = _build_oauth(matrix, oauth_id)
    credentials = _build_credentials(matrix)

    return Variant(
        environment=environment,
        backend=backend,
        oauth=oauth,
        credentials=credentials,
        public_host=_resolve_public_host(environment, public_host),
        repo_root=repo_root(),
    )


def all_variants(public_host: str | None = None) -> list[Variant]:
    environment_ids = _ordered_keys("environments")
    backend_ids = _ordered_keys("backends")
    oauth_ids = _ordered_keys("oauth_modes")
    return [
        build_variant(environment_id, backend_id, oauth_id, public_host=public_host)
        for environment_id, backend_id, oauth_id in product(environment_ids, backend_ids, oauth_ids)
    ]


def _selected_dimension(env_name: str, default: str, ordered_keys: list[str]) -> list[str]:
    raw_value = (os.getenv(env_name) or default).strip()
    if not raw_value:
        raw_value = default
    if raw_value == "all":
        return ordered_keys
    if raw_value not in ordered_keys:
        raise ConfigurationError(
            "{name} must be one of {values} or 'all'; got '{actual}'".format(
                name=env_name,
                values=", ".join(ordered_keys),
                actual=raw_value,
            )
        )
    return [raw_value]


def build_selected_variants_from_env() -> list[Variant]:
    if _as_bool(os.getenv("WEBUI_TEST_RUN_FULL_MATRIX"), default=False):
        return all_variants()

    environment_ids = _ordered_keys("environments")
    backend_ids = _ordered_keys("backends")
    oauth_ids = _ordered_keys("oauth_modes")

    selected_environment_ids = _selected_dimension(
        "WEBUI_TEST_ENVIRONMENT",
        "local_machine_network",
        environment_ids,
    )
    selected_backend_ids = _selected_dimension(
        "WEBUI_TEST_BACKEND_MODE",
        "rest",
        backend_ids,
    )
    selected_oauth_ids = _selected_dimension(
        "WEBUI_TEST_OAUTH_MODE",
        "backend_and_ui_oauth",
        oauth_ids,
    )

    return [
        build_variant(environment_id, backend_id, oauth_id)
        for environment_id, backend_id, oauth_id in product(
            selected_environment_ids,
            selected_backend_ids,
            selected_oauth_ids,
        )
    ]
