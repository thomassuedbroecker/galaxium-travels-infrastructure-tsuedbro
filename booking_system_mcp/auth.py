import base64
import binascii
import os
import secrets
from typing import Any

import jwt
from fastapi import HTTPException, status
from jwt import InvalidTokenError, PyJWKClient


_jwks_client: PyJWKClient | None = None
_VALID_AUTH_MODES = {"none", "oauth2", "basic"}


def _as_bool(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on"}


def auth_mode() -> str:
    explicit_mode = (os.getenv("AUTH_MODE") or "").strip().lower()
    mode = explicit_mode or ("oauth2" if _as_bool(os.getenv("AUTH_ENABLED", "false")) else "none")
    if mode not in _VALID_AUTH_MODES:
        valid_modes = ", ".join(sorted(_VALID_AUTH_MODES))
        raise RuntimeError(f"Unsupported AUTH_MODE '{mode}'. Use one of: {valid_modes}")
    return mode


def auth_enabled() -> bool:
    return auth_mode() != "none"


def oauth2_auth_enabled() -> bool:
    return auth_mode() == "oauth2"


def basic_auth_enabled() -> bool:
    return auth_mode() == "basic"


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


def _basic_username() -> str:
    return (os.getenv("BASIC_AUTH_USERNAME") or "").strip()


def _basic_password() -> str:
    return os.getenv("BASIC_AUTH_PASSWORD") or ""


def _basic_realm() -> str:
    return (os.getenv("BASIC_AUTH_REALM") or "Galaxium Booking MCP").strip() or "Galaxium Booking MCP"


def _basic_challenge_headers() -> dict[str, str]:
    return {"WWW-Authenticate": f'Basic realm="{_basic_realm()}"'}


def validate_auth_configuration() -> None:
    mode = auth_mode()
    if mode == "none":
        return

    if mode == "oauth2":
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
        return

    missing = []
    if not _basic_username():
        missing.append("BASIC_AUTH_USERNAME")
    if _basic_password() == "":
        missing.append("BASIC_AUTH_PASSWORD")

    if missing:
        variables = ", ".join(missing)
        raise RuntimeError(
            f"Basic Auth is enabled but missing required configuration: {variables}"
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


def validate_access_token(token: str) -> dict[str, Any]:
    if not oauth2_auth_enabled():
        return {}
    return _decode_token(token)


def require_basic_auth_header(authorization_header: str | None) -> dict[str, Any]:
    if not basic_auth_enabled():
        return {}

    if not authorization_header:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing basic credentials",
            headers=_basic_challenge_headers(),
        )

    parts = authorization_header.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "basic" or not parts[1].strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing basic credentials",
            headers=_basic_challenge_headers(),
        )

    try:
        decoded = base64.b64decode(parts[1].strip(), validate=True).decode("utf-8")
    except (binascii.Error, UnicodeDecodeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid basic credentials",
            headers=_basic_challenge_headers(),
        ) from exc

    if ":" not in decoded:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid basic credentials",
            headers=_basic_challenge_headers(),
        )

    username, password = decoded.split(":", 1)
    username_ok = secrets.compare_digest(username, _basic_username())
    password_ok = secrets.compare_digest(password, _basic_password())
    if not username_ok or not password_ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid basic credentials",
            headers=_basic_challenge_headers(),
        )

    return {
        "sub": username,
        "auth_mode": "basic",
    }


def require_oauth2_header(authorization_header: str | None) -> dict[str, Any]:
    if not oauth2_auth_enabled():
        return {}

    if not authorization_header:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    parts = authorization_header.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = parts[1].strip()
    try:
        return validate_access_token(token)
    except InvalidTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid token: {str(exc)}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Token validation failed: {str(exc)}",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def require_authorization_header(authorization_header: str | None) -> dict[str, Any]:
    mode = auth_mode()
    if mode == "none":
        return {}
    if mode == "basic":
        return require_basic_auth_header(authorization_header)
    return require_oauth2_header(authorization_header)
