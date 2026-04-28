#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <binary> <rpath>" >&2
  exit 2
fi

binary="$1"
rpath="$2"

if ! command -v patchelf >/dev/null 2>&1; then
  echo "error: patchelf is required to set the packaged cmux RUNPATH" >&2
  exit 1
fi

if [ ! -f "$binary" ]; then
  echo "error: binary not found: $binary" >&2
  exit 1
fi

patchelf --set-rpath "$rpath" "$binary"

actual="$(patchelf --print-rpath "$binary")"
if [ "$actual" != "$rpath" ]; then
  echo "error: expected RUNPATH '$rpath', got '$actual'" >&2
  exit 1
fi

case "$actual" in
  *ghostty/zig-out/lib*)
    echo "error: packaged cmux binary still references build-tree libghostty path: $actual" >&2
    exit 1
    ;;
esac

echo "set RUNPATH on $binary: $actual"
