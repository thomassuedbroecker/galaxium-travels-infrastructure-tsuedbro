from __future__ import annotations

from .http_client import HttpClient
from .models import Variant


def fetch_client_credentials_token(client: HttpClient, variant: Variant) -> str:
    response = client.post_form(
        variant.keycloak_token_url,
        {
            "grant_type": "client_credentials",
            "client_id": variant.credentials.oidc_client_id,
            "client_secret": variant.credentials.oidc_client_secret,
            "scope": variant.credentials.oidc_scope,
        },
    )
    if response.status != 200:
        raise AssertionError(
            "client credentials token request failed for {variant}: {status} {body}".format(
                variant=variant.slug,
                status=response.status,
                body=response.text,
            )
        )
    payload = response.json()
    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise AssertionError(f"access_token missing in token response for {variant.slug}")
    return token


def fetch_password_token(client: HttpClient, variant: Variant) -> str:
    response = client.post_form(
        variant.keycloak_token_url,
        {
            "grant_type": "password",
            "client_id": variant.credentials.oidc_client_id,
            "client_secret": variant.credentials.oidc_client_secret,
            "username": variant.credentials.traveler_username,
            "password": variant.credentials.traveler_password,
            "scope": variant.credentials.oidc_scope,
        },
    )
    if response.status != 200:
        raise AssertionError(
            "password token request failed for {variant}: {status} {body}".format(
                variant=variant.slug,
                status=response.status,
                body=response.text,
            )
        )
    payload = response.json()
    token = payload.get("access_token")
    if not isinstance(token, str) or not token:
        raise AssertionError(f"access_token missing in token response for {variant.slug}")
    return token
