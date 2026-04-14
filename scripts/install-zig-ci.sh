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
zig_bin_target="/usr/local/bin/zig"
zig_lib_target="/usr/local/lib/zig"

run_as_root() {
  if [ -w "/usr/local/bin" ] && [ -w "/usr/local/lib" ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Need write access to /usr/local but sudo is unavailable" >&2
    exit 1
  fi
}

mkdir -p "${zig_root}"

if command -v zig >/dev/null 2>&1 && zig version 2>/dev/null | grep -q "^${ZIG_VERSION}\$" && [ -d "${zig_lib_target}" ]; then
  echo "Zig ${ZIG_VERSION} already installed"
  zig version
  exit 0
fi

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

run_as_root mkdir -p "$(dirname "${zig_bin_target}")" "$(dirname "${zig_lib_target}")"
run_as_root install -m 0755 "${zig_dir}/zig" "${zig_bin_target}"
run_as_root rm -rf "${zig_lib_target}"
run_as_root cp -R "${zig_dir}/lib" "${zig_lib_target}"

echo "Using Zig at ${zig_bin_target}"
zig version
