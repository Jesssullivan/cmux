#!/usr/bin/env bash
# Socket/API test runner for cmux-linux on Linux.
# Runs platform-agnostic Python tests against the Unix socket interface.
# Usage: nix develop --command bash scripts/run-socket-tests.sh
# Environment: TEST_FILTER — optional glob (e.g., "test_workspace_*.py")
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$REPO_ROOT/cmux-linux/zig-out/bin/cmux"
TESTS_DIR="$REPO_ROOT/tests_v2"
FILTER="${TEST_FILTER:-}"

# Output
TAP_FILE="/tmp/socket-tests-results.tap"
STDERR_LOG="/tmp/socket-tests-stderr.log"

cleanup() {
  [ -n "${CMUX_PID:-}" ] && kill -9 "$CMUX_PID" 2>/dev/null || true
  [ -n "${XVFB_PID:-}" ] && kill -9 "$XVFB_PID" 2>/dev/null || true
  [ -n "${XDG_RUNTIME_DIR:-}" ] && rm -rf "$XDG_RUNTIME_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Environment — prepend ghostty lib; Nix's LD_LIBRARY_PATH has the rest
export LD_LIBRARY_PATH="$REPO_ROOT/ghostty/zig-out/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# patchelf the binary to use Nix's interpreter (avoids glibc mismatch at runtime)
NIX_LD=$(find /nix/store -maxdepth 1 -name '*glibc-2*' -type d 2>/dev/null | sort -V | tail -1)
if [ -n "$NIX_LD" ] && [ -f "$NIX_LD/lib/ld-linux-x86-64.so.2" ]; then
  echo "Patching binary interpreter to: $NIX_LD/lib/ld-linux-x86-64.so.2"
  if command -v patchelf &>/dev/null; then
    patchelf --set-interpreter "$NIX_LD/lib/ld-linux-x86-64.so.2" "$BINARY" 2>/dev/null || true
  fi
fi
export DISPLAY=:99
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export LIBGL_ALWAYS_SOFTWARE=1
export XDG_RUNTIME_DIR="/tmp/xdg-socket-tests-$$"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export CMUX_SOCKET="$XDG_RUNTIME_DIR/cmux.sock"

# Start Xvfb
Xvfb :99 -screen 0 1280x720x24 +extension GLX &
XVFB_PID=$!
sleep 1

# Start cmux daemon in test mode (no surface creation, no GL crash)
echo "=== Starting cmux daemon (CMUX_NO_SURFACE=1) ==="
export CMUX_NO_SURFACE=1
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" | head -c 200
echo "..."
timeout 120 "$BINARY" 2>"$STDERR_LOG" &
CMUX_PID=$!

# Wait for socket (Nix interpreter adds startup latency)
for i in $(seq 1 40); do
  [ -S "$CMUX_SOCKET" ] && break
  sleep 0.5
done

if [ ! -S "$CMUX_SOCKET" ]; then
  echo "FAIL: Socket not created within 20s"
  echo "Expected: $CMUX_SOCKET"
  ls -la "$XDG_RUNTIME_DIR/" 2>/dev/null || echo "(dir not found)"
  echo "Daemon stderr:"
  cat "$STDERR_LOG" 2>/dev/null
  exit 1
fi

echo "Socket ready: $CMUX_SOCKET"

# Discover tests (skip browser and interactive tests)
TESTS=()
for f in "$TESTS_DIR"/test_*.py; do
  [ -f "$f" ] || continue
  name=$(basename "$f")

  # Apply filter if set
  if [ -n "$FILTER" ]; then
    case "$name" in $FILTER) ;; *) continue ;; esac
  fi

  # Skip browser tests (need WebKit DOM interaction we haven't wired)
  case "$name" in test_browser_*) continue ;; esac
  # Skip interactive tests (need TTY)
  case "$name" in test_ctrl_interactive*) continue ;; esac
  # Skip SSH remote tests (need SSH infrastructure)
  case "$name" in test_ssh_*) continue ;; esac
  # Skip visual/screenshot tests (need display capture)
  case "$name" in test_visual_*) continue ;; esac
  # Skip lint tests (macOS source checks)
  case "$name" in test_lint_*) continue ;; esac

  TESTS+=("$f")
done

TOTAL=${#TESTS[@]}
echo "=== Running $TOTAL tests ==="
echo "TAP version 13" > "$TAP_FILE"
echo "1..$TOTAL" >> "$TAP_FILE"

PASS=0
FAIL=0
NUM=0

for test_file in "${TESTS[@]}"; do
  NUM=$((NUM + 1))
  name=$(basename "$test_file" .py)

  if timeout 10 python3 "$test_file" > "/tmp/socket-tests-${name}.log" 2>&1; then
    PASS=$((PASS + 1))
    echo "ok $NUM $name" >> "$TAP_FILE"
    echo "PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "not ok $NUM $name" >> "$TAP_FILE"
    echo "  # $(tail -1 "/tmp/socket-tests-${name}.log" 2>/dev/null)" >> "$TAP_FILE"
    echo "FAIL: $name"
  fi
done

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
echo ""

# Show daemon stderr
echo "=== Daemon stderr ==="
head -10 "$STDERR_LOG" 2>/dev/null

if [ $FAIL -gt 0 ]; then
  exit 1
fi
