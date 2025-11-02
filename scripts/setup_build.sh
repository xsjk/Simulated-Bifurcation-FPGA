#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME_FILE="$ROOT/.project-name"

# If a project name is provided, use it and update .project-name
if [ $# -ge 1 ]; then
  PN="$1"
  echo "$PN" > "$PROJECT_NAME_FILE"
  echo "[INFO] Updated .project-name to: $PN"
# Otherwise, read from .project-name
elif [ -f "$PROJECT_NAME_FILE" ]; then
  PN="$(cat "$PROJECT_NAME_FILE")"
  echo "[INFO] Using project name from .project-name: $PN"
else
  echo "Error: No project name provided and .project-name file not found."
  echo "Usage: $0 [PROJECT_NAME]"
  echo "  If PROJECT_NAME is provided, it will be saved to .project-name"
  echo "  Otherwise, the name will be read from .project-name"
  exit 1
fi

BUILD="$ROOT/build"

rm -rf "$BUILD"
mkdir -p "$BUILD"

# Create relative symlinks for easy repository movement
ln -sfn ../srcs "$BUILD/${PN}.srcs"
ln -sfn ../xpr  "$BUILD/${PN}.xpr"

echo "[OK] Created symlinks:"
echo "  $BUILD/${PN}.srcs -> ../srcs"
echo "  $BUILD/${PN}.xpr  -> ../xpr"
echo
echo "You can now open the project in Vivado using: build/${PN}.xpr"
