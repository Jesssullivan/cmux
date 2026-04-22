#!/usr/bin/env bash
# GPU smoke test for cmux-linux.
# Usage: nix develop --command bash scripts/smoke-test-gpu.sh [timeout_seconds]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT="${1:-15}"
BINARY="cmux-linux/zig-out/bin/cmux"
export LD_LIBRARY_PATH="$PWD/ghostty/zig-out/lib:${LD_LIBRARY_PATH:-}"
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export LIBGL_ALWAYS_SOFTWARE=1
export XDG_RUNTIME_DIR="/tmp/xdg-gpu-smoke-$$"
XVFB_LOG="/tmp/cmux-gpu-xvfb.log"

# shellcheck source=./xvfb.sh
source "$REPO_ROOT/scripts/xvfb.sh"

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# Start Xvfb
if ! start_xvfb "1280x720x24" "$XVFB_LOG"; then
  echo "FAIL: Xvfb failed to become ready"
  cat "$XVFB_LOG" 2>/dev/null || true
  exit 1
fi
echo "Xvfb ready on $DISPLAY"

echo "=== OpenGL info ==="
glxinfo 2>/dev/null | grep -E "OpenGL (version|renderer)|direct rendering" || echo "glxinfo not available"

echo "=== Starting cmux-linux (timeout ${TIMEOUT}s) ==="
timeout "$TIMEOUT" "$BINARY" 2>/tmp/cmux-gpu-stderr.log &
BINARY_PID=$!

# Wait for socket
SOCKET_FOUND=false
for i in $(seq 1 10); do
  if [ -S "$XDG_RUNTIME_DIR/cmux.sock" ]; then
    SOCKET_FOUND=true
    echo "Socket created after ${i}x0.5s"
    break
  fi
  sleep 0.5
done

# Wait for renderer to initialize
sleep 2

if [ "$SOCKET_FOUND" = true ]; then
  echo "=== Process alive? ==="
  kill -0 $BINARY_PID 2>/dev/null && echo "YES" || echo "NO"

  echo "=== system.ping ==="
  echo '{"id":1,"method":"system.ping","params":{}}' | socat -t3 - UNIX-CONNECT:"$XDG_RUNTIME_DIR/cmux.sock" 2>/dev/null || true
  echo ""

  echo "=== workspace.list ==="
  echo '{"id":2,"method":"workspace.list","params":{}}' | socat -t3 - UNIX-CONNECT:"$XDG_RUNTIME_DIR/cmux.sock" 2>/dev/null || true
  echo ""

  echo "=== system.identify ==="
  echo '{"id":3,"method":"system.identify","params":{}}' | socat -t3 - UNIX-CONNECT:"$XDG_RUNTIME_DIR/cmux.sock" 2>/dev/null || true
  echo ""
else
  echo "Socket not created within 5s"
  kill -0 $BINARY_PID 2>/dev/null && echo "Process running but no socket" || echo "Process already exited"
fi

echo "=== Clean shutdown ==="
if kill -0 $BINARY_PID 2>/dev/null; then
  kill -TERM $BINARY_PID 2>/dev/null || true
  for i in $(seq 1 6); do
    kill -0 $BINARY_PID 2>/dev/null || break
    sleep 0.5
  done
  kill -0 $BINARY_PID 2>/dev/null && { echo "SIGKILL"; kill -9 $BINARY_PID 2>/dev/null; } || echo "Clean shutdown: PASS"
else
  echo "Process already exited"
fi

echo "=== stderr ==="
cat /tmp/cmux-gpu-stderr.log 2>/dev/null || true

# Cleanup
kill -9 $XVFB_PID 2>/dev/null || true
rm -rf "$XDG_RUNTIME_DIR"

echo "=== GPU smoke test completed ==="
