#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: retry-zig-build.sh [--label NAME] [--working-directory DIR] -- COMMAND [ARGS...]

Retries a Zig build command after clearing Zig's package cache. This is intended
for CI legs that fetch upstream Zig packages and can fail on transient archive
download or unpack errors.
USAGE
}

label="zig build"
workdir=""
attempts="${ZIG_BUILD_RETRIES:-3}"
delay_seconds="${ZIG_BUILD_RETRY_DELAY_SECONDS:-15}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)
      label="${2:?missing value for --label}"
      shift 2
      ;;
    --working-directory)
      workdir="${2:?missing value for --working-directory}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "error: missing command" >&2
  usage
  exit 2
fi

if ! [[ "$attempts" =~ ^[0-9]+$ ]] || [[ "$attempts" -lt 1 ]]; then
  echo "error: ZIG_BUILD_RETRIES must be a positive integer" >&2
  exit 2
fi

if ! [[ "$delay_seconds" =~ ^[0-9]+$ ]]; then
  echo "error: ZIG_BUILD_RETRY_DELAY_SECONDS must be a non-negative integer" >&2
  exit 2
fi

if [[ -n "$workdir" ]]; then
  cd "$workdir"
fi

attempt=1
while true; do
  echo "==> ${label}: attempt ${attempt}/${attempts}"
  if "$@"; then
    exit 0
  fi

  status=$?
  if [[ "$attempt" -ge "$attempts" ]]; then
    echo "error: ${label} failed after ${attempts} attempts" >&2
    exit "$status"
  fi

  cache_dir="${ZIG_GLOBAL_CACHE_DIR:-$HOME/.cache/zig}"
  if [[ -d "$cache_dir" ]]; then
    echo "warning: ${label} failed with exit ${status}; clearing Zig package cache before retry" >&2
    rm -rf "$cache_dir/p" "$cache_dir/tmp"
  else
    echo "warning: ${label} failed with exit ${status}; retrying" >&2
  fi

  if [[ "$delay_seconds" -gt 0 ]]; then
    sleep "$delay_seconds"
  fi
  attempt=$((attempt + 1))
done
