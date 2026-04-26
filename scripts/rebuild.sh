#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

TAG="rebuild"

if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
  TAG="$1"
  shift
fi

echo "warning: ./scripts/rebuild.sh is deprecated." >&2
echo "warning: using tagged reload flow instead of the removed SwiftPM app path." >&2

for arg in "$@"; do
  if [[ "$arg" == "--tag" ]]; then
    exec "$SCRIPT_DIR/reload.sh" "$@"
  fi
done

exec "$SCRIPT_DIR/reload.sh" --tag "$TAG" "$@"
