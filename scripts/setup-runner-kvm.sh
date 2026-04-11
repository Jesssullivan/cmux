#!/usr/bin/env bash
# Setup a self-hosted GitHub Actions runner for cmux QEMU distro testing.
#
# SECURITY:
#   - Runner only accessible via push triggers (no fork PR execution)
#   - Distro test workflow requires 'distro-tests' environment approval
#   - No secrets stored on disk; use GitHub encrypted secrets only
#   - Runner registered with --replace to prevent stale registrations
#
# Prerequisites:
#   - Linux x86_64 with KVM support (Intel VT-x or AMD-V)
#   - /dev/kvm accessible by the runner user
#   - sudo access to install packages
#
# Usage:
#   GITHUB_TOKEN=<token> ./scripts/setup-runner-kvm.sh [runner-name]
#
# The token needs 'repo' scope. Generate at:
#   https://github.com/Jesssullivan/cmux/settings/actions/runners/new
#
# After setup, create the 'distro-tests' environment in GitHub repo settings
# (Settings > Environments > New) with required reviewers enabled.

set -euo pipefail

RUNNER_NAME="${1:-neo}"
RUNNER_LABELS="self-hosted,linux,kvm,cmux-distro-test"
REPO="Jesssullivan/cmux"
RUNNER_DIR="${HOME}/actions-runner"
RUNNER_VERSION="2.322.0"
RUNNER_ARCH="linux-x64"

echo "=== cmux QEMU Distro Test Runner Setup ==="
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
        qemu-system-x86 qemu-utils \
        libguestfs-tools \
        python3 \
        socat
elif command -v dnf &>/dev/null; then
    sudo dnf install -y \
        gcc gcc-c++ git curl jq \
        qemu-kvm qemu-img \
        libguestfs-tools-c \
        python3 \
        socat
else
    echo "ERROR: Unsupported package manager. Install deps manually."
    exit 1
fi

# ── 2. Verify KVM access ──────────────────────────────────────────────

echo ""
echo "=== Checking KVM access ==="

if [ ! -c /dev/kvm ]; then
    echo "ERROR: /dev/kvm not found"
    echo "Check: CPU virtualization enabled in BIOS (VT-x/AMD-V)"
    echo "Check: kvm kernel modules loaded (modprobe kvm kvm_intel or kvm_amd)"
    exit 1
fi

if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo "WARNING: /dev/kvm not readable/writable by current user"
    echo "Fix: sudo usermod -aG kvm $USER && newgrp kvm"
    if ! groups | grep -q kvm; then
        echo "ERROR: Current user not in 'kvm' group"
        exit 1
    fi
fi

echo "KVM: $(ls -la /dev/kvm)"
echo "KVM group membership: OK"

# Verify QEMU can use KVM
# Rocky 10+ only ships /usr/libexec/qemu-kvm (no qemu-system-x86_64 in PATH)
if command -v qemu-system-x86_64 &>/dev/null; then
    QEMU_BIN="qemu-system-x86_64"
elif [ -x /usr/libexec/qemu-kvm ]; then
    QEMU_BIN="/usr/libexec/qemu-kvm"
else
    echo "ERROR: no QEMU KVM binary found (checked qemu-system-x86_64 and /usr/libexec/qemu-kvm)"
    exit 1
fi
echo "QEMU: $($QEMU_BIN --version | head -1)"

# ── 3. Install Nix (if not present) ───────────────────────────────────

echo ""
echo "=== Checking Nix installation ==="

if command -v nix &>/dev/null; then
    echo "Nix already installed: $(nix --version)"
else
    echo "Installing Nix..."
    curl -L https://nixos.org/nix/install | sh -s -- --daemon
    echo "Nix installed. You may need to restart your shell."
    echo "Then re-run this script."
    exit 0
fi

# Verify flake support
if ! nix flake --help &>/dev/null 2>&1; then
    echo "WARNING: Nix flake support not enabled"
    echo "Add to /etc/nix/nix.conf or ~/.config/nix/nix.conf:"
    echo "  experimental-features = nix-command flakes"
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
echo "Next steps:"
echo "  1. Create 'distro-tests' environment at:"
echo "     https://github.com/${REPO}/settings/environments/new"
echo "  2. Verify runner at:"
echo "     https://github.com/${REPO}/settings/actions/runners"
