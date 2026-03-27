#!/usr/bin/env bash
# zig-sdk-shim.sh — Workaround for zig LLD + macOS 26 SDK incompatibility
#
# macOS 26 (Tahoe) ships with SDK 26.4 whose tbd stubs aren't supported by
# zig's internal linker (LLD). This script creates a zig wrapper that uses
# the macOS 15.4 SDK from Command Line Tools instead.
#
# Usage: source scripts/zig-sdk-shim.sh
#        Then `zig build` works normally.
#
# Requires: macOS 15.4 SDK at /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
#           zig 0.15.2 at /tmp/zig-aarch64-macos-0.15.2/zig (or adjust ZIG_REAL below)

set -euo pipefail

SHIM_DIR="/tmp/zig-sdk-shim"
ZIG_REAL="${ZIG_REAL:-/tmp/zig-aarch64-macos-0.15.2/zig}"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"

if [ ! -d "$SDK_PATH" ]; then
    echo "error: macOS 15.4 SDK not found at $SDK_PATH" >&2
    echo "This shim is only needed on macOS 26+. On macOS 15, zig build works natively." >&2
    exit 1
fi

if [ ! -x "$ZIG_REAL" ]; then
    echo "error: zig not found at $ZIG_REAL" >&2
    echo "Download zig 0.15.2 from https://ziglang.org/download/ and set ZIG_REAL" >&2
    exit 1
fi

mkdir -p "$SHIM_DIR/xcrun-shim"

# xcrun wrapper returns macOS 15 SDK path
cat > "$SHIM_DIR/xcrun-shim/xcrun" << 'XCRUN'
#!/bin/bash
if [[ "$*" == *"--show-sdk-path"* ]]; then
    echo "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
else
    /usr/bin/xcrun "$@"
fi
XCRUN
chmod +x "$SHIM_DIR/xcrun-shim/xcrun"

# zig wrapper sets DEVELOPER_DIR and PATH for SDK resolution
cat > "$SHIM_DIR/zig" << ZIGWRAP
#!/bin/bash
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export PATH="$SHIM_DIR/xcrun-shim:\$PATH"
exec $ZIG_REAL "\$@"
ZIGWRAP
chmod +x "$SHIM_DIR/zig"

export PATH="$SHIM_DIR:$PATH"
echo "zig-sdk-shim: activated (zig $(zig version), SDK: macOS 15.4)"
