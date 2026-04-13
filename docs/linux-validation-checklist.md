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

## Tier A: Broad-Feature Distros

Targets:

- Ubuntu 24.04
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

## Tier B: Package / Runtime Baseline

Target:

- Debian 12

Required proof:

### 1. Package install

- package installs successfully
- `cmux` binary is on `PATH`
- runtime dependencies resolve

### 2. Runtime launch

- app launches without immediate crash
- terminal surface appears
- initial workspace is interactive

### 3. Terminal and socket baseline

- terminal surface is interactive
- split and focus flows work
- basic socket/API queries return expected shape

### 4. Browser status

- record browser and WebAuthn status explicitly
- do not assume Debian 12 is already full-feature just because package install passes

## Tier C: Constrained Distros

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
- at least one Tier A distro, Debian 12 baseline, and Rocky 10 pass the terminal/split smoke

### Socket/API control plane

Promote to `full` when:
- command coverage is verified on a Tier A distro
- `surface.send_text`, `surface.read_text`, and the core structural operations are implemented and exercised
- Linux action/clipboard host callbacks are wired for the validated workflow
- no Linux-specific routing regressions remain open for the validated surface

### Browser panel

Promote to `full` only for Tier A when:
- open, navigate, focus, devtools, and find all work on validated distros

Keep `distro-specific` while:
- Debian 12 browser status is not yet fully proven
- Rocky remains terminal-first

### WebAuthn

Promote to `full` only when:
- the bridge request/response path is implemented end-to-end, not just installed
- a real hardware-backed ceremony succeeds on a validated Tier A distro

Current note:
- [webauthn_bridge.zig](/Users/jess/git/cmux/cmux-linux/src/webauthn_bridge.zig:61) still has a stub message handler

### Notifications and lock integration

Promote to `full` when:
- desktop notification and logind lock/unlock behavior are manually validated

### Session restore

Promote to `full` only when:
- restore is implemented and proven

Current note:
- [session.zig](/Users/jess/git/cmux/cmux-linux/src/session.zig:245) currently returns `false` for restore

### Headless / server mode (`cmux-term`)

Promote to `partial` when:
- the binary initializes a real terminal runtime
- a Unix socket control path exists
- PTY/shell lifecycle exists

Promote to `full` only when:
- a real SSH/server workflow is validated end-to-end

Current note:
- [main_headless.zig](/Users/jess/git/cmux/cmux-linux/src/main_headless.zig:23) is still placeholder-only

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
- Debian 12 baseline automation exists, but broader browser/WebAuthn status still needs explicit proof
- Linux WebAuthn bridge install exists, but the message-handling path is still stubbed
- several Linux socket/control-plane verbs remain stubs, including `surface.send_text`, `surface.read_text`, `pane.break`, `pane.join`, `surface.move`, and `surface.reorder`
- Linux action and clipboard callbacks are still mostly no-op in the current host layer
- browser/WebAuthn validation needs a clearly recorded Tier A proof path
- session restore is not yet ready for promotion
- `cmux-term` is still placeholder-only
- fresh package-install proof is not PR-gated today; the KVM workflow runs on push/manual on the self-hosted runner
