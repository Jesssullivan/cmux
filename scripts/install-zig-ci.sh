#!/usr/bin/env bash
set -euo pipefail

ZIG_VERSION="${1:-0.15.2}"

case "$(uname -s)" in
  Linux)
    zig_os="linux"
    ;;
  Darwin)
    zig_os="macos"
    ;;
  *)
    echo "Unsupported OS for Zig install: $(uname -s)" >&2
    exit 1
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64)
    zig_arch="x86_64"
    ;;
  arm64|aarch64)
    zig_arch="aarch64"
    ;;
  *)
    echo "Unsupported architecture for Zig install: $(uname -m)" >&2
    exit 1
    ;;
esac

zig_base="zig-${zig_arch}-${zig_os}-${ZIG_VERSION}"
zig_root="${RUNNER_TEMP:-/tmp}/zig-toolchains"
zig_dir="${zig_root}/${zig_base}"
zig_archive="${zig_root}/${zig_base}.tar.xz"
zig_url="https://ziglang.org/download/${ZIG_VERSION}/${zig_base}.tar.xz"

mkdir -p "${zig_root}"

if [ ! -x "${zig_dir}/zig" ] || ! "${zig_dir}/zig" version 2>/dev/null | grep -q "^${ZIG_VERSION}\$"; then
  rm -rf "${zig_dir}"
  echo "Installing Zig ${ZIG_VERSION} from ${zig_url}"
  curl -fSL "${zig_url}" -o "${zig_archive}"
  tar -xf "${zig_archive}" -C "${zig_root}"
fi

if [ ! -x "${zig_dir}/zig" ]; then
  echo "Zig install did not produce ${zig_dir}/zig" >&2
  exit 1
fi

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "${zig_dir}" >> "${GITHUB_PATH}"
fi

export PATH="${zig_dir}:${PATH}"
echo "Using Zig at ${zig_dir}"
zig version
