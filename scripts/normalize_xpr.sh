#!/usr/bin/env bash
set -euo pipefail

TARGET_PATH="${1:-PROJECT_NAME.xpr}"

XPR_FILE="$(cd "$(dirname "$0")/.." && pwd)/xpr"

if [ ! -f "$XPR_FILE" ]; then
  echo "File not found: $XPR_FILE"
  exit 1
fi

sed -E -i 's#(<Project[^>]*[[:space:]]Path=")[^"]*(")#\1'"$TARGET_PATH"'\2#' "$XPR_FILE"
echo "[OK] Normalized xpr file path to: $TARGET_PATH"

