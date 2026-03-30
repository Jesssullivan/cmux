#!/usr/bin/env bash
# Setup a self-hosted GitHub Actions runner for cmux-linux GPU testing.
#
# Prerequisites:
#   - Linux x86_64 with AMD GPU (RDNA 2+ for OpenGL 4.6)
#   - User in 'render' and 'video' groups for GPU access
#   - Network access to GitHub API
#
# Usage:
#   GITHUB_TOKEN=<token> ./scripts/setup-runner.sh [runner-name]
#
# The token needs 'repo' scope. Generate at:
#   https://github.com/Jesssullivan/cmux/settings/actions/runners/new

set -euo pipefail

RUNNER_NAME="${1:-$(hostname)}"
RUNNER_LABELS="self-hosted,linux,gpu,cmux-test"
REPO="Jesssullivan/cmux"
RUNNER_DIR="${HOME}/actions-runner"
RUNNER_VERSION="2.322.0"
RUNNER_ARCH="linux-x64"

echo "=== cmux-linux GPU Runner Setup ==="
echo "Runner name: $RUNNER_NAME"
echo "Labels: $RUNNER_LABELS"
echo "Repo: $REPO"
echo ""

# ── 1. System dependencies ──────────────────────────────────────────────

echo "=== Installing system dependencies ==="

if command -v apt-get &>/dev/null; then
    sudo apt-get update
    sudo apt-get install -y \
        build-essential git curl jq \
        pkg-config \
        libgtk-4-dev libadwaita-1-dev \
        libfreetype-dev libharfbuzz-dev libfontconfig-dev \
        libpng-dev libonig-dev libgl-dev \
        libsecret-1-dev libnotify-dev \
        glslang-tools spirv-cross \
        mesa-utils vulkan-tools \
        xvfb socat gdb \
        fonts-dejavu-core fonts-liberation \
        python3
elif command -v dnf &>/dev/null; then
    sudo dnf install -y \
        gcc gcc-c++ git curl jq \
        pkg-config \
        gtk4-devel libadwaita-devel \
        freetype-devel harfbuzz-devel fontconfig-devel \
        libpng-devel oniguruma-devel mesa-libGL-devel \
        libsecret-devel libnotify-devel \
        mesa-utils vulkan-tools \
        xorg-x11-server-Xvfb socat gdb \
        dejavu-sans-fonts liberation-fonts \
        python3
else
    echo "ERROR: Unsupported package manager. Install deps manually."
    exit 1
fi

# ── 2. Verify GPU access ────────────────────────────────────────────────

echo ""
echo "=== Checking GPU access ==="

if [ ! -e /dev/dri/renderD128 ]; then
    echo "WARNING: /dev/dri/renderD128 not found — GPU may not be available"
    echo "Check: lsmod | grep amdgpu"
else
    echo "Render node: $(ls -la /dev/dri/renderD128)"
fi

# Check if user can access the GPU
if ! groups | grep -qE 'render|video'; then
    echo "WARNING: Current user not in 'render' or 'video' groups"
    echo "Fix: sudo usermod -aG render,video $USER && newgrp render"
fi

# Verify OpenGL
if command -v glxinfo &>/dev/null; then
    echo ""
    echo "=== OpenGL info ==="
    # Try with real display first, fall back to Xvfb
    if [ -n "${DISPLAY:-}" ]; then
        glxinfo 2>/dev/null | grep -E "OpenGL (version|renderer)|direct rendering" || true
    else
        echo "(Starting temporary Xvfb to check GL...)"
        Xvfb :98 -screen 0 800x600x24 &
        XVFB_PID=$!
        sleep 1
        DISPLAY=:98 glxinfo 2>/dev/null | grep -E "OpenGL (version|renderer)|direct rendering" || true
        kill $XVFB_PID 2>/dev/null || true
    fi
fi

# ── 3. Install Zig ──────────────────────────────────────────────────────

echo ""
echo "=== Installing Zig 0.15.2 ==="

ZIG_VERSION="0.15.2"
ZIG_DIR="${HOME}/.local/zig"
ZIG_TARBALL="zig-linux-x86_64-${ZIG_VERSION}.tar.xz"
ZIG_URL="https://ziglang.org/builds/${ZIG_TARBALL}"

if [ -x "${ZIG_DIR}/zig" ] && "${ZIG_DIR}/zig" version 2>/dev/null | grep -q "${ZIG_VERSION}"; then
    echo "Zig ${ZIG_VERSION} already installed"
else
    mkdir -p "${ZIG_DIR}"
    curl -L "${ZIG_URL}" | tar xJ --strip-components=1 -C "${ZIG_DIR}"
    echo "Zig installed: $("${ZIG_DIR}/zig" version)"
fi

# Add to PATH if not already there
if ! echo "$PATH" | grep -q "${ZIG_DIR}"; then
    export PATH="${ZIG_DIR}:${PATH}"
    echo "export PATH=\"${ZIG_DIR}:\${PATH}\"" >> "${HOME}/.profile"
fi

# ── 4. Install GitHub Actions runner ────────────────────────────────────

echo ""
echo "=== Setting up GitHub Actions runner ==="

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "ERROR: GITHUB_TOKEN not set"
    echo "Generate a token at: https://github.com/${REPO}/settings/actions/runners/new"
    echo "Re-run: GITHUB_TOKEN=<token> $0 ${RUNNER_NAME}"
    exit 1
fi

mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

if [ ! -f ./config.sh ]; then
    echo "Downloading runner ${RUNNER_VERSION}..."
    curl -o runner.tar.gz -L \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
    tar xzf runner.tar.gz
    rm runner.tar.gz
fi

# Get registration token
REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO}/actions/runners/registration-token" \
    | jq -r .token)

if [ "${REG_TOKEN}" = "null" ] || [ -z "${REG_TOKEN}" ]; then
    echo "ERROR: Failed to get registration token"
    echo "Make sure GITHUB_TOKEN has admin:repo scope"
    exit 1
fi

# Configure runner
./config.sh \
    --url "https://github.com/${REPO}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --runnergroup "default" \
    --replace

echo ""
echo "=== Installing as systemd service ==="
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status

echo ""
echo "=== Runner setup complete ==="
echo "Runner: ${RUNNER_NAME}"
echo "Labels: ${RUNNER_LABELS}"
echo "Directory: ${RUNNER_DIR}"
echo ""
echo "Verify at: https://github.com/${REPO}/settings/actions/runners"
