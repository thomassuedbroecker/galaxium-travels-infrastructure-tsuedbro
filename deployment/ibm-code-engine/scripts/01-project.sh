#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud
require_var IBM_CLOUD_REGION
require_var IBM_CLOUD_RESOURCE_GROUP
require_var CE_PROJECT_NAME

target_args=("-r" "${IBM_CLOUD_REGION}" "-g" "${IBM_CLOUD_RESOURCE_GROUP}")
select_args=("--name" "${CE_PROJECT_NAME}")
create_args=("--name" "${CE_PROJECT_NAME}")

if [[ -n "${CE_ENDPOINT:-}" ]]; then
  select_args+=("--endpoint" "${CE_ENDPOINT}")
fi

if [[ -n "${CE_PROJECT_TAG:-}" ]]; then
  create_args+=("--tag" "${CE_PROJECT_TAG}")
fi

ibmcloud target "${target_args[@]}"

if ! ibmcloud ce project select "${select_args[@]}" >/dev/null 2>&1; then
  ibmcloud ce project create "${create_args[@]}"
fi

ibmcloud ce project select "${select_args[@]}"
echo "Active Code Engine project: ${CE_PROJECT_NAME}"
