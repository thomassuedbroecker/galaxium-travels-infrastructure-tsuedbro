#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_var KEYCLOAK_APP_NAME
require_var KEYCLOAK_REALM_CONFIGMAP_NAME
require_var KEYCLOAK_ADMIN_SECRET_NAME
require_var KEYCLOAK_CPU
require_var KEYCLOAK_MEMORY
require_var KEYCLOAK_MIN_SCALE
require_var KEYCLOAK_MAX_SCALE

select_project

args=(
  --image quay.io/keycloak/keycloak:26.0
  --port 8080
  --cpu "${KEYCLOAK_CPU}"
  --memory "${KEYCLOAK_MEMORY}"
  --min-scale "${KEYCLOAK_MIN_SCALE}"
  --max-scale "${KEYCLOAK_MAX_SCALE}"
  --visibility public
  --command kc.sh
  --argument start-dev
  --argument --http-port=8080
  --argument --import-realm
  --env KC_HTTP_ENABLED=true
  --env KC_PROXY_HEADERS=xforwarded
  --env KC_HOSTNAME_STRICT=false
  --env-from-secret "${KEYCLOAK_ADMIN_SECRET_NAME}"
  --mount-configmap "/opt/keycloak/data/import=${KEYCLOAK_REALM_CONFIGMAP_NAME}"
)

if [[ -n "${KEYCLOAK_DATA_STORE_NAME:-}" ]]; then
  args+=(--mount-data-store "/opt/keycloak/data=${KEYCLOAK_DATA_STORE_NAME}")
fi

ce_upsert_application "${KEYCLOAK_APP_NAME}" "${args[@]}"

keycloak_url="$(ce_app_url "${KEYCLOAK_APP_NAME}")"
echo "Keycloak URL: ${keycloak_url}"
