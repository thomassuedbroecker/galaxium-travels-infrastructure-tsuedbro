from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


def _bool_text(value: bool) -> str:
    return "true" if value else "false"


@dataclass(frozen=True)
class Credentials:
    traveler_username: str
    traveler_password: str
    oidc_client_id: str
    oidc_client_secret: str
    oidc_scope: str


@dataclass(frozen=True)
class EnvironmentProfile:
    id: str
    label: str
    description: str
    public_host_default: str
    uses_vm_oauth_override: bool
    public_host_env: str


@dataclass(frozen=True)
class BackendProfile:
    id: str
    label: str
    frontend_service: str
    backend_service: str
    frontend_port: int
    backend_port: int
    frontend_login_path: str
    frontend_health_path: str
    backend_health_path: str
    backend_flights_path: str
    mcp_endpoint_path: str = "/mcp"
    mcp_openid_configuration_path: str = "/.well-known/openid-configuration"
    mcp_authorization_server_path: str = "/.well-known/oauth-authorization-server"
    mcp_protected_resource_path: str = "/.well-known/oauth-protected-resource"


@dataclass(frozen=True)
class OAuthProfile:
    id: str
    label: str
    backend_auth_enabled: bool
    frontend_oauth_enabled: bool
    frontend_auth_required: bool


@dataclass(frozen=True)
class Variant:
    environment: EnvironmentProfile
    backend: BackendProfile
    oauth: OAuthProfile
    credentials: Credentials
    public_host: str
    repo_root: Path

    @property
    def slug(self) -> str:
        return f"{self.environment.id}-{self.backend.id}-{self.oauth.id}"

    @property
    def compose_services(self) -> tuple[str, ...]:
        return ("keycloak", self.backend.backend_service, self.backend.frontend_service)

    @property
    def keycloak_base_url(self) -> str:
        return f"http://{self.public_host}:8080"

    @property
    def keycloak_realm_url(self) -> str:
        return f"{self.keycloak_base_url}/realms/galaxium"

    @property
    def keycloak_openid_configuration_url(self) -> str:
        return f"{self.keycloak_realm_url}/.well-known/openid-configuration"

    @property
    def keycloak_token_url(self) -> str:
        return f"{self.keycloak_realm_url}/protocol/openid-connect/token"

    @property
    def frontend_base_url(self) -> str:
        return f"http://{self.public_host}:{self.backend.frontend_port}"

    @property
    def frontend_login_url(self) -> str:
        return f"{self.frontend_base_url}{self.backend.frontend_login_path}"

    @property
    def frontend_health_url(self) -> str:
        return f"{self.frontend_base_url}{self.backend.frontend_health_path}"

    @property
    def frontend_flights_url(self) -> str:
        return f"{self.frontend_base_url}/api/flights"

    @property
    def frontend_traveler_url(self) -> str:
        return f"{self.frontend_base_url}/api/traveler"

    @property
    def frontend_bookings_url(self) -> str:
        return f"{self.frontend_base_url}/api/bookings"

    @property
    def frontend_book_url(self) -> str:
        return f"{self.frontend_base_url}/api/book"

    @property
    def backend_base_url(self) -> str:
        return f"http://{self.public_host}:{self.backend.backend_port}"

    @property
    def backend_health_url(self) -> str:
        return f"{self.backend_base_url}{self.backend.backend_health_path}"

    @property
    def backend_flights_url(self) -> str:
        return f"{self.backend_base_url}{self.backend.backend_flights_path}"

    @property
    def mcp_endpoint_url(self) -> str:
        return f"{self.backend_base_url}{self.backend.mcp_endpoint_path}"

    @property
    def mcp_openid_configuration_url(self) -> str:
        return f"{self.backend_base_url}{self.backend.mcp_openid_configuration_path}"

    @property
    def mcp_authorization_server_url(self) -> str:
        return f"{self.backend_base_url}{self.backend.mcp_authorization_server_path}"

    @property
    def mcp_protected_resource_url(self) -> str:
        return f"{self.backend_base_url}{self.backend.mcp_protected_resource_path}"

    @property
    def compose_files(self) -> tuple[Path, ...]:
        files = [self.repo_root / "local-container" / "docker_compose.yaml"]
        if self.environment.uses_vm_oauth_override:
            files.append(self.repo_root / "local-container" / "docker_compose.vm-oauth.yaml")
        files.append(self.repo_root / "testing" / "webui_matrix" / "docker_compose.auth-matrix.yaml")
        return tuple(files)

    @property
    def expected_frontend_label(self) -> str:
        return "REST API" if self.backend.id == "rest" else "MCP"

    @property
    def expected_frontend_summary(self) -> str:
        if self.backend.id == "rest":
            return "This frontend proxies booking requests to the REST backend."
        return "This frontend executes booking actions through MCP tool calls."

    @property
    def expected_integration_mode(self) -> str:
        if self.backend.id == "rest":
            return "rest_api_proxy"
        return "direct_python_mcp_client"

    @property
    def expected_proxy_to(self) -> str:
        if self.backend.id == "rest":
            return "http://booking_system:8082"
        return "http://booking_system_mcp:8084/mcp"

    @property
    def compose_env(self) -> dict[str, str]:
        backend_issuer = self.keycloak_realm_url if self.environment.uses_vm_oauth_override else "http://keycloak:8080/realms/galaxium"
        backend_jwks_url = "http://keycloak:8080/realms/galaxium/protocol/openid-connect/certs"
        auth_server_url = self.keycloak_realm_url if self.environment.uses_vm_oauth_override else "http://localhost:8080/realms/galaxium"
        rest_ui_token_url = self.keycloak_token_url if self.environment.uses_vm_oauth_override else "http://keycloak:8080/realms/galaxium/protocol/openid-connect/token"
        mcp_ui_token_url = self.keycloak_token_url if self.environment.uses_vm_oauth_override else "http://keycloak:8080/realms/galaxium/protocol/openid-connect/token"

        env = {
            "REST_BACKEND_AUTH_ENABLED": _bool_text(self.oauth.backend_auth_enabled),
            "MCP_BACKEND_AUTH_ENABLED": _bool_text(self.oauth.backend_auth_enabled),
            "REST_BACKEND_OIDC_ISSUER": backend_issuer,
            "REST_BACKEND_OIDC_JWKS_URL": backend_jwks_url,
            "MCP_BACKEND_OIDC_ISSUER": backend_issuer,
            "MCP_BACKEND_OIDC_JWKS_URL": backend_jwks_url,
            "MCP_AUTHORIZATION_SERVER_URL": auth_server_url,
            "REST_UI_OAUTH_ENABLED": _bool_text(self.oauth.frontend_oauth_enabled),
            "REST_UI_AUTH_REQUIRED": _bool_text(self.oauth.frontend_auth_required),
            "REST_UI_OIDC_TOKEN_URL": rest_ui_token_url,
            "REST_UI_OIDC_SCOPE": self.credentials.oidc_scope,
            "MCP_UI_OAUTH_ENABLED": "true",
            "MCP_UI_AUTH_REQUIRED": "true",
            "MCP_UI_OIDC_TOKEN_URL": mcp_ui_token_url,
            "MCP_UI_OIDC_SCOPE": self.credentials.oidc_scope,
        }

        if self.environment.uses_vm_oauth_override:
            env.update(
                {
                    "KEYCLOAK_PUBLIC_BASE_URL": self.keycloak_base_url,
                    "MCP_PUBLIC_BASE_URL": "http://{host}:8084".format(host=self.public_host),
                }
            )

        return env
