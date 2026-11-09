#!/usr/bin/env bash
# Packages precompiled libe2ee_olm.so binaries into android/app/src/main/jniLibs
# for Android APK and AAB packaging (E2EE_DESIGN.md, Milestone M4).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_DIR="$REPO_ROOT/native/e2ee_olm/dist/android"
DEST_DIR="$REPO_ROOT/android/app/src/main/jniLibs"

if [ ! -d "$SRC_DIR" ]; then
  echo "Error: Source directory $SRC_DIR does not exist." >&2
  echo "Build the native libraries first using .github/workflows/e2ee_native.yml or cargo." >&2
  exit 1
fi

for abi in arm64-v8a armeabi-v7a x86_64; do
  if [ -f "$SRC_DIR/$abi/libe2ee_olm.so" ]; then
    mkdir -p "$DEST_DIR/$abi"
    cp -v "$SRC_DIR/$abi/libe2ee_olm.so" "$DEST_DIR/$abi/libe2ee_olm.so"
  else
    echo "Warning: $SRC_DIR/$abi/libe2ee_olm.so not found." >&2
  fi
done

echo "Successfully packaged E2EE native libraries into $DEST_DIR"
