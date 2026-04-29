# Distro Testing Readiness Plan

This document turns the current Linux delivery state into an explicit readiness
plan for distro testing, QEMU/KVM validation, automated testing, and the
`cmux` vs `lmux` naming question.

Use it with:

- `docs/program-status.md`
- `docs/linux-program-plan.md`
- `docs/linux-packaging-cd-plan.md`
- `docs/linux-graphical-qa-machine-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-validation-checklist.md`
- `docs/flakehub-qa-ownership-notes.md`

## Snapshot

As of 2026-04-29:

- hosted Linux CI is already green on `Ubuntu 24.04`, `Fedora 42`, `Rocky 10`,
  `Debian 12` baseline, and `Arch`
- tagged Linux releases already build signed multi-arch `DEB`, `RPM`, and
  tarball assets
- release-gated KVM package validation now executes real `.sandboxed` VM tests
  for `Ubuntu 24.04`, `Fedora 42`, and the dedicated `Rocky 10`
  terminal-first RPM path before upload
- `Debian 12` remains a baseline/no-WebKit lane; the current broad-feature
  Ubuntu-family `DEB` is diagnostic there until a separate Debian baseline
  artifact or backports policy is chosen
- release run `25087301829` proved the exact signed Fedora 42 RPM and Rocky 10
  terminal-first RPM in KVM; the upload was blocked by the Debian diagnostic
  mismatch before Ubuntu could run
- `numtide/nix-vm-test#172` merged on 2026-04-22 with `Fedora 42` and
  `Rocky 10.1` image support, so upstream image availability is no longer the
  blocker
- the repo now pins upstream `numtide/nix-vm-test` at `be5379d`
- direct QA proof is still weaker than the build and packaging surface
- the biggest remaining Linux risk is proof depth and parity honesty, not basic
  architecture

## Target Matrix

| Target | Current build proof | Current KVM / QEMU proof | Current release gating | Current direct QA | Target posture |
|---|---|---|---|---|---|
| `Ubuntu 24.04` | hosted CI green | yes | yes | still needs one recorded broad-feature pass | Tier A broad-feature |
| `Fedora 42` | hosted CI green, RPM builds on Fedora 42 | yes; first exact-artifact proof recorded in run `25087301829` | yes | still needs one recorded broad-feature pass | Tier A broad-feature |
| `Debian 12` | hosted CI green with baseline `-Dno-webkit` lane | baseline automation exists; broad-feature release `DEB` is diagnostic until artifact taxonomy is fixed | diagnostic only | still needs one explicit browser/WebAuthn status record | Tier B baseline |
| `Rocky 10` | hosted CI green, constrained build posture is real | yes; first exact-artifact terminal-first proof recorded in run `25087301829` | yes, when `rpmRocky` exists | still needs one direct terminal-first report | Tier C constrained |
| `arm64` Linux artifacts | multi-arch release builds exist | not yet | not yet | none | follow-on after x86_64 proof |

## Automation Surfaces

### 1. Hosted build matrix

Current sources:

- `.github/workflows/linux-ci.yml`
- `.github/workflows/release-linux.yml`

What this already proves:

- dependency install works on the intended build distros
- `cmux-linux`, `cmuxd`, `libghostty`, and the Zig vendor libraries build
- signed `DEB`, `RPM`, and tarball release artifacts are produced

What it still does not prove:

- exact fresh-install behavior on every target distro
- browser, notification, lock, and WebAuthn behavior on real desktop sessions
- arm64 runtime parity

### 2. KVM / QEMU package-install validation

Current sources:

- `.github/workflows/test-distro.yml`
- `nix/tests-distro.nix`
- `.github/workflows/release-linux.yml`

What exists now:

- `Ubuntu 24.04` `DEB` install validation
- `Fedora 42` `RPM` install validation
- `Rocky 10` terminal-first validation through a dedicated `rpmRocky` asset
- `Debian 12` diagnostic validation of the current `DEB`, with failure treated
  as evidence for the pending baseline artifact decision rather than a
  broad-feature release blocker
- current checks resolve to `.sandboxed` VM runs rather than driver-only
  derivations
- release-time validation of the exact x86_64 `DEB` and `RPM` assets before
  upload

What is still missing:

- a separate Debian 12 baseline/no-WebKit package artifact, or an explicit
  Debian backports policy for the broad-feature `DEB`
- arm64 KVM validation

### 3. Socket and control-plane automation

Current sources:

- `.github/workflows/test-socket.yml`
- `scripts/run-socket-tests.sh`
- `Jesssullivan/cmux#216`

What exists now:

- 123 `tests_v2` test files on disk
- 28 stable Linux baseline tests
- 1 gated phase-1 candidate test running as a non-fatal observation

What is still missing:

- broader command coverage on Linux
- browser automation beyond the current limited socket surface
- direct automation for WebAuthn, notifications, and lock integration

### 4. Graphical human QA

Current sources:

- `docs/linux-graphical-qa-machine-plan.md`
- `docs/linux-qa-intake.md`
- `docs/linux-validation-checklist.md`

Current decision:

- physical standard installs and normal user-managed VMs are the source of truth
  for public graphical QA
- `honey` KVM/QEMU remains useful for package proof and private lab work
- NixOS desktop VM/QCOW surfaces can support internal demos and future visual
  automation, but they do not yet replace distro-specific graphical testing

Current machine-pool recommendation:

