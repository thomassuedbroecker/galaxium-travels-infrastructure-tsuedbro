#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# run-code-review-web-app-mcp.sh
#
# Runs a Bob CLI code review for the galaxium-booking-web-app-mcp/ application.
# The review output is printed to stdout only — nothing is saved to disk.
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${REPO_ROOT}/galaxium-booking-web-app-mcp"

# ── Sanity checks ────────────────────────────────────────────────────────────
if ! command -v bob &>/dev/null; then
  echo "ERROR: 'bob' CLI not found in PATH. Install Bob Shell and retry." >&2
  exit 1
fi

if [[ ! -d "${APP_DIR}" ]]; then
  echo "ERROR: Application directory not found: ${APP_DIR}" >&2
  exit 1
fi

# ── Spinner — shows live activity while bob is running ───────────────────────
spinner() {
  local pid=$1
  local frames='|/-\'
  local i=0
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    local frame="${frames:$((i % 4)):1}"
    printf "\r  %s  Reviewing files ... %ds elapsed" "$frame" "$elapsed"
    sleep 1
    (( i++ ))   || true
    (( elapsed++ )) || true
  done
  printf "\r%-60s\r" " "   # clear spinner line
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo "=========================================================="
echo " Bob CLI Code Review — galaxium-booking-web-app-mcp"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================================="
echo
echo "  Files in scope:"
echo "    app/app.py"
echo "    app/booking_mcp_service.py"
echo "    app/requirements.txt"
echo "    app/static/script.js"
echo "    app/static/style.css"
echo "    app/templates/index.html"
echo "    app/templates/login.html"
echo "    Dockerfile"
echo "    .env-template"
echo
echo "  Mode: arch-review  |  Max coins: 3"
echo "----------------------------------------------------------"
echo

# ── Write prompt to a temp file (heredoc cannot attach to a backgrounded cmd) ─
PROMPT_FILE=$(mktemp)
REVIEW_OUTPUT=$(mktemp)
trap 'rm -f "${PROMPT_FILE}" "${REVIEW_OUTPUT}"' EXIT

cat > "${PROMPT_FILE}" <<'PROMPT_EOF'
Perform a thorough code review of the galaxium-booking-web-app-mcp/ application.

Scope — review ONLY the files inside galaxium-booking-web-app-mcp/:
  - app/app.py
  - app/booking_mcp_service.py
  - app/requirements.txt
  - app/static/script.js
  - app/static/style.css
  - app/templates/index.html
  - app/templates/login.html
  - Dockerfile
  - .env-template

For each file, evaluate and report on:
  1. Correctness        - logic errors, edge cases, error handling
  2. Security           - injection risks, secrets exposure, auth gaps, unsafe patterns
  3. Code quality       - readability, naming, duplication, dead code
  4. Dependencies       - outdated or risky packages in requirements.txt
  5. Docker best practices - image hygiene, layer caching, non-root user, secrets leakage
  6. Configuration      - .env-template completeness and safe defaults

Format the output as:
  ## <filename>
  ### Findings
  - [SEVERITY] Description and recommendation   (SEVERITY: CRITICAL | HIGH | MEDIUM | LOW | INFO)

  ### Summary
  Brief overall assessment for this file.

End with a ## Overall Summary section listing the top 5 actionable improvements
across the entire application, ranked by severity.

Do NOT write any output to files — print to stdout only.
PROMPT_EOF

# ── Run bob in background, spinner shows progress ────────────────────────────
NODE_NO_WARNINGS=1 bob \
  --chat-mode arch-review \
  --approval-mode yolo \
  --hide-intermediary-output \
  --trust \
  --max-coins 3 \
  < "${PROMPT_FILE}" > "${REVIEW_OUTPUT}" 2>&1 &
BOB_PID=$!

spinner "$BOB_PID"
wait "$BOB_PID"
BOB_EXIT=$?

# ── Print results ─────────────────────────────────────────────────────────────
echo "=========================================================="
if [[ $BOB_EXIT -eq 0 ]]; then
  echo " Review complete  |  $(date '+%Y-%m-%d %H:%M:%S')"
else
  echo " Review stopped (exit code: ${BOB_EXIT})  |  $(date '+%Y-%m-%d %H:%M:%S')"
fi
echo "=========================================================="
echo

cat "${REVIEW_OUTPUT}"
exit "$BOB_EXIT"
