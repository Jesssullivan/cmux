#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <distro-check-name>" >&2
  echo "example: $0 distro-fedora42" >&2
  exit 2
fi

check_name="$1"
out_link="result-${check_name}-driver"
driver_timeout="${CMUX_DISTRO_DRIVER_TIMEOUT_SECONDS:-900}"
override_path="$PWD/nix/release-artifacts.override.nix"

# Build the nix-vm-test driver with Nix, then run it outside the Nix build
# sandbox. The distro install tests intentionally use guest package managers,
# which need normal runner networking.
echo "::group::Build ${check_name} VM test driver"
nix_args=(
  --store daemon
  build
)

if [ -f "$override_path" ]; then
  export CMUX_RELEASE_ARTIFACTS_OVERRIDE="$override_path"
  nix_args+=(--impure)
  echo "Using release artifact override: $CMUX_RELEASE_ARTIFACTS_OVERRIDE"
fi

nix_args+=(
  ".#checks.x86_64-linux.${check_name}.passthru.targets.driver"
  --out-link "$out_link"
  --print-build-logs
  -L
  --option sandbox relaxed
)

nix "${nix_args[@]}"
echo "::endgroup::"

echo "::group::Run ${check_name} VM test driver"
if command -v timeout >/dev/null 2>&1; then
  timeout --foreground "$driver_timeout" "./${out_link}/bin/test-driver"
else
  "./${out_link}/bin/test-driver"
fi
echo "::endgroup::"
