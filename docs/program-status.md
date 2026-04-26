# Program Status

This is the short operational status for the `cmux` program.

Use it as the top-level readout for current health, blockers, and next actions.
It complements, rather than replaces:

- `docs/fork-landscape.md`
- `docs/cache-ownership-policy.md`
- `docs/component-portfolio.md`
- `docs/distro-testing-readiness-plan.md`
- `docs/flakehub-qa-ownership-notes.md`
- `docs/linux-program-plan.md`
- `docs/linux-packaging-cd-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-work-week-2026-04-14.md`
- `docs/linear-qa-shard-punchlist.md`
- `docs/program-review-2026-04-14.md`
- `docs/linux-validation-checklist.md`
- `docs/tracker-refresh-notes.md`

## Snapshot

As of 2026-04-25:

- core repo health is good: the fork is ahead of upstream, recent CI is mostly
  green, and the Linux branch is proving real distro/container coverage instead
  of speculative design
- fork hygiene is materially better: the `ghostty` pin is now reachable from
  canonical fork `main`, and the carried package graph is mostly reproducible
- Linux implementation health is medium-good: `cmux-linux` is broad and real,
  but validation still lags implementation
- tracker health is medium-good: the public issues are now much closer to repo
  reality, but the distro-proof lane still needs steady note hygiene
- packaging health is medium: Homebrew is slightly behind, and Linux package
  proof is still uneven across the distro matrix
- CI runtime hygiene is medium: the Linux branch is green, but GitHub Actions
  runtime upkeep still needs steady attention as hosted actions deprecate older
  Node versions, and `main` branch protection still needs to be enforced after
  the required check set is finalized

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
- `docs/distro-testing-readiness-plan.md`

### 2. Tracker hygiene

The main planning risk is no longer stale umbrella issues. It is making sure the
same QA and ownership decisions are visible on every owned surface.

Current focus:

- keep `#55`, `#187`, and `#209` aligned with the real Fedora 42 and Rocky 10
  distro-proof state
- keep FlakeHub and `nix-vm-test` notes on owned Jesssullivan and Tinyland
  surfaces only
- keep the `nix-vm-test` upstream exit visible: `numtide/nix-vm-test#172`
  merged on 2026-04-22, and cmux now pins upstream `numtide/nix-vm-test`
- keep the now-closed fork-landscape work from reopening ad hoc upstream work
  while new upstream handoffs stay human-gated

Primary references:

- `docs/flakehub-qa-ownership-notes.md`
- `docs/linear-qa-shard-punchlist.md`

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
- `Jesssullivan/nix-vm-test` exists as the previous fallback fork, but upstream
  now has the needed Fedora 42 and Rocky 10.1 image support and cmux pins
  upstream `numtide/nix-vm-test`

### Distro package-test VM coverage

Current `test-distro` coverage includes:

- `Ubuntu 24.04`
- `Debian 12`
- `Fedora 42`
- `Rocky 9` as the current RPM-path proxy
- real `.sandboxed` VM execution rather than driver-only outputs

Current gap:

- `Fedora 42` is wired into the repo-owned VM lane, but still needs a recorded
  first green CI result on the self-hosted KVM runner
- `Rocky 10` has a terminal-first RPM path staged in the active packaging WIP,
  but still needs first green CI evidence and a published `rpmRocky` asset in
  the checked-in manifest
- the VM-image blocker is resolved upstream; remaining work is artifact truth
  and first green proof
- this remains a distro-proof and artifact-truth problem, not a FlakeHub
  account or repo ownership problem

### Linux socket-test coverage

Current `scripts/run-socket-tests.sh` coverage includes:

- 123 `tests_v2` test files on disk
- 18 baseline tests that fail the Linux socket job when red
- 11 phase-1 candidate tests that run as non-fatal observations

Recent CI made the baseline contract useful but exposed one active baseline
failure: `test_surface_action_close_variants`. That should be fixed or
explicitly reclassified before promoting more candidate tests.

### Merge governance

`docs/ci-governance.md` defines the required hosted checks and advisory
self-hosted lanes for `Jesssullivan/cmux`.

Current gap:

- `main` branch protection/rulesets still need to be enabled in GitHub
- self-hosted KVM package-install proof remains advisory until `honey-cmux`
  availability is stable enough to act as a normal merge gate

## Dependency And Package Health

| Component | Status | Current read |
|---|---|---|
| `ghostty` | `yellow` | highest-churn dependency, but fork-main ancestry is repaired |
| `vendor/bonsplit` | `green` | low-risk, close to upstream |
| `vendor/ctap2` | `green` | repo hygiene is healthy; real Linux/WebAuthn proof is still needed |
| `vendor/zig-keychain` | `green` | healthy; distro-level secret-service validation still needed |
| `vendor/zig-crypto` | `green` | healthy, not a delivery blocker |
| `vendor/zig-notify` | `green` | healthy; Linux notification proof still needed |
| `homebrew-cmux` | `yellow` | behind `origin/main` by 6 commits; not a Linux blocker |

For live ancestry and worktree checks:

```bash
./scripts/report-fork-health.sh
```

## Open Tracker Map

As of 2026-04-25, the public fork tracker is small and focused:

- `#55` `Epic: Linux Delivery, Distro Proof, and Remaining Parity Gaps`
- `#76` `RFC: Linux client naming — cmux vs lmux`
- `#187` `ci(distro): establish Rocky 10 fresh-install proof and retire the Rocky 9 proxy`
- `#206` `linux: complete WebAuthn bridge handling`
- `#209` `ci(distro): establish Fedora 42 fresh-install VM proof`
- `#216` `tests_v2: expand Linux socket-test coverage beyond the current stable baseline`
- `#201` `feat(cmuxd-remote): add TCP listener mode for Tailnet direct connections`

Interpretation:

- `#55`, `#187`, `#209`, and `#216` are the active Linux execution lane
- `#206` is the active WebAuthn/FIDO2 parity lane
- `#201` is real, but parallel
- `#76` is intentionally non-blocking unless distro distribution or product
  clarity creates a real rename trigger
- the main note-hygiene risk is cross-repo QA decisions drifting out of sync

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
2. Record the wired `Fedora 42` and `Rocky 10` VM lanes on `#209` and `#187`,
   and keep their first green runs visible.
3. Keep Ubuntu/Fedora as the broad-feature proof target and Debian as the
   explicit baseline target.
4. Keep Rocky 10 terminal-first until a real browser/package path exists.
5. Keep `cmux` as the working product and package name unless the rename
   triggers in `docs/distro-testing-readiness-plan.md` become real.
6. Replace or isolate the remaining `mlugg/setup-zig@v2` call sites as a
   separate CI hygiene follow-up.
7. Enable `main` branch protection with the hosted required-check set in
   `docs/ci-governance.md`.
8. Avoid opening new architectural lanes until the existing parity matrix is
   promoted with real validation.
