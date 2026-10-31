#!/usr/bin/env bash
# dart:io does not work on the web, so only the files listed in tool/dart_io_allowlist.txt
# may import it. A new import must go behind a conditional import, or be written so
# that it is never reached on the web. Remove a file from the list once it no longer
# imports dart:io.
set -euo pipefail
cd "$(dirname "$0")/.."

allowed=$(sort tool/dart_io_allowlist.txt)
found=$(grep -rl "^import 'dart:io';" lib --include=*.dart | sort || true)
new=$(comm -23 <(printf '%s\n' "$found") <(printf '%s\n' "$allowed") | sed '/^$/d' || true)

if [ -n "$new" ]; then
  echo "These files import dart:io but are not in tool/dart_io_allowlist.txt:"
  echo "$new"
  exit 1
fi
echo "dart:io is imported only by the files listed in tool/dart_io_allowlist.txt."
