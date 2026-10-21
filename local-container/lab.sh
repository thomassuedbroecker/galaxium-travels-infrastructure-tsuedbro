#!/usr/bin/env bash
# lab.sh: one entry point for the local labs L01-L08 described in ../LABS.md.
# It only wraps the existing compose files and scripts; it does not change any configuration.
#
#   bash local-container/lab.sh list
#   bash local-container/lab.sh up|down|verify <lab>    # <lab>: 01-08 or 04-vm (L prefix optional)
#   bash local-container/lab.sh status
#   bash local-container/lab.sh down-all
#
# L08 uses the Python HR backend; set HR_BACKEND=java for the Java backend.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HR_DIR="$(cd -- "${SCRIPT_DIR}/../hr_database_frontend_java" && pwd)"
LABS="01 02 03 04 04-vm 05 06 07 08"

BASIC_ENV_ARGS=()
if [[ -f "${SCRIPT_DIR}/basic-auth.env" ]]; then
  BASIC_ENV_ARGS=(--env-file "${SCRIPT_DIR}/basic-auth.env")
fi

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

lab_title() {
  case "$1" in
    01) echo "MCP server, no auth" ;;
    02) echo "MCP server, Basic Auth" ;;
    03) echo "MCP server, OAuth 2.0 (no implicit flow)" ;;
    04) echo "Full stack, Basic Auth (QUICKSTART Option 3)" ;;
    04-vm) echo "Full stack, Basic Auth, VM/LAN-flavored compose file" ;;
    05) echo "Full stack, Keycloak OAuth (QUICKSTART Option 1)" ;;
    06) echo "Keycloak UI + MCP Basic Auth (QUICKSTART Option 4)" ;;
    07) echo "Host + VM/LAN OAuth (QUICKSTART Option 2)" ;;
    08) echo "HR stack (HR_BACKEND=${HR_BACKEND:-python})" ;;
    *) return 1 ;;
  esac
}

normalize_lab() {
  local lab="${1#[Ll]}"
  lab_title "${lab}" >/dev/null || { echo "ERROR: unknown lab '$1'. Run: $0 list" >&2; exit 1; }
  echo "${lab}"
}

mcp_only_dir() {
  case "$1" in
    01) echo "${SCRIPT_DIR}/booking_system_mcp_no_auth" ;;
    02) echo "${SCRIPT_DIR}/booking_system_mcp_basic_auth" ;;
    03) echo "${SCRIPT_DIR}/booking_system_mcp_oauth2_no_implicit_flow" ;;
  esac
}

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "ERROR: $1 not found. Create it from $(basename "$1").template first (see LABS.md)." >&2
    exit 1
  fi
}

# lab_compose LAB ARGS...: docker compose with the files and env file of LAB (L01-L07).
lab_compose() {
  local lab="$1"
  shift
  local dir
  case "${lab}" in
    01|02|03)
      dir="$(mcp_only_dir "${lab}")"
      if [[ -f "${dir}/mcp.env" ]]; then
        docker compose --env-file "${dir}/mcp.env" -f "${dir}/docker_compose.yaml" "$@"
      else
        docker compose -f "${dir}/docker_compose.yaml" "$@"
      fi
      ;;
    04)
      docker compose ${BASIC_ENV_ARGS[@]+"${BASIC_ENV_ARGS[@]}"} \
        -f "${SCRIPT_DIR}/docker_compose.basic-auth.yaml" "$@"
      ;;
    04-vm)
      docker compose ${BASIC_ENV_ARGS[@]+"${BASIC_ENV_ARGS[@]}"} \
        -f "${SCRIPT_DIR}/docker_compose.basic-auth-vm.yaml" "$@"
      ;;
    05)
      docker compose -f "${SCRIPT_DIR}/docker_compose.yaml" "$@"
      ;;
    06)
      docker compose ${BASIC_ENV_ARGS[@]+"${BASIC_ENV_ARGS[@]}"} \
        -f "${SCRIPT_DIR}/docker_compose.yaml" \
        -f "${SCRIPT_DIR}/docker_compose.mcp-ui-keycloak-basic.yaml" "$@"
      ;;
    07)
      local env_args=()
      if [[ -f "${SCRIPT_DIR}/vm-oauth.env" ]]; then
        env_args=(--env-file "${SCRIPT_DIR}/vm-oauth.env")
      fi
      docker compose ${env_args[@]+"${env_args[@]}"} \
        -f "${SCRIPT_DIR}/docker_compose.yaml" \
        -f "${SCRIPT_DIR}/docker_compose.vm-oauth.yaml" "$@"
      ;;
  esac
}

hr_backend() {
  if [[ -n "${HR_BACKEND:-}" ]]; then
    echo "${HR_BACKEND}"
  elif docker ps --format '{{.Names}}' | grep -qx 'hr_database_backend_java'; then
    echo "java"
  else
    echo "python"
  fi
}

