#!/usr/bin/env bash
set -euo pipefail

# ************************
# Variable definition section
# ************************

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Force oauth2 mode regardless of what the env file says.
# This orchestrator is the dedicated oauth2 deployment path.
export STACK_AUTH_MODE=oauth2

# Allow the caller to override the env file location.
# Default: deploy.env.oauth2 next to this script, falling back to deploy.env.
if [[ -z "${ENV_FILE:-}" ]]; then
  if [[ -f "${SCRIPT_DIR}/deploy.env.oauth2" ]]; then
    export ENV_FILE="${SCRIPT_DIR}/deploy.env.oauth2"
  else
    export ENV_FILE="${SCRIPT_DIR}/deploy.env"
  fi
fi

# Steps for the oauth2-specific deployment path.
# 02b is included because it self-skips when DEPLOY_ARTIFACT_MODE=source_build.
# 03 (Keycloak) and 05 (Keycloak client sync) are required for oauth2.
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
# Pre-flight checks
# ************************

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: environment file not found: ${ENV_FILE}"
  echo ""
  echo "Prepare it with one of:"
  echo "  cp ${SCRIPT_DIR}/deploy.env.oauth2.template ${SCRIPT_DIR}/deploy.env.oauth2"
  echo "  cp ${SCRIPT_DIR}/deploy.env.template        ${SCRIPT_DIR}/deploy.env"
  echo ""
  echo "Then fill in the required values and re-run."
  exit 1
fi

log_info "Using environment file: ${ENV_FILE}"
log_info "Stack auth mode locked to: ${STACK_AUTH_MODE}"

# ************************
# Execution section
# ************************

log_info "Running IBM Code Engine oauth2 deployment steps from ${SCRIPTS_DIR}"

for step in "${steps[@]}"; do
  log_info "START ${step}"
  bash "${SCRIPTS_DIR}/${step}"
  log_info "DONE  ${step}"
done

log_info "IBM Code Engine oauth2 deployment automation finished."
