#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_var CE_PROJECT_NAME
require_var KEYCLOAK_REALM_CONFIGMAP_NAME
require_var KEYCLOAK_ADMIN_SECRET_NAME
require_var WEB_APP_SECRET_NAME
require_var KEYCLOAK_ADMIN_USER
require_var KEYCLOAK_ADMIN_PASSWORD
require_var OIDC_CLIENT_SECRET
require_var FLASK_SECRET_KEY

select_project

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

ce_upsert_secret \
  "${WEB_APP_SECRET_NAME}" \
  --from-literal "OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}" \
  --from-literal "FLASK_SECRET_KEY=${FLASK_SECRET_KEY}"

echo "Updated configmap: ${KEYCLOAK_REALM_CONFIGMAP_NAME}"
echo "Updated secret: ${KEYCLOAK_ADMIN_SECRET_NAME}"
echo "Updated secret: ${WEB_APP_SECRET_NAME}"
