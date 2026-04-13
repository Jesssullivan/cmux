# Linux Program Plan

This document translates the Linux effort from a research project into an
execution program.

The goal is straightforward:

Build, package, validate, and ship native Linux `cmux` on a practical distro
matrix while preserving the feature work that already exists in the fork.

## Program Goal

Deliver a native Linux `cmux` that is:

- usable for real terminal-first workflows
- feature-complete on the main supported desktop distros
- explicit about constrained-distro limitations
- backed by repeatable packaging and CI validation

## Support Tiers

### Tier A: Broad-Feature Linux

These are the distros where Linux-native `cmux` should aim for the broadest
feature set, including browser-panel work.

| Distro | Why it matters | Expected capability |
|---|---|---|
| Ubuntu 24.04 | mainstream LTS baseline | full feature target |
| Fedora 42 | modern GNOME/Wayland baseline | full feature target |

### Tier B: Package / Runtime Baseline

These are important supported distros where package install and runtime behavior
should be proven explicitly, even if the full browser/WebAuthn story is not yet
represented in the same automation lanes as Tier A.

| Distro | Why it matters | Expected capability |
|---|---|---|
| Debian 12 | stable deb-family packaging baseline | package + runtime baseline; browser status must be recorded explicitly |

### Tier C: Constrained Linux

These are supported, but not necessarily full-parity.

| Distro | Constraint | Expected capability |
|---|---|---|
| Rocky 10 | system WebKitGTK path is not a normal base assumption | terminal-first target |

## Capability Classes

Every Linux feature should be tracked in one of four states:

| State | Meaning |
|---|---|
| `full` | implemented and validated on the target distro class |
| `partial` | implemented but missing some behavior or validation |
| `unsupported` | not present yet |
| `distro-specific` | supported only on some distros or packaging modes |

## Critical Workstreams

### 1. Platform Hygiene

Goal:
- keep the Linux effort grounded in reproducible dependencies and current docs

Scope:
- fork pin hygiene
- submodule ancestry
- carried patch ledgers
- issue grooming
- component portfolio visibility

Blockers:
- stale `ghostty` fork state documentation
- stale Linux/Rocky issue descriptions

### 2. Linux Parity

Goal:
- establish what Linux-native `cmux` already does and what still needs work

Core domains:
- terminal and split tree
- tabs and workspace model
- socket/API parity
- browser panel
- WebAuthn
- cookies
- devtools and find
- notifications
- session restore
- remote workflows

Required output:
- a maintained parity matrix in `docs/linux-parity-matrix.md`
- a validation checklist in `docs/linux-validation-checklist.md`

### 3. Distro Validation

Goal:
- prove the Linux app works on the distros users will actually run

Validation layers:
- package install
- runtime launch
- socket/API smoke
- browser/WebAuthn smoke where supported
- GPU/UI smoke on `honey`

### 4. Packaging

Goal:
- make installation paths match distro reality

Primary packaging lanes:
- Nix
- Flatpak
- DEB
- RPM

Important rule:
- Rocky support should not be blocked on system-package browser parity

### 5. Remote And Fleet Fit

Goal:
- ensure Linux-native `cmux` works in the real multi-host environment

Scope:
- `cmuxd-remote`
- SSH-driven remote flows
- Tailnet-ready design
- fleet deployment assumptions

This is important, but it is not the first blocker for distro validation.

## Current Blockers

### 1. Rocky browser availability

The Linux tree supports building without WebKitGTK via `-Dno-webkit`.
That means Rocky must currently be treated as a constrained target, not a
full-parity browser target.

### 2. Planning drift

The Linux epic and Rocky tracking issues need to reflect the current codebase
and the current distro support reality.

### 3. Dependency hygiene

The `ghostty` fork state needs to be made reproducible before more Linux work
stacks on top of it.

## Execution Order

### Phase 1: Baseline Hygiene

1. reconcile `ghostty` pin and docs
2. groom Linux and distro-tracking issues
3. write and maintain the parity matrix

### Phase 2: Tier A Validation

1. validate Ubuntu 24.04
2. validate Fedora 42
3. confirm browser/WebAuthn behavior where available

### Phase 3: Tier B Validation

1. validate Debian 12 package install path
2. validate Debian 12 runtime and socket baseline
3. record Debian 12 browser/WebAuthn status explicitly

### Phase 4: Tier C Validation

1. validate Rocky 10 install/runtime path
2. validate terminal-first behavior on Rocky
3. document browser constraints explicitly

### Phase 5: Packaging And Release Confidence

1. tighten CI coverage
2. ensure packages match actual install paths
3. keep release artifacts and distro tests aligned

## Acceptance Criteria

The Linux program should only be called healthy when all of the following are
true:

1. Ubuntu 24.04 and Fedora 42 pass package install and runtime smoke.
2. Ubuntu 24.04 and Fedora 42 have explicit browser/WebAuthn status.
3. Debian 12 passes package install and runtime baseline validation, and its browser status is recorded explicitly.
4. Rocky 10 passes terminal-first validation with limitations documented.
5. dependency pins are reproducible and documented.
6. the issue tracker reflects current reality instead of old research states.

## Non-Goals

- forcing identical implementation choices across macOS and Linux
- blocking Linux progress on immediate upstream correspondence
- treating every distro as full-parity from day one

The program succeeds by being explicit, reproducible, and validated.
