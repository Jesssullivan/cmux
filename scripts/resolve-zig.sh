#!/usr/bin/env bash
set -euo pipefail

# Prefer an explicitly managed Zig install over whatever happens to appear
# first on PATH. This avoids local Nix profiles shadowing the repo's intended
# Zig version during Xcode/script-driven builds.

if [[ -n "${CMUX_ZIG_BIN:-}" ]]; then
  if [[ -x "${CMUX_ZIG_BIN}" ]]; then
    printf '%s\n' "${CMUX_ZIG_BIN}"
    exit 0
  fi
  echo "error: CMUX_ZIG_BIN is set but not executable: ${CMUX_ZIG_BIN}" >&2
  exit 1
fi

declare -a candidates=(
  "/usr/local/bin/zig"
  "/opt/homebrew/bin/zig"
  "$HOME/.local/zig/zig"
)

for candidate in "${candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    exit 0
  fi
done

if command -v zig >/dev/null 2>&1; then
  command -v zig
  exit 0
fi

echo "error: zig is required but was not found." >&2
echo "hint: install Zig 0.15.2 or set CMUX_ZIG_BIN=/abs/path/to/zig" >&2
exit 1
