#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# shellcheck disable=SC1091
source "${SCRIPTS_DIR}/common.sh"

bash "${SCRIPTS_DIR}/00-prereqs.sh"
bash "${SCRIPTS_DIR}/01-project.sh"
bash "${SCRIPTS_DIR}/02-config-and-secrets.sh"

if prebuilt_image_mode_enabled; then
  bash "${SCRIPTS_DIR}/02b-build-and-push-images.sh"
fi

if should_deploy_keycloak; then
  bash "${SCRIPTS_DIR}/03-deploy-keycloak.sh"
fi

bash "${SCRIPTS_DIR}/04-deploy-services.sh"

if [[ "${STACK_AUTH_MODE}" == "oauth2" ]]; then
  bash "${SCRIPTS_DIR}/05-sync-keycloak-client.sh"
fi

bash "${SCRIPTS_DIR}/06-summary.sh"
