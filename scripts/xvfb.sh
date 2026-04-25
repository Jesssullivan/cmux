#!/usr/bin/env bash
# Shared Xvfb startup helper for Linux test runners.

start_xvfb() {
  local screen="${1:-1280x720x24}"
  local log_file="${2:-/tmp/xvfb.log}"
  local display_file=""

  display_file="$(mktemp)"

  if Xvfb -help 2>&1 | grep -q -- "-displayfd"; then
    Xvfb -displayfd 3 -screen 0 "$screen" +extension GLX >"$log_file" 2>&1 3>"$display_file" &
    XVFB_PID=$!

    for _ in $(seq 1 80); do
      if [ -s "$display_file" ]; then
        export DISPLAY=":$(tr -d '\n' < "$display_file")"
        rm -f "$display_file"
        return 0
      fi
      if ! kill -0 "$XVFB_PID" 2>/dev/null; then
        rm -f "$display_file"
        return 1
      fi
      sleep 0.25
    done

    rm -f "$display_file"
    return 1
  fi

  rm -f "$display_file"

  export DISPLAY="${DISPLAY:-:99}"
  Xvfb "$DISPLAY" -screen 0 "$screen" +extension GLX >"$log_file" 2>&1 &
  XVFB_PID=$!

  local display_num="${DISPLAY#:}"
  for _ in $(seq 1 40); do
    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      sleep 0.5
      return 0
    fi
    if ! kill -0 "$XVFB_PID" 2>/dev/null; then
      return 1
    fi
    sleep 0.25
  done

  return 1
}
