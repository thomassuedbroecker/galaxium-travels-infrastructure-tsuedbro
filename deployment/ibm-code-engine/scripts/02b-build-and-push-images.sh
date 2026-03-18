#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

require_command ibmcloud

if ! prebuilt_image_mode_enabled; then
  echo "Skipping local image build and push because DEPLOY_ARTIFACT_MODE=${DEPLOY_ARTIFACT_MODE}."
  echo "Use DEPLOY_ARTIFACT_MODE=prebuilt_images to enable the IBM Cloud Container Registry workflow."
  exit 0
fi

require_prebuilt_image_settings
ensure_icr_namespace
login_container_client_to_icr

build_and_push_service_image hr HR_database
build_and_push_service_image booking_api booking_system_rest
build_and_push_service_image mcp_api booking_system_mcp
build_and_push_service_image web_app galaxium-booking-web-app
build_and_push_service_image web_app_mcp galaxium-booking-web-app-mcp

cat <<EOF
Prebuilt image push summary
===========================

HR API:         $(image_ref_for_service hr)
Booking API:    $(image_ref_for_service booking_api)
MCP API:        $(image_ref_for_service mcp_api)
REST Web UI:    $(image_ref_for_service web_app)
MCP Web UI:     $(image_ref_for_service web_app_mcp)
EOF
