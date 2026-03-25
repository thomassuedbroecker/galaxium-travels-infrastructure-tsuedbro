#!/usr/bin/env bash
set -euo pipefail

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

for step in "${steps[@]}"; do
  echo "==> ${step}"
  bash "${SCRIPTS_DIR}/${step}"
done
