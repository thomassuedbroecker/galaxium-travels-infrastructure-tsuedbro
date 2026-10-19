#!/usr/bin/env bash
set -euo pipefail

# ************************
# Variable definition section
# ************************
#
# Deletes ALL applications, configmaps, and secrets inside the Code Engine
# project.  The project itself is intentionally NOT deleted — removing a
# Code Engine project name puts it into a reclamation hold for several days,
# making the name unavailable for re-deployment.
#
# Usage:
#   bash teardown-stack-oauth2.sh
#   ENV_FILE=/path/to/my.env bash teardown-stack-oauth2.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${ENV_FILE:-}" ]]; then
  if [[ -f "${SCRIPT_DIR}/deploy.env.oauth2" ]]; then
    export ENV_FILE="${SCRIPT_DIR}/deploy.env.oauth2"
  else
    export ENV_FILE="${SCRIPT_DIR}/deploy.env"
  fi
fi

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
  echo "Prepare it with:"
  echo "  cp ${SCRIPT_DIR}/deploy.env.oauth2.template ${SCRIPT_DIR}/deploy.env.oauth2"
  exit 1
fi

log_info "Using environment file: ${ENV_FILE}"

# shellcheck disable=SC1090
source "${ENV_FILE}"

IBM_CLOUD_API_KEY_RESOLVED="${IBM_CLOUD_API_KEY:-${IBMCLOUD_API_KEY:-}}"

require_var() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: required variable '${var}' is empty in ${ENV_FILE}."
    exit 1
  fi
}

require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME

# ************************
# Execution section
# ************************

log_info "Starting teardown inside Code Engine project: ${CE_PROJECT_NAME}"
log_info "The project itself will NOT be deleted."

# ── Login ──────────────────────────────────────────────────────────────────
if ! ibmcloud target >/dev/null 2>&1; then
  if [[ -n "${IBM_CLOUD_API_KEY_RESOLVED}" ]]; then
    log_info "Logging in to IBM Cloud (region=${IBM_CLOUD_REGION}, rg=${IBM_CLOUD_RESOURCE_GROUP})"
    ibmcloud login \
      --apikey "${IBM_CLOUD_API_KEY_RESOLVED}" \
      -r "${IBM_CLOUD_REGION}" \
      -g "${IBM_CLOUD_RESOURCE_GROUP}" \
      -q
  else
    echo "ERROR: run 'ibmcloud login' or set IBM_CLOUD_API_KEY."
    exit 1
  fi
fi

# Check project exists
if ! ibmcloud ce project get --name "${CE_PROJECT_NAME}" >/dev/null 2>&1; then
  log_info "Project '${CE_PROJECT_NAME}' does not exist — nothing to clean."
  exit 0
fi

ibmcloud target -r "${IBM_CLOUD_REGION}" -g "${IBM_CLOUD_RESOURCE_GROUP}" -q
ibmcloud ce project select --name "${CE_PROJECT_NAME}" -q

# ── Applications ───────────────────────────────────────────────────────────
log_info "=== Phase 1: Delete all applications ==="
app_names=$(ibmcloud ce app list --output json 2>/dev/null \
  | python3 -c "import sys,json; [print(a['metadata']['name']) for a in json.load(sys.stdin).get('items',[])]" 2>/dev/null || true)

if [[ -z "${app_names}" ]]; then
  log_info "No applications found."
else
  while IFS= read -r name; do
    log_info "Deleting application: ${name}"
    ibmcloud ce app delete --name "${name}" --force -q
    log_info "Deleted  application: ${name}"
  done <<< "${app_names}"
fi

# ── Configmaps ─────────────────────────────────────────────────────────────
log_info "=== Phase 2: Delete all configmaps ==="
cm_names=$(ibmcloud ce configmap list --output json 2>/dev/null \
  | python3 -c "import sys,json; [print(c['metadata']['name']) for c in json.load(sys.stdin).get('items',[])]" 2>/dev/null || true)

if [[ -z "${cm_names}" ]]; then
  log_info "No configmaps found."
else
  while IFS= read -r name; do
    log_info "Deleting configmap: ${name}"
    ibmcloud ce configmap delete --name "${name}" --force -q
    log_info "Deleted  configmap: ${name}"
  done <<< "${cm_names}"
fi

# ── Secrets ────────────────────────────────────────────────────────────────
log_info "=== Phase 3: Delete all secrets ==="
secret_names=$(ibmcloud ce secret list --output json 2>/dev/null \
  | python3 -c "import sys,json; [print(s['metadata']['name']) for s in json.load(sys.stdin).get('items',[])]" 2>/dev/null || true)

if [[ -z "${secret_names}" ]]; then
  log_info "No secrets found."
else
  while IFS= read -r name; do
    log_info "Deleting secret: ${name}"
    ibmcloud ce secret delete --name "${name}" --force -q
    log_info "Deleted  secret: ${name}"
  done <<< "${secret_names}"
fi

log_info "Teardown complete. Project '${CE_PROJECT_NAME}' is empty and ready for re-deployment."
