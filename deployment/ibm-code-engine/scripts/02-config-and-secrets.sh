#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_var CE_PROJECT_NAME
require_var WEB_APP_SECRET_NAME
require_var FLASK_SECRET_KEY

if prebuilt_image_mode_enabled; then
  require_prebuilt_image_settings
fi

select_project

if should_deploy_keycloak; then
  require_var KEYCLOAK_REALM_CONFIGMAP_NAME
  require_var KEYCLOAK_ADMIN_SECRET_NAME
  require_var KEYCLOAK_ADMIN_USER
  require_var KEYCLOAK_ADMIN_PASSWORD

  realm_file="${REPO_ROOT}/local-container/keycloak/realm/galaxium-realm.json"
  if [[ ! -f "${realm_file}" ]]; then
    echo "ERROR: Keycloak realm file not found at ${realm_file}"
    exit 1
  fi

  ce_upsert_configmap \
    "${KEYCLOAK_REALM_CONFIGMAP_NAME}" \
    --from-file "galaxium-realm.json=${realm_file}"

  ce_upsert_secret \
    "${KEYCLOAK_ADMIN_SECRET_NAME}" \
    --from-literal "KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN_USER}" \
    --from-literal "KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}"

  echo "Updated configmap: ${KEYCLOAK_REALM_CONFIGMAP_NAME}"
  echo "Updated secret: ${KEYCLOAK_ADMIN_SECRET_NAME}"
else
  echo "Skipping in-project Keycloak config because STACK_AUTH_MODE=${STACK_AUTH_MODE} or KEYCLOAK_BASE_URL_OVERRIDE is set."
fi

ui_secret_args=(
  --from-literal "FLASK_SECRET_KEY=${FLASK_SECRET_KEY}"
)
if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  require_var OIDC_CLIENT_SECRET
  ui_secret_args+=(
    --from-literal "OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}"
  )
fi

ce_upsert_secret \
  "${WEB_APP_SECRET_NAME}" \
  "${ui_secret_args[@]}"

echo "Updated secret: ${WEB_APP_SECRET_NAME}"

if [[ "${STACK_AUTH_MODE}" == "basic" ]]; then
  require_var BASIC_AUTH_SECRET_NAME
  require_var BASIC_AUTH_USERNAME
  require_var BASIC_AUTH_PASSWORD

  ce_upsert_secret \
    "${BASIC_AUTH_SECRET_NAME}" \
    --from-literal "BASIC_AUTH_USERNAME=${BASIC_AUTH_USERNAME}" \
    --from-literal "BASIC_AUTH_PASSWORD=${BASIC_AUTH_PASSWORD}"

  echo "Updated secret: ${BASIC_AUTH_SECRET_NAME}"
fi

if prebuilt_image_mode_enabled; then
  ensure_icr_namespace

  ce_upsert_secret \
    "${ICR_REGISTRY_SECRET_NAME}" \
    --format registry \
    --server "${ICR_REGISTRY}" \
    --username "${ICR_REGISTRY_USERNAME_RESOLVED}" \
    --password "${ICR_REGISTRY_PASSWORD_RESOLVED}"

  echo "Updated registry secret: ${ICR_REGISTRY_SECRET_NAME}"
fi
