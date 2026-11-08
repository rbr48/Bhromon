#!/usr/bin/env bash
# Checks that the functions the library exports are exactly the functions that
# include/e2ee_olm.h declares. Run it from native/e2ee_olm after a release build.
set -euo pipefail

cd "$(dirname "$0")/.."

lib="target/release/libe2ee_olm.so"
if [ ! -f "$lib" ]; then
  echo "missing $lib: run 'cargo build --release --locked' first" >&2
  exit 1
fi

exported=$(nm -D --defined-only "$lib" | awk '{print $NF}' | grep '^e2ee_' | sort -u)
declared=$(grep -o 'e2ee_[a-z0-9_]*(' include/e2ee_olm.h | tr -d '(' | sort -u)

if [ "$exported" != "$declared" ]; then
  echo "exports and header differ:" >&2
  diff <(echo "$declared") <(echo "$exported") >&2 || true
  exit 1
fi

echo "$(echo "$exported" | wc -l) exported functions match include/e2ee_olm.h"
