# Program Status

This is the short operational status for the `cmux` program.

Use it as the top-level readout for current health, blockers, and next actions.
It complements, rather than replaces:

- `docs/fork-landscape.md`
- `docs/component-portfolio.md`
- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-validation-checklist.md`
- `docs/tracker-refresh-notes.md`

## Snapshot

As of 2026-04-13:

- core repo health is good: the fork is ahead of upstream, recent CI is mostly
  green, and the Linux branch is proving real distro/container coverage instead
  of speculative design
- fork hygiene is materially better: the `ghostty` pin is now reachable from
  canonical fork `main`, and the carried package graph is mostly reproducible
- Linux implementation health is medium-good: `cmux-linux` is broad and real,
  but validation still lags implementation
- tracker health is medium: the remaining open issues are valid, but several
  issue bodies still describe an older phase of the project
- packaging health is medium: Homebrew is slightly behind, and Linux package
  proof is still uneven across the distro matrix

## Current Critical Path

### 1. Linux distro proof

The project is no longer blocked on Linux architecture. It is blocked on
repeatable proof.

Priority order:

1. `Ubuntu 24.04` broad-feature validation
2. `Fedora 42` broad-feature validation
3. `Debian 12` package/runtime baseline with explicit browser status
4. `Rocky 10` terminal-first validation

Primary references:

- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-validation-checklist.md`

### 2. Tracker hygiene

The main planning risk is stale tracker language, not missing planning docs.

Open issues that still need refresh:

- `#55` Linux umbrella should be reframed as a program/status epic
- `#76` naming RFC should be explicitly non-blocking
- `#187` Rocky 10 needs updated GA/automation language
- `#199` should stay parallel to Linux delivery
- `#201` should stay clearly separate from distro validation

Draft update text is already prepared in:

- `docs/tracker-refresh-drafts.md`

### 3. Explicit parity promotion

Capabilities must not be promoted based on source presence alone.

The biggest remaining parity gaps are:

- browser/WebAuthn proof on Tier A distros
- explicit browser/WebAuthn status recording on Debian 12
- terminal-first proof on Rocky 10
- session restore staying below `full` until restore is actually proven

## Current Automation Coverage

### Linux CI container/build coverage

Current branch coverage includes:

- `Fedora 42`
- `Rocky 10`
- `Debian 12` baseline, `-Dno-webkit`
- `Arch Linux`
- hosted `Nix flake check`
- Linux vendor-library build/test lane

This is useful build/static/runtime-baseline evidence, but it is not the same
as package-install proof.

### Distro package-test VM coverage

Current `test-distro` coverage includes:

- `Ubuntu 24.04`
- `Debian 12`
- `Rocky 9` as the current RPM-path proxy

Current gap:

- `Fedora 42` and `Rocky 10` VM package-install proof still lag because
  `nix-vm-test` coverage is not there yet

## Dependency And Package Health

| Component | Status | Current read |
|---|---|---|
| `ghostty` | `yellow` | highest-churn dependency, but fork-main ancestry is repaired |
| `vendor/bonsplit` | `green` | low-risk, close to upstream |
| `vendor/ctap2` | `green` | repo hygiene is healthy; real Linux/WebAuthn proof is still needed |
| `vendor/zig-keychain` | `green` | healthy; distro-level secret-service validation still needed |
| `vendor/zig-crypto` | `green` | healthy, not a delivery blocker |
| `vendor/zig-notify` | `green` | healthy; Linux notification proof still needed |
| `homebrew-cmux` | `yellow` | behind `origin/main` by 2 commits; not a Linux blocker |

For live ancestry and worktree checks:

```bash
./scripts/report-fork-health.sh
```

## Open Tracker Map

As of 2026-04-13, the public fork tracker is small and focused:

- `#55` `Epic: De-Attestation & Linux Porting Roadmap`
- `#76` `RFC: Linux client naming — cmux vs lmux`
- `#187` `ci(distro): Rocky 10 — track upstream nix-vm-test support`
- `#199` `audit: fork landscape, novel libraries, and upstream PR opportunities`
- `#201` `feat(cmuxd-remote): add TCP listener mode for Tailnet direct connections`

Interpretation:

- `#55` and `#187` are the tracker items most in need of refresh
- `#199` and `#201` are real, but parallel
- `#76` is intentionally non-blocking

## Current Non-Blockers

These lanes matter, but they should not take priority over distro proof and
repo hygiene:

- manual upstream-prep and correspondence
- Tailnet-direct transport
- Homebrew sync hygiene
- naming decisions

## Next Actions

1. Use the current Linux CI rerun as the proof base for the Debian 12 baseline
   lane; the substantive distro jobs are green even if the hosted Nix post-step
   still needs classification.
2. Refresh `#187`, `#55`, and `#76` using `docs/tracker-refresh-drafts.md`.
3. Keep Ubuntu/Fedora as the broad-feature proof target and Debian as the
   explicit baseline target.
4. Keep Rocky 10 terminal-first until a real browser/package path exists.
5. Avoid opening new architectural lanes until the existing parity matrix is
   promoted with real validation.
