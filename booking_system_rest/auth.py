import os
from typing import Any

import jwt
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import InvalidTokenError, PyJWKClient


http_bearer = HTTPBearer(auto_error=False)
_jwks_client: PyJWKClient | None = None


def _as_bool(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def auth_enabled() -> bool:
    return _as_bool(os.getenv("AUTH_ENABLED", "false"))


def _issuer() -> str:
    return (os.getenv("OIDC_ISSUER") or "").strip()


def _audience() -> str:
    return (os.getenv("OIDC_AUDIENCE") or "").strip()


def _jwks_url() -> str:
    explicit = (os.getenv("OIDC_JWKS_URL") or "").strip()
    if explicit:
        return explicit
    issuer = _issuer()
    if not issuer:
        return ""
    return f"{issuer}/protocol/openid-connect/certs"


def validate_auth_configuration() -> None:
    if not auth_enabled():
        return

    missing = []
    if not _issuer():
        missing.append("OIDC_ISSUER")
    if not _jwks_url():
        missing.append("OIDC_JWKS_URL")

    if missing:
        variables = ", ".join(missing)
        raise RuntimeError(
            f"OAuth2/OIDC is enabled but missing required configuration: {variables}"
        )


def _get_jwks_client() -> PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        _jwks_client = PyJWKClient(_jwks_url())
    return _jwks_client


def _decode_token(token: str) -> dict[str, Any]:
    signing_key = _get_jwks_client().get_signing_key_from_jwt(token)
    audience = _audience()
    decode_kwargs: dict[str, Any] = {
        "key": signing_key.key,
        "algorithms": ["RS256"],
        "issuer": _issuer(),
    }
    if audience:
        decode_kwargs["audience"] = audience
    else:
        decode_kwargs["options"] = {"verify_aud": False}
    return jwt.decode(token, **decode_kwargs)


def require_oauth2_token(
    credentials: HTTPAuthorizationCredentials | None = Security(http_bearer),
) -> dict[str, Any]:
    if not auth_enabled():
        return {}

    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    token = credentials.credentials
    try:
        return _decode_token(token)
    except InvalidTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(exc)}",
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token validation failed: {str(exc)}",
        ) from exc
