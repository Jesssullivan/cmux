# Downloadable Demo VM Images — Implementation Plan (TIN-182)

Updated: 2026-08-28

Status: planning/scoping only. No flake output or CI trigger is added by
this pass beyond an inert `workflow_dispatch`-only skeleton
(`.github/workflows/release-demo-vms.yml`) that does not fire on its own and
targets a flake output that does not exist yet.

## Goal (unchanged from the ticket)

"Try cmux Linux without installing anything": a downloadable Debian 12 and
Ubuntu 24.04 QCOW2 with cmux pre-installed, boot with
`qemu-system-x86_64 -m 4G -enable-kvm -hda cmux-demo-debian12.qcow2`,
published to a `demo-vms-vX.Y.Z` GitHub Release.

## Builder decision

**Use nix-vm-test's `pkgs.testers.nonNixOSDistros` machinery, not
packer/mkosi.** cmux already depends on it (`nix-vm-test` flake input,
`nix/tests-distro.nix`) for real Debian 12 / Ubuntu 24.04 cloud-image QEMU
boots that install the release `.deb` — introducing a second, unrelated
image-building toolchain (packer or mkosi) for the same two distros the repo
already boots via Nix would duplicate machinery for no benefit. This also
keeps the demo-VM build inside the same Nix/flake dependency-pinning
discipline as every other cmux release artifact.

## What already exists to build on

Fetched and read directly from `numtide/nix-vm-test` (locked rev
`be5379d18ae1c4ad25d950d9a785008cb5998d69`, matching `flake.lock`):

* `nix-vm-test`'s `overlay.nix` exposes `pkgs.testers.nonNixOSDistros.{debian,ubuntu,fedora,rocky}`.
* `debian/default.nix` and `ubuntu/default.nix` both export:
  * `images` — `lib.mapAttrs fetchImage (importJSON ./images.json).${system}`,
    keyed by version string (`"12"` for Debian, `"24_04"` for Ubuntu — the
    same keys `nix/tests-distro.nix` already calls as
    `nvt.debian."12" { ... }` / `nvt.ubuntu."24_04" { ... }`).
  * `prepareDebianImage` / `prepareUbuntuImage` — takes
    `{ hostPkgs, originalImage, diskSize, extraPathsToRegister }`, resizes
    the image, then runs `virt-customize -a <img> --smp 2 --memsize 256
    --no-network --copy-in <test-driver services> --run <script>` to install
    the nixos-test-driver's backdoor/mount-store/resize services, clear the
    root password, mask `ssh`/serial-getty, and configure DHCP networking
    for boot.
* `nix/tests-distro.nix`'s `injectReleaseAssetIntoImage` (used today for
  Rocky) is the closest existing pattern for "take a base image, copy a
  release artifact into it via `virt-customize --copy-in`, emit a new
  qcow2" — but it only *copies a file in*, it does not install/resolve the
  package, because the real distro tests install the `.deb`/`.rpm` at VM
  **boot** time (inside `generic.makeVmTest`'s scripted QEMU boot, which has
  real usermode-NAT network), not at `virt-customize` bake time (which runs
  `--no-network` and cannot reach `apt-get`/`dnf` mirrors).

## The actual gap (why this isn't a small diff)

A demo image needs cmux **already installed** when the user boots it — no
install step, no network dependency at first boot. That means: boot the
base cloud image for real (with network, so `apt-get install -f` can
resolve the GTK4/WebKit dependency closure — cmux's Ubuntu cloud-image
distro test already notes this closure needs `diskSize = "+8G"` just to
unpack), run the install inside that live boot, then **export the guest's
mutated root disk** as the final artifact.

Every existing use of `nix-vm-test` in this repo (and in `nix-vm-test`
itself) treats the booted VM as an ephemeral **test**: `generic.makeVmTest`
runs a Python test-driver script against a disposable QEMU instance and
produces a pass/fail log, not a exportable post-boot disk image. Baking a
qcow2 with `virt-customize` (`prepareDebianImage`/`prepareUbuntuImage`,
`injectReleaseAssetIntoImage`) is offline-only (`--no-network`) and cannot
run `apt-get install -f` against real mirrors.

Neither existing pattern alone produces "boot this and cmux is already
installed and resolvable." Closing that gap needs one of:

1. A test-driver script that installs cmux inside a `nixosTest`/`vmTest`
   boot as today, but the derivation is changed to copy the guest's
   `/dev/vda`-equivalent disk out to `$out` after the script succeeds
   (nixpkgs' `nixosTest` machinery does not do this by default — the test
   driver's QEMU instance uses a disposable overlay disk; this needs an
   explicit non-disposable disk + an explicit "stop and keep the disk"
   step, which is a nontrivial modification of `generic.makeVmTest`, not a
   parameter it already exposes).
2. Two-phase build: `prepareDebianImage`/`prepareUbuntuImage` to get a
   network-capable base with DHCP configured, then a **separate** qemu boot
   (outside the nix-vm-test test-driver harness — e.g. a raw `qemu-system`
   invocation with `-netdev user` and a serial-console-driven install
   script) that installs the `.deb` and its dependencies over real network,
   shuts the guest down cleanly, and keeps the resulting disk as `$out`.
   This is buildable but needs to be authored and iterated against a real
   `nix build`/QEMU boot to get guest-shutdown timing, serial console
   automation, and dependency-closure disk sizing right — none of which can
   be verified from source reading alone.

Both shapes are real, buildable Nix work; neither is safe to author blind
(no local `nix build`, per this session's NEO FENCE) because correctness
here is entirely about QEMU boot behavior, not text/config shape.

## Proposed shape once buildable

* New `nix/vm/demo-qcow2.nix`, parallel to the existing
  `nix/vm/image-builder.nix`, exposing `demoQcow2 { distro, version,
  debAsset }` built on option 2 above.
* Flake outputs `demo-qcow2-debian12` / `demo-qcow2-ubuntu2404`, each
  producing `cmux-demo-<distro>-<version>.qcow2`.
* `.github/workflows/release-demo-vms.yml` (this pass adds an inert
  skeleton — `workflow_dispatch` only, no tag trigger, targets the
  not-yet-existing flake outputs so it fails closed rather than silently
  doing nothing until they land) builds both, compresses with `qemu-img
  convert -c`, and publishes to a `demo-vms-vX.Y.Z` release — mirroring
  `release-qcow2.yml`'s existing NixOS-variant upload job shape, kept as a
  separate workflow/tag namespace (`demo-vms-v*`) so it doesn't collide
  with `lab-v*` NixOS desktop images or cmux's own `v*` app releases.
* README "Try cmux Linux without installing anything" section (the ticket's
  step 4 one-liner) gets added in the same PR that actually ships the
  images — adding it now, before the artifacts exist, would be a dead link.
* Fedora 42 / Rocky 10 follow-up (ticket step 5) reuses the same shape once
  the Debian/Ubuntu path is proven, since `nix-vm-test` already exposes
  `fedora`/`rocky` with the identical `images` + `prepare*Image` shape.
