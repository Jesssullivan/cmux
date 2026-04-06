#!/usr/bin/env bash
# SSH proxy test runner for cmux-linux.
# Requires: Docker, curl, ssh-keygen, Python 3.
# Run inside: nix develop --command bash scripts/run-ssh-proxy-tests.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$REPO_ROOT/cmux-linux/zig-out/bin/cmux"
TESTS_DIR="$REPO_ROOT/tests_v2"
FILTER="${TEST_FILTER:-}"
STDERR_LOG="/tmp/ssh-proxy-tests-stderr.log"
TAP_FILE="/tmp/ssh-proxy-tests-results.tap"

cleanup() {
  [ -n "${CMUX_PID:-}" ] && kill -9 "$CMUX_PID" 2>/dev/null || true
  [ -n "${XVFB_PID:-}" ] && kill -9 "$XVFB_PID" 2>/dev/null || true
  [ -n "${XDG_RUNTIME_DIR:-}" ] && rm -rf "$XDG_RUNTIME_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Verify Docker
if ! docker info >/dev/null 2>&1; then
  echo "FAIL: Docker is not available"
  exit 1
fi

# Prepend ghostty lib
export LD_LIBRARY_PATH="$REPO_ROOT/ghostty/zig-out/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# patchelf for Nix glibc
NIX_INTERP=$(ls /nix/store/*glibc*/lib/ld-linux-x86-64.so.2 2>/dev/null | tail -1)
if [ -n "$NIX_INTERP" ] && command -v patchelf &>/dev/null; then
  echo "Patching interpreter: $NIX_INTERP"
  patchelf --set-interpreter "$NIX_INTERP" "$BINARY" 2>/dev/null || true
fi
export DISPLAY=:99
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export LIBGL_ALWAYS_SOFTWARE=1
export XDG_RUNTIME_DIR="/tmp/xdg-ssh-proxy-tests-$$"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export CMUX_SOCKET="$XDG_RUNTIME_DIR/cmux.sock"

# Export CLI path for tests that need it
export CMUXTERM_CLI="$BINARY"

# Start Xvfb
Xvfb :99 -screen 0 1280x720x24 +extension GLX &
XVFB_PID=$!
sleep 1

# Start daemon
echo "=== Starting cmux daemon (CMUX_NO_SURFACE=1) ==="
export CMUX_NO_SURFACE=1
timeout 300 "$BINARY" 2>"$STDERR_LOG" &
CMUX_PID=$!

for i in $(seq 1 20); do
  [ -S "$CMUX_SOCKET" ] && break
  sleep 0.25
done

if [ ! -S "$CMUX_SOCKET" ]; then
  echo "FAIL: Socket not created"
  cat "$STDERR_LOG" 2>/dev/null
  exit 1
fi
echo "Socket ready"

# Discover Docker SSH proxy tests
TESTS=()
for f in "$TESTS_DIR"/test_ssh_remote_docker_*.py "$TESTS_DIR"/test_ssh_remote_proxy_*.py; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  [ -n "$FILTER" ] && case "$name" in $FILTER) ;; *) continue ;; esac
  TESTS+=("$f")
done

TOTAL=${#TESTS[@]}
echo "=== Running $TOTAL SSH proxy tests ==="
echo "TAP version 13" > "$TAP_FILE"
echo "1..$TOTAL" >> "$TAP_FILE"

PASS=0 FAIL=0 NUM=0
for test_file in "${TESTS[@]}"; do
  NUM=$((NUM + 1))
  name=$(basename "$test_file" .py)
  LOG="/tmp/ssh-proxy-tests-${name}.log"
  echo "--- $name ---"
  if timeout 120 python3 "$test_file" > "$LOG" 2>&1; then
    if grep -q "^SKIP:" "$LOG" 2>/dev/null; then
      PASS=$((PASS + 1))
      echo "ok $NUM $name # SKIP $(grep '^SKIP:' "$LOG" | head -1)" >> "$TAP_FILE"
      echo "SKIP: $name ($(grep '^SKIP:' "$LOG" | head -1))"
    else
      PASS=$((PASS + 1))
      echo "ok $NUM $name" >> "$TAP_FILE"
      echo "PASS: $name"
    fi
  else
    FAIL=$((FAIL + 1))
    echo "not ok $NUM $name" >> "$TAP_FILE"
    echo "FAIL: $name"
    tail -10 "$LOG" 2>/dev/null
  fi
done

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[ $FAIL -gt 0 ] && exit 1 || exit 0
