# Linux Packaging And Release Plan

This document tracks Linux artifact parity, distro-install validation, and
package/release CI/CD for `cmux`.

Use it with:

- `docs/linux-program-plan.md`
- `docs/linux-validation-checklist.md`
- `docs/linux-parity-matrix.md`
- `docs/flakehub-qa-ownership-notes.md`
- `docs/program-status.md`

## Current State

As of 2026-04-29:

- hosted Linux CI is green across `Ubuntu 24.04`, `Fedora 42`, `Rocky 10`,
  `Debian 12` baseline, `Arch`, and the vendor-library lane
- self-hosted distro package-install tests now execute real `.sandboxed` VM
  runs for `Ubuntu 24.04`, `Fedora 42`, and dedicated `Rocky 10`
  terminal-first release artifacts
- the release workflow now builds a separate Rocky 10 terminal-first RPM and
  wires it into the release-gated VM validator
- release run `25087301829` proved the exact signed Fedora 42 and Rocky 10 RPMs
  in KVM
- release run `25088831284` built and signed all Linux artifacts, re-proved
  Fedora 42 and Rocky 10 in KVM, then failed before upload because the Ubuntu
  24.04 cloud image ran out of disk while unpacking the broad-feature `DEB`
  dependency closure; PR `#278` adds Ubuntu VM disk expansion for that gate
- release run `25090142397` built and signed all Linux artifacts, passed the
  Fedora 42, Rocky 10, and Ubuntu 24.04 exact-artifact KVM gates, and uploaded
  the Linux package assets to `lab-v0.75.0`
- the release workflow now stages a separate Debian 12 baseline/no-WebKit
  `DEB` as `cmux_<version>+deb12_<arch>.deb`; first release proof for that
  artifact is still pending
- Linux release automation builds:
  - Ubuntu-family broad-feature `DEB`
  - Debian 12 baseline/no-WebKit `DEB`
  - `RPM`
  - generic Linux tarball
- tagged Linux releases now validate the just-built `DEB`/`RPM` artifacts on
  the self-hosted KVM lane before uploading Linux assets to GitHub Releases
- `numtide/nix-vm-test#172` merged on 2026-04-22 with `Fedora 42` and
  `Rocky 10.1` images; the repo now pins upstream `numtide/nix-vm-test` at
  `be5379d`
- Flatpak is built in CI, but is not yet part of the release-upload path
- `Jesssullivan/cmux` intentionally uses Magic Nix Cache rather than FlakeHub
  Cache
- `tinyland-inc/lab` remains the active FlakeHub-heavy org lane and the main
  self-hosted Linux builder experiment surface
- `Jesssullivan/nix-vm-test` exists as the previous owned contingency fork, but
  it is no longer the pinned flake input surface

## Current Artifact Surface

### 1. Hosted CI build matrix

Primary workflow:
- `.github/workflows/linux-ci.yml`

What it proves today:
- source checkout and Zig toolchain bootstrapping
- Linux dependency installation
- `libghostty` build
- `cmux-linux` build
- Linux vendor-library build/test
- desktop/metainfo validation
- container/headless static smoke

What it does not prove:
- fresh package install from the exact release artifacts
- distro-native dependency resolution in a clean VM
- release-asset upload correctness

### 2. KVM distro-install tests

Primary surfaces:
- `.github/workflows/test-distro.yml`
- `nix/tests-distro.nix`

What it proves today:
- actual `.deb`/`.rpm` artifacts can be installed in QEMU guests
- package manager dependency resolution runs in a real distro image
- runtime linker checks can be performed after install
- the current checks execute the VM runs themselves, not just the driver
  derivations

Current limits:
- runs on trusted push/manual only, not on pull requests
- still pinned to a checked-in release artifact manifest
- `Debian 12` has a distinct baseline artifact path in the release workflow,
  but still needs first release-candidate proof before closing TIN-745
- `Rocky 9` is still a temporary RPM-path proxy
- the remaining blocker is first proof for the new Debian baseline artifact,
  not cache account shape or VM-image availability

### 3. Linux release workflows

Primary surfaces:
- `.github/workflows/release-linux.yml`
- `.github/workflows/fork-release.yml`

What they do today:
- build Linux release packages on tag push
- validate the just-built `DEB`/`RPM` artifacts in fresh distro VMs before Linux
  upload
- upload Linux assets to the matching GitHub Release
- upload macOS assets separately through the fork release workflow

Current limits:
- Linux release gating currently covers `Ubuntu 24.04`, `Fedora 42`,
  `Rocky 10`, and, after this workflow change, the dedicated Debian 12
  baseline `DEB`; `arm64` remains outside the gated VM matrix
- Debian 12 still needs a fresh release-candidate proof before its Linear lane
  can be marked complete

### 4. Flatpak

Primary surfaces:
- `.github/workflows/flatpak-ci.yml`
- `flatpak/com.jesssullivan.cmux.yml`

What it proves today:
- manifest resolves and builds in CI

What it does not do yet:
- publish a user-facing Flatpak artifact
- serve as the release-grade browser-capable cross-distro channel

## Artifact Classes

The release story should be explicit about which artifact is intended for which
distro class.

### Broad-feature artifacts

These are the artifacts that can legitimately target browser-capable Linux
desktops:

- Ubuntu-family `DEB`
- Fedora-family `RPM`
- Flatpak

### Baseline artifact

This is the artifact lane that proves package/runtime viability without implying
full browser parity:

- Debian 12 no-WebKit `DEB` install validation

Current interpretation:
- the hosted Debian 12 build lane already proves the source can build
  `-Dno-webkit=true`
- the release workflow now emits `cmux_<version>+deb12_<arch>.deb` for Debian
  12 baseline package/runtime proof