- Ubuntu 24.04 GNOME and Fedora 42 GNOME for Tier A broad-feature proof
- Fedora 42 KDE Plasma as the first DE-variance target
- Debian 12 GNOME first, with Xfce optional later
- Rocky 10.1 GNOME for terminal-first proof
- CachyOS KDE Plasma as the primary Arch-family rolling target
- Omarchy Hyprland as exploratory Arch/tiling coverage only
- Linux Mint Cinnamon as the first Ubuntu-family community target
- NixOS GNOME/Sway/Hyprland for internal lab and early Nix reports

## Required Readiness Moves

### 1. Finish the x86_64 target matrix

This is the current release-critical gap.

Required outcome:

1. keep `Ubuntu 24.04` green for the broad-feature `DEB`
2. keep `Fedora 42` KVM proof green and visible in CI
3. keep real `Rocky 10` terminal-first proof green when `rpmRocky` exists
4. decide and implement the Debian 12 baseline artifact path

Recommended owned path:

1. keep `Rocky 10` only when the artifact under test matches the constrained
   distro promise
2. treat Debian 12 broad-feature `DEB` results as diagnostic until a baseline
   artifact exists
3. keep the former `Jesssullivan/nix-vm-test` carry reason visible in
   `Jesssullivan/cmux` issues, Tinyland Linear, and
   `docs/flakehub-qa-ownership-notes.md` as historical context

### 2. Record one direct proof pass per distro tier

The repo has more build proof than user-behavior proof.

Required direct passes:

- `Ubuntu 24.04` broad-feature
- `Fedora 42` broad-feature
- `Debian 12` explicit baseline with browser/WebAuthn status
- `Rocky 10` terminal-first

Required evidence:

- package filename and version
- distro image or host version
- pass/fail notes for terminal, split, socket/API, browser, notification, and
  lock behavior where relevant

### 3. Expand automated Linux socket coverage

Current baseline is intentionally conservative.

Near-term target:

- keep the newly promoted baseline green
- keep the baseline small enough to trust
- move Linux socket coverage materially above the current 28-test stable floor

Follow-on target:

- add dedicated coverage for high-value Linux parity commands as they land
- avoid claiming socket parity until the Linux host callbacks and structural
  verbs are real

### 4. Separate ship blockers from follow-on parity work

Not every Linux gap should block distro testing readiness.

Current release-facing blockers:

- first green CI evidence for the new `Fedora 42` fresh-install VM lane
- first green CI evidence for the new `Rocky 10` terminal-first VM lane
- one direct QA pass on each distro tier
- truthful browser/WebAuthn claims per distro tier

Current broad-feature blockers:

- Linux WebAuthn bridge completion
- browser proof on `Ubuntu 24.04` and `Fedora 42`
- Linux socket/control-plane completion for the most user-visible verbs

Current follow-on lanes:

- session restore promotion
- `cmux-term` headless runtime
- Tailnet direct remote transport
- arm64 KVM proof

## Missing Feature Parity

### Highest-value gaps

These are the Linux gaps most likely to affect real distro-readiness claims:

1. WebAuthn remains `unsupported` on Linux because the bridge handler is still
   stubbed
2. socket/control-plane remains `partial` because several structural verbs and
   host callbacks are still incomplete
3. browser status is still distro-specific and not yet proven broadly enough on
   Tier A distros
4. session restore is still `partial`
5. `cmux-term` is still `unsupported`

### Parity interpretation

- Tier A should aim for the broadest Linux-native `cmux` feature set
- Debian 12 should stay honest as a baseline until browser/WebAuthn proof is
  explicit
- Rocky 10 should stay terminal-first unless a real browser packaging path is
  proven

## FlakeHub And Ownership Read

Current owned reality:

- both a personal FlakeHub subscription and a `tinyland-inc` organization
  subscription exist
- this improves optional cache and flake publication flexibility
- it does not change the repo ownership rule

Interpretation:

- `Jesssullivan/cmux` can remain the canonical personal fork while still using
  the personal subscription where useful
- `tinyland-inc/lab` remains the right shared builder and org-cache lane
- distro readiness should be driven by proof and harness coverage, not by which
  FlakeHub subscription happens to be available

## `cmux` vs `lmux`

### Options

1. keep `cmux` everywhere
2. keep `cmux` as the product and repo name, but use Linux-specific wording in
   docs and package metadata
3. rename the Linux client or package to `lmux`

### Current recommendation

Keep `cmux` as the product, repo, binary, and package name for now.

Reasoning:

- the repo is already cross-platform and the Linux work is an extension of the
  same product, not a separate project
- changing the binary or package name now would add migration and distribution
  churn right when the real blocker is proof depth
- the existing user confusion risk is smaller than the cost of splitting names
  before the distro story is stable

### Revisit triggers

Only reopen a rename as an active work item if at least one of these becomes
true:

1. distro packaging requires `cmux` and a Linux-specific variant to coexist as
   distinct installable products
2. Linux intentionally becomes a materially different product surface
3. the release and docs story becomes actively confusing under the shared name
4. there is a concrete migration plan for binary names, package names, and user
   documentation

Until then:

- keep `#76` open
- keep it explicitly non-blocking
- use wording like `Linux-native cmux` in docs when clarity helps

## Ordered Next Actions

1. rerun release-gated proof after the Debian diagnostic posture change so
   Ubuntu/Fedora/Rocky exact-artifact gates can upload signed assets
2. record one direct QA pass for `Ubuntu 24.04`, `Fedora 42`, `Debian 12`, and
   `Rocky 10`
3. decide whether Debian 12 gets a separate no-WebKit `DEB` or a documented
   backports-based install path
4. promote Linux socket-test candidates into baseline only after green proof
5. keep `WebAuthn`, socket parity, and browser claims honest in the matrix
6. defer `lmux` renaming work unless the revisit triggers become real
