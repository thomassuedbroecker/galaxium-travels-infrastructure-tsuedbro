#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TESTING_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd -- "${TESTING_DIR}/.." && pwd)"
LOCAL_CONTAINER_DIR="${REPO_ROOT}/local-container"
COMPOSE_FILE="${LOCAL_CONTAINER_DIR}/docker_compose.yaml"
RESULTS_ROOT="${TESTING_DIR}/results"
GENERATED_RESULTS_DIR="${RESULTS_ROOT}/generated"

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed or not on PATH."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker is not running or not accessible."
    exit 1
  fi
}

cleanup_stack() {
  docker compose -f "${COMPOSE_FILE}" down >/dev/null 2>&1 || true
}

ensure_results_dir() {
  mkdir -p "${GENERATED_RESULTS_DIR}/rest"
  mkdir -p "${GENERATED_RESULTS_DIR}/ui"
  mkdir -p "${GENERATED_RESULTS_DIR}/mcp"
}
