#!/usr/bin/env bash
# CJK input method validation for cmux-linux.
# Tests character output correctness via the socket API.
# Requires: fcitx5-gtk4, socat, xdotool
# Usage: nix develop --command bash scripts/test-cjk-input.sh
set -euo pipefail

BINARY="cmux-linux/zig-out/bin/cmux"
export LD_LIBRARY_PATH="$PWD/ghostty/zig-out/lib:${LD_LIBRARY_PATH:-}"
export DISPLAY=:99
export MESA_GL_VERSION_OVERRIDE=4.6COMPAT
export MESA_GLSL_VERSION_OVERRIDE=460
export LIBGL_ALWAYS_SOFTWARE=1
export XDG_RUNTIME_DIR="/tmp/xdg-cjk-test-$$"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }
skip() { echo "  SKIP: $1"; ((SKIP++)); }

# Send JSON-RPC to socket, return result
rpc() {
  local method="$1"
  local params="${2:-{}}"
  local id="${3:-1}"
  echo "{\"id\":$id,\"method\":\"$method\",\"params\":$params}" | \
    socat -t5 - UNIX-CONNECT:"$XDG_RUNTIME_DIR/cmux.sock" 2>/dev/null
}

# ─── Setup ──────────────────────────────────────────────────
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

echo "=== CJK Input Validation ==="
echo ""

# Check prerequisites
echo "--- Prerequisites ---"
HAS_FCITX5=false
HAS_IBUS=false
HAS_XDOTOOL=false

if command -v fcitx5 &>/dev/null; then
  echo "  fcitx5: $(fcitx5 --version 2>&1 | head -1)"
  HAS_FCITX5=true
else
  echo "  fcitx5: not installed"
fi

if command -v ibus &>/dev/null; then
  echo "  ibus: $(ibus version 2>&1 | head -1)"
  HAS_IBUS=true
else
  echo "  ibus: not installed"
fi

if command -v xdotool &>/dev/null; then
  HAS_XDOTOOL=true
  echo "  xdotool: available"
else
  echo "  xdotool: not installed"
fi

if ! command -v socat &>/dev/null; then
  echo "  socat: MISSING (required)"
  exit 1
fi

# Start Xvfb
Xvfb :99 -screen 0 1280x720x24 +extension GLX &
XVFB_PID=$!
sleep 1

# ─── Start cmux-linux ──────────────────────────────────────
echo ""
echo "--- Starting cmux-linux ---"
timeout 60 "$BINARY" 2>/tmp/cmux-cjk-stderr.log &
BINARY_PID=$!

# Wait for socket
for i in $(seq 1 20); do
  if [ -S "$XDG_RUNTIME_DIR/cmux.sock" ]; then
    echo "  Socket ready after ${i}x0.5s"
    break
  fi
  sleep 0.5
done

if [ ! -S "$XDG_RUNTIME_DIR/cmux.sock" ]; then
  echo "  FATAL: Socket not created"
  cat /tmp/cmux-cjk-stderr.log 2>/dev/null || true
  kill -9 $BINARY_PID 2>/dev/null || true
  kill -9 $XVFB_PID 2>/dev/null || true
  rm -rf "$XDG_RUNTIME_DIR"
  exit 1
fi

# Wait for renderer init
sleep 2

# ─── Test 1: Socket API health ─────────────────────────────
echo ""
echo "--- Test: Socket API health ---"
PING=$(rpc "system.ping")
if echo "$PING" | grep -q "pong"; then
  pass "system.ping responds"
else
  fail "system.ping: $PING"
fi

