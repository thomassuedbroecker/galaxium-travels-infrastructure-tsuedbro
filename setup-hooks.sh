#!/usr/bin/env sh
# setup-hooks.sh
#
# Run once after cloning to activate the repository's Git hooks.
# This makes every commit automatically include the "Signed-off-by" trailer
# required by the Developer Certificate of Origin (DCO) check — no manual
# --signoff flag needed.
#
# Usage:
#   bash setup-hooks.sh

set -e

git config core.hooksPath .githooks
# Ensure the hook is executable locally and that the executable bit is recorded
# in the Git index so every fresh clone also has it set.
chmod +x .githooks/commit-msg
git update-index --chmod=+x .githooks/commit-msg

echo ""
echo "Git hooks activated."
echo "Every commit in this repository will now be signed off automatically."
echo ""
echo "Make sure your name and e-mail are set:"
echo "  git config --global user.name  \"Your Name\""
echo "  git config --global user.email \"you@example.com\""
echo ""