- the broad-feature Ubuntu-family `DEB` should not be treated as Debian
  baseline proof

### Constrained artifact

This is the artifact lane for terminal-first Linux support:

- Rocky 10 runtime/package path

Current interpretation:
- Rocky should not inherit broad-feature claims by accident
- Flatpak may ultimately be the cleanest full-feature answer for Rocky-class
  systems if browser support matters there

## Current Problems

### 1. Artifact metadata still overstates Linux parity

Current Linux package metadata has claimed:

- WebAuthn support
- session persistence/restore

Those claims need to follow the real Linux implementation state, not the
broader program intent.

### 2. Runtime dependency declarations need a distro-specific audit

The release workflows build browser-capable binaries on broad-feature distros.
That means runtime dependencies, especially for WebKitGTK-capable builds, need
to be audited carefully instead of hand-waved.

Current read:

- the shipped Linux binary links `libwebkitgtk-6.0.so.4`, so the broad-feature
  `DEB`/`RPM` lanes should declare WebKitGTK explicitly
- the current RPM requirement on `webkitgtk6.0` is honest for Fedora 42, but it
  means the same RPM is not a truthful default artifact for Rocky 10
- the branch now addresses that by producing a separate no-WebKit Rocky 10 RPM
  instead of pretending one RPM covers both distro classes
- the branch now addresses the Debian 12 tension by producing a separate
  no-WebKit `+deb12` package instead of treating the Ubuntu broad-feature `DEB`
  as Debian proof
- the shipped Linux binary does not currently link `libsecret` or `libnotify`,
  so those should not be declared as package requirements just because helper
  libraries exist elsewhere in the tree

### 3. Release tests are pinned to a checked-in artifact manifest

`nix/tests-distro.nix` now reads a checked-in release manifest by default, with
an optional local override manifest path for validating a specific release tag.
The workflow-generated override intentionally fails if a release exposes more
than one matching `DEB` or `RPM`, so artifact taxonomy drift shows up as an
explicit packaging decision instead of being hidden behind `head -1`. That is
better than inline hardcoding, but it is still not yet a clean end-to-end
release pipeline for the newest just-built artifacts.

### 4. Fresh-install release gating is still incomplete

The current shape is:

1. build release artifacts
2. install the just-built `DEB`/`RPM` artifacts in the current KVM distro matrix
3. upload Linux assets only after that proof passes

The desired shape is:

1. build release artifacts
2. install those exact artifacts in fresh VMs across the intended distro matrix
3. upload only after install proof passes

## Builder And Cache Posture

### `Jesssullivan/cmux`

Current posture:

- hosted GitHub Actions for most Linux CI
- self-hosted KVM lane for fresh distro-install tests
- Magic Nix Cache, not FlakeHub Cache

Rationale:

- this repo is a personal fork and should remain healthy without forcing
  ownership changes for cache tooling

### `Jesssullivan/nix-vm-test`

Current posture:

- personal fork of `numtide/nix-vm-test`
- previous fallback for `Fedora 42` and `Rocky 10.1` image support
- no open pull requests
- issues disabled
- superseded by upstream `numtide/nix-vm-test#172`
- no longer the cmux pinned flake input

Interpretation:

- this is an owned contingency surface for future image or harness carry work
- it is not the canonical planning surface for distro QA decisions
- any divergence must be tracked back in `Jesssullivan/cmux` issues and Tinyland
  Linear

### `tinyland-inc/lab`

Current posture:

- active FlakeHub Cache lane
- `honey`-backed self-hosted Linux runner experiments and throughput work

Interpretation:

- `lab` is the place to refine org-owned Linux builder strategy
- `cmux` should consume those lessons where useful, but not inherit its
  ownership/cache policy

## Recommended Delivery Pipeline

### Phase 1: Truthful artifacts

Before expanding release reach:

1. align Linux package/license metadata with the actual project license
2. remove Linux artifact claims that are not yet true end-to-end
3. audit runtime dependencies for each package class

### Phase 2: Exact-artifact install validation

For tagged Linux releases:

1. build `DEB`, `RPM`, and tarball artifacts
2. generate a local artifact manifest for that release candidate
3. install those exact artifacts in fresh VMs
4. fail the Linux upload if install/runtime validation fails

### Phase 3: Distro-matrix completion

Expand fresh-install proof to:

1. `Ubuntu 24.04` DEB
2. `Debian 12` DEB
3. `Fedora 42` RPM and keep it green
4. `Rocky 10` runtime/package path with a truthful terminal-first artifact

### Phase 4: Flatpak decision

Decide whether Flatpak is:

- build-only validation
- or a first-class published Linux artifact

If it becomes first-class, it should be reflected in:

- release notes
- artifact taxonomy
- distro support policy

## Near-Term Priority Order

1. finish signed-package install docs:
   - apt/rpm verification commands
   - supported distro tier wording
   - clear Rocky 10 terminal-first caveat
2. finish distribution runbooks:
   - Flathub submission handoff
   - AUR `PKGBUILD` scaffold
   - COPR spec scaffold
3. fix Linux artifact truth:
   - license fields
   - package descriptions
   - parity claims
4. keep Fedora 42 release-gated proof green and record the first green Rocky 10
   constrained-distro run
5. audit runtime dependency declarations for the broad-feature package lanes
6. decide whether Flatpak becomes a first-class published artifact

## Success Criteria

This lane is healthy when all of the following are true:

1. Linux artifacts describe what Linux actually supports today
2. fresh-install validation uses the exact artifacts being released
3. distro support tiers map cleanly to artifact types
4. release upload does not outrun package-install proof
5. builder/cache posture is explicit and does not distort repository ownership