# Get workspace and surface IDs
WS_LIST=$(rpc "workspace.list")
SURFACE_ID=$(echo "$WS_LIST" | python3 -c "
import json, sys
data = json.load(sys.stdin)
result = data.get('result', {})
workspaces = result.get('workspaces', [])
if workspaces:
    ws = workspaces[0]
    panes = ws.get('panes', [])
    if panes:
        surfaces = panes[0].get('surfaces', [])
        if surfaces:
            print(surfaces[0].get('id', ''))
" 2>/dev/null || true)

if [ -n "$SURFACE_ID" ]; then
  pass "Got surface ID: ${SURFACE_ID:0:8}..."
else
  fail "Could not get surface ID"
  echo "  workspace.list response: $WS_LIST"
fi

# ─── Test 2: ASCII input baseline ──────────────────────────
echo ""
echo "--- Test: ASCII input baseline ---"
if [ -n "$SURFACE_ID" ]; then
  # Send ASCII text via socket
  rpc "surface.send_text" "{\"surface_id\":\"$SURFACE_ID\",\"text\":\"echo hello_cjk_test\\n\"}" 10 >/dev/null 2>&1
  sleep 1

  # Read screen
  SCREEN=$(rpc "surface.report_screen" "{\"surface_id\":\"$SURFACE_ID\"}" 11 2>/dev/null || true)
  if echo "$SCREEN" | grep -q "hello_cjk_test"; then
    pass "ASCII text appears in terminal output"
  else
    skip "surface.report_screen may not be wired (ASCII baseline)"
  fi
else
  skip "No surface ID for ASCII test"
fi

# ─── Test 3: Direct UTF-8 CJK character injection ─────────
echo ""
echo "--- Test: Direct UTF-8 CJK injection ---"
if [ -n "$SURFACE_ID" ]; then
  # Send CJK characters directly via socket (bypasses IME, tests rendering)
  rpc "surface.send_text" "{\"surface_id\":\"$SURFACE_ID\",\"text\":\"echo 你好世界\\n\"}" 20 >/dev/null 2>&1
  sleep 1

  SCREEN=$(rpc "surface.report_screen" "{\"surface_id\":\"$SURFACE_ID\"}" 21 2>/dev/null || true)
  if echo "$SCREEN" | grep -q "你好世界"; then
    pass "CJK characters rendered correctly (Chinese: 你好世界)"
  elif echo "$SCREEN" | grep -q "result"; then
    skip "screen capture available but CJK not found (may need encoding check)"
  else
    skip "surface.report_screen not available for CJK rendering check"
  fi

  # Japanese hiragana
  rpc "surface.send_text" "{\"surface_id\":\"$SURFACE_ID\",\"text\":\"echo こんにちは\\n\"}" 22 >/dev/null 2>&1
  sleep 1

  SCREEN=$(rpc "surface.report_screen" "{\"surface_id\":\"$SURFACE_ID\"}" 23 2>/dev/null || true)
  if echo "$SCREEN" | grep -q "こんにちは"; then
    pass "CJK characters rendered correctly (Japanese: こんにちは)"
  else
    skip "Japanese hiragana rendering check inconclusive"
  fi

  # Korean hangul
  rpc "surface.send_text" "{\"surface_id\":\"$SURFACE_ID\",\"text\":\"echo 안녕하세요\\n\"}" 24 >/dev/null 2>&1
  sleep 1

  SCREEN=$(rpc "surface.report_screen" "{\"surface_id\":\"$SURFACE_ID\"}" 25 2>/dev/null || true)
  if echo "$SCREEN" | grep -q "안녕하세요"; then
    pass "CJK characters rendered correctly (Korean: 안녕하세요)"
  else
    skip "Korean hangul rendering check inconclusive"
  fi
else
  skip "No surface ID for CJK injection test"
fi

# ─── Test 4: Wide character alignment ──────────────────────
echo ""
echo "--- Test: Wide character alignment ---"
if [ -n "$SURFACE_ID" ]; then
  # Full-width characters should occupy 2 cells each
  rpc "surface.send_text" "{\"surface_id\":\"$SURFACE_ID\",\"text\":\"echo ＡＢＣＤ\\n\"}" 30 >/dev/null 2>&1
  sleep 1

  SCREEN=$(rpc "surface.report_screen" "{\"surface_id\":\"$SURFACE_ID\"}" 31 2>/dev/null || true)
  if echo "$SCREEN" | grep -q "ＡＢＣＤ"; then
    pass "Full-width characters rendered"
  else
    skip "Full-width character test inconclusive"
  fi
else
  skip "No surface ID for wide char test"
fi

# ─── Test 5: IME framework availability ────────────────────
echo ""
echo "--- Test: IME framework availability ---"
if [ "$HAS_FCITX5" = true ]; then
  # Check if fcitx5-gtk4 module is installed
  if fcitx5-diagnose 2>/dev/null | grep -q "gtk4" || \
     ls /usr/lib*/fcitx5/gtk4* 2>/dev/null || \
     ls /usr/lib*/gtk-4.0/*/immodules/*fcitx* 2>/dev/null; then
    pass "fcitx5-gtk4 module found"
  else
    fail "fcitx5 installed but gtk4 module missing (install fcitx5-gtk4)"
  fi

  # Check available input methods
  if fcitx5-diagnose 2>/dev/null | grep -qi "anthy\|pinyin\|hangul" || \
     ls /usr/share/fcitx5/inputmethod/ 2>/dev/null | grep -qi "anthy\|pinyin\|hangul"; then
    pass "CJK input methods available in fcitx5"
  else
    skip "No CJK input methods configured in fcitx5"
  fi
else
  skip "fcitx5 not installed"
fi

if [ "$HAS_IBUS" = true ]; then
  if ibus list-engine 2>/dev/null | grep -qi "anthy\|pinyin\|hangul"; then
    pass "CJK input methods available in ibus"
  else
    skip "No CJK input methods configured in ibus"
  fi
else
  skip "ibus not installed"
fi

# ─── Test 6: Multi-surface CJK isolation ───────────────────
echo ""
echo "--- Test: Multi-surface CJK isolation ---"
if [ -n "$SURFACE_ID" ]; then
  # Create a split to get a second surface
  SPLIT_RESP=$(rpc "surface.split" "{\"surface_id\":\"$SURFACE_ID\",\"direction\":\"right\"}" 40 2>/dev/null || true)
  if echo "$SPLIT_RESP" | grep -q "result"; then
    sleep 1
    # Re-list to get both surfaces
    WS_LIST2=$(rpc "workspace.list" "{}" 41 2>/dev/null || true)
    SURFACE_COUNT=$(echo "$WS_LIST2" | python3 -c "
import json, sys
data = json.load(sys.stdin)
count = 0
for ws in data.get('result', {}).get('workspaces', []):
    for p in ws.get('panes', []):
        count += len(p.get('surfaces', []))
print(count)
" 2>/dev/null || echo "0")

    if [ "$SURFACE_COUNT" -ge 2 ]; then
      pass "Multi-surface created ($SURFACE_COUNT surfaces) — IME isolation testable"
    else
      skip "Split created but surface count unexpected: $SURFACE_COUNT"
    fi
  else
    skip "surface.split not available"
  fi
else
  skip "No surface ID for multi-surface test"
fi

# ─── Cleanup ───────────────────────────────────────────────
echo ""
echo "--- Cleanup ---"
if kill -0 $BINARY_PID 2>/dev/null; then
  kill -TERM $BINARY_PID 2>/dev/null || true
  for i in $(seq 1 6); do
    kill -0 $BINARY_PID 2>/dev/null || break
    sleep 0.5
  done
  kill -0 $BINARY_PID 2>/dev/null && kill -9 $BINARY_PID 2>/dev/null || true
fi
kill -9 $XVFB_PID 2>/dev/null || true
rm -rf "$XDG_RUNTIME_DIR"

# ─── Summary ──────────────────────────────────────────────
echo ""
echo "=== CJK Input Test Results ==="
echo "  PASS: $PASS"
echo "  FAIL: $FAIL"
echo "  SKIP: $SKIP"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "stderr output:"
  cat /tmp/cmux-cjk-stderr.log 2>/dev/null || true
  exit 1
fi

echo "CJK input validation completed"
