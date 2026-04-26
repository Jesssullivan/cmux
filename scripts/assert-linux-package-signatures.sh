#!/usr/bin/env bash
# Verify every Linux release package in a directory has a detached signature.

set -euo pipefail

ARTIFACT_DIR="${1:-.}"

if [ ! -d "$ARTIFACT_DIR" ]; then
  echo "assert-linux-package-signatures: ERROR — artifact dir not found: $ARTIFACT_DIR" >&2
  exit 1
fi

shopt -s nullglob

checked_count=0
missing_count=0

for artifact in "$ARTIFACT_DIR"/*.deb "$ARTIFACT_DIR"/*.rpm "$ARTIFACT_DIR"/*.tar.gz; do
  checked_count=$((checked_count + 1))
  signature="${artifact}.asc"
  if [ ! -s "$signature" ]; then
    echo "assert-linux-package-signatures: ERROR — missing detached signature for $artifact" >&2
    missing_count=$((missing_count + 1))
  fi
done

if [ "$checked_count" -eq 0 ]; then
  echo "assert-linux-package-signatures: ERROR — no Linux package artifacts found in $ARTIFACT_DIR" >&2
  exit 1
fi

if [ "$missing_count" -ne 0 ]; then
  exit 1
fi

echo "assert-linux-package-signatures: verified detached signatures for $checked_count artifact(s) in $ARTIFACT_DIR"
