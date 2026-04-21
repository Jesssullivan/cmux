#!/usr/bin/env bash
set -euo pipefail

if ! command -v nix >/dev/null 2>&1; then
  echo "::error::Nix is not installed on this self-hosted runner." >&2
  exit 1
fi

if [[ -z "${GITHUB_ENV:-}" ]]; then
  echo "::error::GITHUB_ENV is not set; this script is meant to run inside GitHub Actions." >&2
  exit 1
fi

ATTIC_PUBLIC_KEY="main:NKRk1XYo/dfd9fcDqgotUJg2DTDHWp5ny+Ba7WzRjgE="

emit_github_env() {
  local key="$1"
  shift

  {
    printf '%s<<EOF\n' "$key"
    printf '%s\n' "$@"
    printf 'EOF\n'
  } >>"$GITHUB_ENV"
}

if [[ -S /nix/var/nix/daemon-socket/socket ]]; then
  echo "NIX_REMOTE=daemon" >>"$GITHUB_ENV"
  echo "::notice::Using preinstalled Nix daemon at /nix/var/nix/daemon-socket/socket"
else
  echo "::warning::Nix daemon socket not found; using the runner's default Nix mode"
fi

declare -a nix_config_lines=()
if [[ -n "${NIX_CONFIG:-}" ]]; then
  nix_config_lines+=("${NIX_CONFIG}")
fi

if [[ -n "${ATTIC_SERVER:-}" && -n "${ATTIC_CACHE:-}" ]]; then
  nix_config_lines+=("extra-substituters = ${ATTIC_SERVER%/}/${ATTIC_CACHE}")
  nix_config_lines+=("extra-trusted-public-keys = ${ATTIC_PUBLIC_KEY}")
  echo "::notice::Configured Nix substituter ${ATTIC_SERVER%/}/${ATTIC_CACHE}"
fi

if (( ${#nix_config_lines[@]} > 0 )); then
  emit_github_env "NIX_CONFIG" "${nix_config_lines[@]}"
fi

echo "::notice::Using Nix from $(command -v nix)"
nix --version
