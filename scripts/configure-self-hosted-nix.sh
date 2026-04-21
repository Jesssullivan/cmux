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
DETERMINATE_NIXD_LOG="/tmp/determinate-nixd.log"

emit_github_env() {
  local key="$1"
  shift

  {
    printf '%s<<EOF\n' "$key"
    printf '%s\n' "$@"
    printf 'EOF\n'
  } >>"$GITHUB_ENV"
}

daemon_store_available() {
  nix store info --store daemon >/dev/null 2>&1
}

start_determinate_daemon() {
  local daemon_bin
  daemon_bin="$(command -v determinate-nixd)"

  if [[ "$(id -u)" -eq 0 ]]; then
    nohup "$daemon_bin" daemon >"$DETERMINATE_NIXD_LOG" 2>&1 &
    return 0
  fi

  if ! command -v sudo >/dev/null 2>&1; then
    echo "::error::determinate-nixd requires root to launch the daemon, but sudo is unavailable on this runner" >&2
    return 1
  fi

  if ! sudo -n true >/dev/null 2>&1; then
    echo "::error::Passwordless sudo is unavailable for launching determinate-nixd on this runner" >&2
    return 1
  fi

  nohup sudo -n "$daemon_bin" daemon >"$DETERMINATE_NIXD_LOG" 2>&1 &
}

emit_diagnostics() {
  echo "::notice::Nix daemon socket diagnostics"
  for path in \
    /nix/var/nix/daemon-socket \
    /nix/var/nix/daemon-socket/socket \
    /nix/var/determinate/determinate-nixd.socket \
    /var/run/nix-daemon.socket \
    /var/run/determinate-nixd.socket
  do
    if [[ -e "$path" || -L "$path" ]]; then
      ls -ld "$path" >&2
    else
      echo "missing: $path" >&2
    fi
  done

  if command -v ps >/dev/null 2>&1; then
    ps -ef | grep '[d]eterminate-nixd' >&2 || true
  fi
}

determine_daemon_mode() {
  if daemon_store_available; then
    echo "NIX_REMOTE=daemon" >>"$GITHUB_ENV"
    echo "::notice::Using preinitialized Nix daemon"
    return 0
  fi

  if command -v determinate-nixd >/dev/null 2>&1; then
    echo "::notice::Starting determinate-nixd for this workflow"
    rm -f "$DETERMINATE_NIXD_LOG"
    start_determinate_daemon

    local attempt
    for attempt in $(seq 1 100); do
      if daemon_store_available; then
        echo "NIX_REMOTE=daemon" >>"$GITHUB_ENV"
        echo "::notice::Determinate Nix daemon is ready"
        return 0
      fi
      sleep 0.2
    done

    echo "::error::Determinate Nix daemon did not become ready" >&2
    if [[ -f "$DETERMINATE_NIXD_LOG" ]]; then
      sed -n '1,120p' "$DETERMINATE_NIXD_LOG" >&2
    fi
    emit_diagnostics
    exit 1
  fi

  echo "::error::No usable Nix daemon detected on this self-hosted runner" >&2
  emit_diagnostics
  exit 1
}

determine_daemon_mode

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
