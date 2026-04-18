#!/usr/bin/env bash
# Socket test runner for cmux-linux. Run inside: nix develop --command bash scripts/run-socket-tests.sh
#
# Test selection model: explicit baseline allowlist + opt-in candidate set.
#
#   BASELINE             Tests that pass green on every CI run. A failure here
#                        fails the job. Keep this list small and stable.
#
#   CANDIDATES_PHASE1    Tests we believe should pass on Linux but have not
#                        verified yet. Run only when CMUX_TEST_PHASE1=1.
#                        Failures are reported but do NOT fail the job — the
#                        gate exists so we can observe behavior on real CI
#                        without regressing the green baseline. After several
#                        consecutive green runs, promote into BASELINE.
#
# Adding a new test:
#   1. Land the test in tests_v2/test_*.py.
#   2. If you believe it'll pass on Linux, add the basename to
#      CANDIDATES_PHASE1 and set CMUX_TEST_PHASE1=1 in CI for at least
#      one merged PR run to observe.
#   3. If green, move from CANDIDATES_PHASE1 to BASELINE and drop the gate.
#
# Tracking issue: #216 (TIN-183 — expand tests_v2 Linux coverage).
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

# ── Baseline allowlist ──────────────────────────────────────────────
# The 15 tests known to pass on cmux-linux today. A failure in any of
# these fails the job.
BASELINE=(
  test_close_surface_selection
  test_close_workspace_selection
  test_focus_notification_dismiss
  test_nested_split_no_detach_during_update
  test_notification_socket_api
  test_pane_break_swap_preserve_focus
  test_pane_operations
  test_signals_auto
  test_surface_split_tree
  test_system_api
  test_trigger_flash
  test_windows_api
  test_workspace_lifecycle
  test_workspace_navigation
  test_workspace_reorder
)

# ── Phase 1 candidate allowlist (gated) ─────────────────────────────
# Tests we believe should pass on Linux but have not verified. Run only
# when CMUX_TEST_PHASE1=1. Candidate failures are reported but do not
# fail the job — see header comment for promotion workflow.
CANDIDATES_PHASE1=(
  test_browser_open_split_reuse_policy
  test_workspace_create_background_starts_terminal
  test_workspace_create_initial_env
)

# Build the test list. Apply TEST_FILTER if set (case-style glob).
TESTS=()
CANDIDATE_NAMES=()

filter_match() {
  local name="$1"
  [ -z "$FILTER" ] && return 0
  case "$name" in $FILTER) return 0 ;; *) return 1 ;; esac
}

resolve_test() {
  local name="$1"
  local f="$TESTS_DIR/${name}.py"
  if [ ! -f "$f" ]; then
    echo "WARN: allowlisted test missing on disk: $name" >&2
    return 1
  fi
  filter_match "$name" || return 1
  TESTS+=("$f")
  return 0
}

for name in "${BASELINE[@]}"; do
  resolve_test "$name" || true
done

if [ "${CMUX_TEST_PHASE1:-0}" = "1" ]; then
  echo "=== Phase 1 candidate gate enabled (CMUX_TEST_PHASE1=1) ==="
  for name in "${CANDIDATES_PHASE1[@]}"; do
    if resolve_test "$name"; then
      CANDIDATE_NAMES+=("$name")
    fi
  done
fi

is_candidate() {
  local needle="$1"
  for c in "${CANDIDATE_NAMES[@]}"; do
    [ "$c" = "$needle" ] && return 0
  done
  return 1
}

TOTAL=${#TESTS[@]}
echo "=== Running $TOTAL tests (${#BASELINE[@]} baseline, ${#CANDIDATE_NAMES[@]} phase1 candidates) ==="
echo "TAP version 13" > "$TAP_FILE"
echo "1..$TOTAL" >> "$TAP_FILE"

PASS=0 FAIL=0 NUM=0 CAND_PASS=0 CAND_FAIL=0
for test_file in "${TESTS[@]}"; do
  NUM=$((NUM + 1))
  name=$(basename "$test_file" .py)
  if timeout 5 python3 "$test_file" > "/tmp/socket-tests-${name}.log" 2>&1; then
    if is_candidate "$name"; then
      CAND_PASS=$((CAND_PASS + 1))
      echo "ok $NUM $name # candidate" >> "$TAP_FILE"
      echo "PASS: $name (candidate)"
    else
      PASS=$((PASS + 1))
      echo "ok $NUM $name" >> "$TAP_FILE"
      echo "PASS: $name"
    fi
  else
    if is_candidate "$name"; then
      CAND_FAIL=$((CAND_FAIL + 1))
      # TAP-style "todo" — visible as a failure but conventionally non-fatal
      echo "not ok $NUM $name # TODO candidate (non-fatal)" >> "$TAP_FILE"
      echo "FAIL: $name (candidate, non-fatal)"
    else
      FAIL=$((FAIL + 1))
      echo "not ok $NUM $name" >> "$TAP_FILE"
      echo "FAIL: $name"
    fi
  fi
done

echo ""
echo "=== Baseline: $PASS/${#BASELINE[@]} passed, $FAIL failed ==="
if [ "${#CANDIDATE_NAMES[@]}" -gt 0 ]; then
  echo "=== Phase 1 candidates: $CAND_PASS/${#CANDIDATE_NAMES[@]} passed, $CAND_FAIL failed (non-fatal) ==="
fi
echo "=== Daemon stderr ==="
head -5 "$STDERR_LOG" 2>/dev/null

# Only baseline failures fail the job. Phase 1 candidate failures are
# observational — promote into BASELINE once consistently green.
[ $FAIL -gt 0 ] && exit 1 || exit 0
