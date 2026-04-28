#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <distro-check-name>" >&2
  echo "example: $0 distro-fedora42" >&2
  exit 2
fi

check_name="$1"
out_link="result-${check_name}-driver"

# Build the nix-vm-test driver with Nix, then run it outside the Nix build
# sandbox. The distro install tests intentionally use guest package managers,
# which need normal runner networking.
nix --store daemon build \
  ".#checks.x86_64-linux.${check_name}.passthru.targets.driver" \
  --out-link "$out_link" \
  --print-build-logs \
  -L \
  --option sandbox relaxed

"./${out_link}/bin/test-driver"