cmd_up() {
  local lab="$1"
  echo "Starting L${lab}: $(lab_title "${lab}")"
  case "${lab}" in
    01|02|03) bash "$(mcp_only_dir "${lab}")/start.sh" ;;
    04|04-vm|05) lab_compose "${lab}" up --build -d ;;
    06) lab_compose "${lab}" up --build -d keycloak booking_system_mcp web_app_mcp ;;
    07)
      require_file "${SCRIPT_DIR}/vm-oauth.env"
      lab_compose "${lab}" up --build -d
      ;;
    08) bash "${HR_DIR}/start-hr-app.sh" "--backend=${HR_BACKEND:-python}" ;;
  esac
}

cmd_down() {
  local lab="$1"
  echo "Stopping L${lab}: $(lab_title "${lab}")"
  case "${lab}" in
    08) bash "${HR_DIR}/stop-hr-app.sh" "--backend=$(hr_backend)" ;;
    *) lab_compose "${lab}" down ;;
  esac
}

cmd_verify() {
  local lab="$1"
  echo "Verifying L${lab}: $(lab_title "${lab}")"
  case "${lab}" in
    01|02|03) bash "$(mcp_only_dir "${lab}")/verify.sh" ;;
    04)
      echo "Note: these scripts start docker_compose.basic-auth.yaml themselves and stop it when they finish."
      bash "${SCRIPT_DIR}/verify-basic-auth-backends.sh"
      bash "${SCRIPT_DIR}/verify-basic-auth-frontends-and-inspector.sh"
      ;;
    04-vm)
      echo "The Basic Auth verify scripts always use docker_compose.basic-auth.yaml." >&2
      echo "Stop L04-vm and run: $0 verify 04" >&2
      exit 2
      ;;
    05) bash "${SCRIPT_DIR}/verify-keycloak-auth-e2e.sh" ;;
    06) bash "${SCRIPT_DIR}/verify-keycloak-ui-basic-auth-mcp.sh" ;;
    07)
      require_file "${SCRIPT_DIR}/verify-keycloak-auth-remote.env"
      bash "${SCRIPT_DIR}/verify-keycloak-auth-remote.sh" --env-file "${SCRIPT_DIR}/verify-keycloak-auth-remote.env"
      ;;
    08)
      if curl -fsS http://localhost:8090/q/health/ready >/dev/null; then
        echo "PASS: HR portal ready at http://localhost:8090"
      else
        echo "FAIL: HR portal not ready at http://localhost:8090/q/health/ready" >&2
        exit 1
      fi
      ;;
  esac
}

# lab_of_container CONFIG_FILES: map a container's compose config files to a lab ID.
lab_of_container() {
  case "$1" in
    *booking_system_mcp_no_auth/*) echo "01" ;;
    *booking_system_mcp_basic_auth/*) echo "02" ;;
    *booking_system_mcp_oauth2_no_implicit_flow/*) echo "03" ;;
    *docker_compose.basic-auth-vm.yaml*) echo "04-vm" ;;
    *docker_compose.basic-auth.yaml*) echo "04" ;;
    *docker_compose.mcp-ui-keycloak-basic.yaml*) echo "06" ;;
    *docker_compose.vm-oauth.yaml*) echo "07" ;;
    *hr_database_frontend_java/docker-compose*) echo "08" ;;
    *local-container/docker_compose.yaml*) echo "05" ;;
  esac
}

# running_containers: prints "LAB CONTAINER" for every running container that belongs to a lab.
running_containers() {
  local name files lab
  docker ps --format '{{.Names}}|{{.Label "com.docker.compose.project.config_files"}}' |
    while IFS='|' read -r name files; do
      lab="$(lab_of_container "${files}")"
      if [[ -n "${lab}" ]]; then
        echo "${lab} ${name}"
      fi
    done
}

cmd_status() {
  local lines
  lines="$(running_containers | sort)"
  if [[ -z "${lines}" ]]; then
    echo "No lab is running."
    return
  fi
  printf '%-7s %s\n' "LAB" "CONTAINER"
  while read -r lab name; do
    printf '%-7s %s\n' "L${lab}" "${name}"
  done <<<"${lines}"
}

cmd_down_all() {
  local labs lab
  labs="$(running_containers | awk '{print $1}' | sort -u)"
  if [[ -z "${labs}" ]]; then
    echo "No lab is running."
    return
  fi
  for lab in ${labs}; do
    cmd_down "${lab}"
  done
}

command="${1:-}"
case "${command}" in
  list)
    for lab in ${LABS}; do
      printf 'L%-6s %s\n' "${lab}" "$(lab_title "${lab}")"
    done
    echo "L09, L10 (IBM Code Engine): see LABS.md"
    ;;
  up|down|verify)
    [[ $# -ge 2 ]] || { usage; exit 1; }
    lab="$(normalize_lab "$2")"
    "cmd_${command}" "${lab}"
    ;;
  status) cmd_status ;;
  down-all) cmd_down_all ;;
  -h|--help|help|"") usage ;;
  *) usage; exit 1 ;;
esac
