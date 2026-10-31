#!/usr/bin/env bash
# A catch that does nothing hides the failure. Log it (logSkipped or logWarning) or
# rethrow it. A catch with a comment saying why it is safe to ignore is allowed.
set -euo pipefail
cd "$(dirname "$0")/.."

if files=$(grep -rlPz "catch\s*\([^)]*\)\s*\{\s*\}" lib --include=*.dart); then
  echo "Empty catch blocks in:"
  echo "$files"
  exit 1
fi
echo "No empty catch blocks in lib/."
