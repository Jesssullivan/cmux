# Program Status

This is the short operational status for the `cmux` program.

Use it as the top-level readout for current health, blockers, and next actions.
It complements, rather than replaces:

- `docs/fork-landscape.md`
- `docs/cache-ownership-policy.md`
- `docs/component-portfolio.md`
- `docs/linux-program-plan.md`
- `docs/linux-packaging-cd-plan.md`
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
- CI runtime hygiene is medium: the Linux branch is green, but GitHub Actions
  runtime upkeep still needs steady attention as hosted actions deprecate older
  Node versions

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

### 3. Linux parity honesty

The main Linux risk is no longer “is there source code?” It is whether the
current docs and tracker are honest about what is implemented versus what is
still scaffolding.

The biggest currently non-promotable surfaces are:

- the Linux WebAuthn bridge installs, but request handling is still stubbed
- the socket/control-plane surface includes several stubbed verbs and mostly
  no-op Linux action/clipboard callbacks
- `cmux-term` remains placeholder-only

### 4. Explicit parity promotion

Capabilities must not be promoted based on source presence alone.

The biggest remaining parity gaps are:

- Linux WebAuthn bridge completion, not just WebAuthn validation
- Linux socket/control-plane parity for write/read and structural commands
- browser/WebAuthn proof on Tier A distros
- explicit browser/WebAuthn status recording on Debian 12
- terminal-first proof on Rocky 10
- session restore and headless mode staying below `full` until implementation
  and proof exist

## Current Automation Coverage

### Linux CI container/build coverage

Current branch coverage includes:

- `Ubuntu 24.04`
- `Fedora 42`
- `Rocky 10`
- `Debian 12` baseline, `-Dno-webkit`
- `Arch Linux`
- hosted `Nix flake check`
- Linux vendor-library build/test lane

This is useful build/static/runtime-baseline evidence, but it is not the same
as package-install proof.

Current read:

- the branch Linux CI matrix is fully green
- the remaining CI hygiene issue is Actions runtime drift, not Linux breakage
- cache policy is explicit: personal forks use Magic Nix Cache by default,
  while FlakeHub Cache remains an org-owned repo lane

### Distro package-test VM coverage

Current `test-distro` coverage includes:

- `Ubuntu 24.04`
- `Debian 12`
- `Rocky 9` as the current RPM-path proxy

Current gap:

- `Fedora 42` and `Rocky 10` VM package-install proof still lag because
  upstream `nix-vm-test` currently exposes `Fedora 39-41` and `Rocky 8.6-9.6`,
  not `Fedora 42` or `Rocky 10`

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
- the tracker still does not isolate the Linux WebAuthn, socket-parity, or
  headless/runtime gaps as dedicated issues

## Current Non-Blockers

These lanes matter, but they should not take priority over distro proof and
repo hygiene:

- replacing `mlugg/setup-zig@v2` to eliminate the last Node 20 deprecation noise
- manual upstream-prep and correspondence
- Tailnet-direct transport
- Homebrew sync hygiene
- naming decisions
- moving personal forks into `tinyland-inc` purely to satisfy FlakeHub Cache

## Next Actions

1. Use the current Linux CI rerun as the proof base for the Debian 12 baseline
   lane and the Ubuntu/Fedora broad-feature lanes; the current branch matrix is
   green.
2. Refresh `#187`, `#55`, and `#76` using `docs/tracker-refresh-drafts.md`.
3. Keep Ubuntu/Fedora as the broad-feature proof target and Debian as the
   explicit baseline target.
4. Keep Rocky 10 terminal-first until a real browser/package path exists.
5. Replace or isolate the remaining `mlugg/setup-zig@v2` call sites as a
   separate CI hygiene follow-up.
6. Avoid opening new architectural lanes until the existing parity matrix is
   promoted with real validation.
