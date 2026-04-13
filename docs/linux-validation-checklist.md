# Linux Validation Checklist

This checklist turns the Linux program plan into concrete proof work.

Use it alongside:

- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
- `nix/tests-distro.nix`

## Validation Rules

- do not promote a capability from `partial` to `full` without proof
- prefer artifact-level proof over source inspection
- record distro-specific constraints explicitly
- treat Rocky 10 as terminal-first unless browser support is proven in a real
  packaging path

## Tier A: Full-Feature Distros

Targets:

- Ubuntu 24.04
- Debian 12
- Fedora 42

Required proof on each distro:

### 1. Package install

- package installs successfully
- `cmux` binary is on `PATH`
- runtime dependencies resolve

Reference:
- [nix/tests-distro.nix](/Users/jess/git/cmux/nix/tests-distro.nix:1)

### 2. Runtime launch

- app launches without immediate crash
- terminal surface appears
- initial workspace is interactive

### 3. Terminal/split smoke

- create additional surface
- split right and split down
- move focus between panes
- close surfaces and confirm layout remains valid

### 4. Socket/API smoke

- basic socket/API commands work
- workspace and surface queries return expected shape
- pane/surface actions route correctly

Suggested coverage source:
- `tests_v2/`

### 5. Browser smoke

- open browser panel
- navigate to a URL
- query current URL
- focus webview
- use browser find
- open and close devtools

### 6. WebAuthn smoke

- run one real hardware-backed ceremony where practical
- confirm JS bridge path and device access work

### 7. Notifications and lock integration

- send notification and confirm desktop delivery
- verify session lock/unlock hooks do not break terminal state

### 8. Session persistence

- save a session
- relaunch and confirm current restore behavior matches the documented status

## Tier B: Constrained Distros

Target:

- Rocky 10

Required proof:

### 1. Package/runtime path

- install path works
- binary launches
- terminal surface is interactive

### 2. Terminal-first workflow

- new surface
- splits
- focus movement
- socket/API smoke
- session file path works as expected

### 3. Browser status

- document browser status explicitly
- if using `-Dno-webkit`, confirm browser commands fail clearly and predictably
- if a Flatpak/browser path is validated later, record that separately

## Promotion Criteria By Capability

### Terminal surfaces and split tree

Promote to `full` when:
- at least one Tier A distro and Rocky 10 pass the terminal/split smoke

### Socket/API control plane

Promote to `full` when:
- command coverage is verified on a Tier A distro
- no Linux-specific routing regressions remain open for the validated surface

### Browser panel

Promote to `full` only for Tier A when:
- open, navigate, focus, devtools, and find all work on validated distros

Keep `distro-specific` while:
- Rocky remains terminal-first

### WebAuthn

Promote to `full` only when:
- a real hardware-backed ceremony succeeds on a validated Tier A distro

### Notifications and lock integration

Promote to `full` when:
- desktop notification and logind lock/unlock behavior are manually validated

### Session restore

Promote to `full` only when:
- restore is implemented and proven

Current note:
- [session.zig](/Users/jess/git/cmux/cmux-linux/src/session.zig:245) currently returns `false` for restore

## Existing Automation

- distro package tests: [nix/tests-distro.nix](/Users/jess/git/cmux/nix/tests-distro.nix:1)
- distro workflow: [.github/workflows/test-distro.yml](/Users/jess/git/cmux/.github/workflows/test-distro.yml:1)
- Linux CI: [.github/workflows/linux-ci.yml](/Users/jess/git/cmux/.github/workflows/linux-ci.yml:1)
- GPU smoke helper: [smoke-test-gpu.sh](/Users/jess/git/cmux/scripts/smoke-test-gpu.sh:1)
- CI smoke helper: [smoke-test-ci.sh](/Users/jess/git/cmux/scripts/smoke-test-ci.sh:1)

## Current Gaps

- Fedora 42 is covered in container build validation, but not yet in
  `nix/tests-distro.nix` package-install VM coverage
- Rocky 10 is covered in container build validation, but package-install VM
  coverage still lags because `nix-vm-test` image support is not there yet
- Rocky 9 is still being used as an RPM-path proxy and should be treated as
  temporary coverage, not as the target distro itself
- Rocky 10 tracking and repo issue wording need to match current reality
- browser/WebAuthn validation needs a clearly recorded Tier A proof path
- session restore is not yet ready for promotion
