#!/usr/bin/env bash
# Socket test runner for cmux-linux. Run inside: nix develop --command bash scripts/run-socket-tests.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$REPO_ROOT/cmux-linux/zig-out/bin/cmux"
TESTS_DIR="$REPO_ROOT/tests_v2"
FILTER="${TEST_FILTER:-}"
STDERR_LOG="/tmp/socket-tests-stderr.log"
TAP_FILE="/tmp/socket-tests-results.tap"

cleanup() {
  [ -n "${CMUX_PID:-}" ] && kill -9 "$CMUX_PID" 2>/dev/null || true
  [ -n "${XVFB_PID:-}" ] && kill -9 "$XVFB_PID" 2>/dev/null || true
  [ -n "${XDG_RUNTIME_DIR:-}" ] && rm -rf "$XDG_RUNTIME_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Prepend ghostty lib
export LD_LIBRARY_PATH="$REPO_ROOT/ghostty/zig-out/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# patchelf the binary to use Nix's glibc interpreter (host glibc is too old for WebKitGTK)
NIX_INTERP=$(ls /nix/store/*glibc*/lib/ld-linux-x86-64.so.2 2>/dev/null | tail -1)
if [ -n "$NIX_INTERP" ] && command -v patchelf &>/dev/null; then
  echo "Patching interpreter: $NIX_INTERP"
  patchelf --set-interpreter "$NIX_INTERP" "$BINARY" 2>/dev/null || true
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

# Start daemon in test mode (CMUX_NO_SURFACE prevents GL crash, daemon survives indefinitely)
echo "=== Starting cmux daemon (CMUX_NO_SURFACE=1) ==="
export CMUX_NO_SURFACE=1
timeout 120 "$BINARY" 2>"$STDERR_LOG" &
CMUX_PID=$!

# Wait for socket
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

# Discover tests
TESTS=()
for f in "$TESTS_DIR"/test_*.py; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  [ -n "$FILTER" ] && case "$name" in $FILTER) ;; *) continue ;; esac
  case "$name" in
    # Require macOS app / GUI interaction
    test_browser_*|test_cli_*|test_ctrl_interactive*|test_ssh_*) continue ;;
    test_visual_*|test_lint_*|test_command_palette_*|test_tmux_*) continue ;;
    # Require macOS shortcuts, panel_snapshot, simulate_type, bonsplit_underflow
    test_nested_split_does_not_disappear*|test_nested_split_no_arranged_subview*) continue ;;
    test_nested_split_panel_routing*) continue ;;
    test_split_cmd_*|test_split_flash_*) continue ;;
    test_shortcut_window_scope*|test_tab_dragging*) continue ;;
    test_ctrl_enter_keybind*) continue ;;
    test_new_tab_interactive*|test_new_tab_render*) continue ;;
    test_initial_terminal_interactive*) continue ;;
    test_terminal_focus_routing*|test_terminal_input_render*) continue ;;
    test_v1_panel_creation*|test_update_timing*) continue ;;
    # Require real terminal PTY / I/O
    test_pane_resize_*|test_read_screen_capture*) continue ;;
    test_surface_list_custom_titles*) continue ;;
    test_workspace_create_background*|test_workspace_create_initial_env*) continue ;;
    test_ctrl_socket*) continue ;;
    # Require macOS CLI binary
    test_rename_tab_cli*|test_rename_window_workspace*) continue ;;
    test_tab_workspace_action_naming*|test_workspace_relative*) continue ;;
    # Require layout_debug (macOS debug-only)
    test_nested_split_preserves_existing*) continue ;;
    # Require macOS process patterns (pgrep .app/Contents/MacOS)
    test_cpu_usage*|test_cpu_notifications*) continue ;;
    # Require multi-window (not implemented on Linux)
    test_windows_api*) continue ;;
    # Require terminal send + OSC sequences for notification tests
    test_notifications*) continue ;;
    # Require real surface.move/reorder implementation
    test_surface_move_reorder_api*) continue ;;
  esac
  TESTS+=("$f")
done

TOTAL=${#TESTS[@]}
echo "=== Running $TOTAL tests ==="
echo "TAP version 13" > "$TAP_FILE"
echo "1..$TOTAL" >> "$TAP_FILE"

PASS=0 FAIL=0 NUM=0
for test_file in "${TESTS[@]}"; do
  NUM=$((NUM + 1))
  name=$(basename "$test_file" .py)
  if timeout 5 python3 "$test_file" > "/tmp/socket-tests-${name}.log" 2>&1; then
    PASS=$((PASS + 1))
    echo "ok $NUM $name" >> "$TAP_FILE"
    echo "PASS: $name"
  else
    FAIL=$((FAIL + 1))
    echo "not ok $NUM $name" >> "$TAP_FILE"
    echo "FAIL: $name"
  fi
done

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
echo "=== Daemon stderr ==="
head -5 "$STDERR_LOG" 2>/dev/null
[ $FAIL -gt 0 ] && exit 1 || exit 0
