#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/deploy.env}"

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command '${command_name}' is not installed."
    exit 1
  fi
}

require_command bash
require_command ibmcloud
require_command curl
require_command jq

if ! ibmcloud plugin show code-engine >/dev/null 2>&1; then
  echo "ERROR: the IBM Cloud Code Engine plugin is not available."
  echo "Install it with: ibmcloud plugin install code-engine"
  exit 1
fi

env_loaded="false"
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  env_loaded="true"
fi

ibm_cloud_api_key_resolved="${IBM_CLOUD_API_KEY:-${IBMCLOUD_API_KEY:-}}"
deploy_artifact_mode="$(printf '%s' "${DEPLOY_ARTIFACT_MODE:-source_build}" | tr '[:upper:]' '[:lower:]')"
container_client="$(printf '%s' "${CONTAINER_CLIENT:-docker}" | tr '[:upper:]' '[:lower:]')"

echo "Prerequisite check"
echo "=================="
echo
echo "Installed commands"
echo "------------------"
echo "bash:      $(command -v bash)"
echo "ibmcloud:  $(command -v ibmcloud)"
echo "curl:      $(command -v curl)"
echo "jq:        $(command -v jq)"
echo "plugin:    Code Engine available"
echo
echo "Installed CLI versions"
echo "----------------------"
ibmcloud version
echo
ibmcloud plugin show code-engine
echo

if [[ "${deploy_artifact_mode}" == "prebuilt_images" ]]; then
  if ! ibmcloud plugin show container-registry >/dev/null 2>&1; then
    echo "ERROR: the IBM Cloud Container Registry plugin is not available."
    echo "Install it with: ibmcloud plugin install container-registry"
    exit 1
  fi

  require_command "${container_client}"

  echo "Prebuilt image mode checks"
  echo "--------------------------"
  echo "container client: ${container_client} -> $(command -v "${container_client}")"
  ibmcloud plugin show container-registry
  echo
fi

if [[ "${env_loaded}" == "true" ]]; then
  echo "deploy.env"
  echo "----------"
  echo "Loaded: ${ENV_FILE}"
  echo "IBM_CLOUD_REGION: ${IBM_CLOUD_REGION:-<empty>}"
  echo "IBM_CLOUD_RESOURCE_GROUP: ${IBM_CLOUD_RESOURCE_GROUP:-<empty>}"
  echo "CE_PROJECT_NAME: ${CE_PROJECT_NAME:-<empty>}"
  echo "STACK_AUTH_MODE: ${STACK_AUTH_MODE:-<empty>}"
  echo "DEPLOY_ARTIFACT_MODE: ${deploy_artifact_mode:-<empty>}"
  if [[ "${deploy_artifact_mode}" == "prebuilt_images" ]]; then
    echo "ICR_REGION: ${ICR_REGION:-<empty>}"
    echo "ICR_REGISTRY: ${ICR_REGISTRY:-<empty>}"
    echo "ICR_NAMESPACE: ${ICR_NAMESPACE:-<empty>}"
    echo "IMAGE_TAG: ${IMAGE_TAG:-<empty>}"
  fi
  echo
else
  echo "deploy.env"
  echo "----------"
  echo "Not loaded because ${ENV_FILE} does not exist yet."
  echo "Copy deploy.env.template to deploy.env before running the deployment scripts."
  echo
fi

echo "IBM Cloud login path"
echo "--------------------"
if [[ -n "${ibm_cloud_api_key_resolved}" ]]; then
  echo "Non-interactive login is configured."
  echo "The deployment scripts will call: ibmcloud login --apikey <hidden> -r <region> -g <resource-group>"
else
  echo "No IBM Cloud API key is configured."
  if ibmcloud target >/dev/null 2>&1; then
    echo "An interactive ibmcloud session already exists."
  else
    echo "Run 'ibmcloud login' before scripts/01-project.sh, or set IBM_CLOUD_API_KEY in deploy.env."
  fi
fi
