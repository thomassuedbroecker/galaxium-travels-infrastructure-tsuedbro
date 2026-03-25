#!/usr/bin/env bash
set -euo pipefail

# ************************
# Variable definition section
# ************************

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

steps=(
  00-prereqs.sh
  01-project.sh
  02-config-and-secrets.sh
  02b-build-and-push-images.sh
  03-deploy-keycloak.sh
  04-deploy-services.sh
  05-sync-keycloak-client.sh
  06-summary.sh
)

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

# ************************
# Execution section
# ************************

log_info "Running IBM Code Engine deployment steps from ${SCRIPTS_DIR}"

for step in "${steps[@]}"; do
  log_info "START ${step}"
  bash "${SCRIPTS_DIR}/${step}"
  log_info "DONE  ${step}"
done

log_info "IBM Code Engine deployment automation finished."
