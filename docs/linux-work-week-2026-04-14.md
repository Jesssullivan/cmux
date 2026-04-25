# Linux Work Week Plan

This document is the week-scale execution plan for the Linux-native `cmux`
program as of `2026-04-14`.

Use it with:

- [program-status.md](/Users/jess/git/cmux/docs/program-status.md:1)
- [program-review-2026-04-14.md](/Users/jess/git/cmux/docs/program-review-2026-04-14.md:1)
- [linux-program-plan.md](/Users/jess/git/cmux/docs/linux-program-plan.md:1)
- [linear-qa-shard-punchlist.md](/Users/jess/git/cmux/docs/linear-qa-shard-punchlist.md:1)

## North Star

Ship Linux-native `cmux` with explicit distro support tiers, truthful package
metadata, repeatable fresh-install proof, and a parity surface that reflects
what actually works today rather than what merely has source files.

## Current Read

The broad shape is good.

- `cmux` repo health is good
- hosted Linux CI is green
- KVM package validation is real and release-gating
- dependency hygiene is mostly healthy

The main work has shifted from architecture to proof and scope control.

## This Week's Priority Order

### 1. Merge And Stabilize `#205`

Why first:

- it already contains the hygiene, packaging, distro-test, and status work the
  program should build on
- it materially improves the release surface and the public state of the repo

Success:

- `#205` merged
- no new Linux CI regressions introduced immediately after merge

### 2. Refresh The Public Planning Surface

Why next:

- the current repo docs are more accurate than the current public issue and
  milestone bodies
- stale tracker state is now a coordination risk

Scope:

- refresh `#55`
- refresh `#187`
- refresh `#199` (completed on `2026-04-21`)
- keep `#76` explicitly non-blocking
- keep `#201` explicitly parallel
- clean up stale open milestones `M6` through `M9`

Success:

- the public tracker matches the current code and distro support reality

### 3. Run Direct Tier A QA

Why now:

- the remaining blocker is not build breakage, it is proving real user-facing
  behavior on real distros

Scope:

- `Ubuntu 24.04` direct feature QA
- `Fedora 42` direct feature QA

Focus:

- package install
- runtime launch
- terminal/split smoke
- socket/API smoke
- browser smoke
- desktop integration smoke

Success:

- one recorded proof pass or one crisp blocker per distro

### 4. Close The Debian And Rocky Truth Gaps

Why this matters:

- Debian is currently a baseline distro, not yet a broad-feature claim
- Rocky 10 is currently terminal-first, not browser-first

Scope:

- record Debian 12 browser/WebAuthn status explicitly
- run direct Rocky 10 terminal-first QA
- make package/runtime limits explicit where needed

Success:

- Debian is accurately classified
- Rocky is accurately classified

### 5. Decide The Next VM Harness Move

Why this matters:

- KVM release-gated proof exists, but the current VM matrix still does not cover
  `Fedora 42` or `Rocky 10`

Decision to make:

1. extend `nix-vm-test` coverage when upstream images exist
2. carry a local harness extension
3. add an alternate VM path for those distros

Success:

- one selected approach for `Fedora 42` and `Rocky 10` fresh-install proof

### 6. Split The Remaining Linux Parity Work Into Dedicated Lanes

Why this matters:

- WebAuthn, socket/control-plane parity, and restore/headless are currently
  buried under the Linux umbrella

Dedicated lanes:

- Linux WebAuthn bridge completion
- Linux socket/control-plane parity
- Linux session restore and headless runtime

Success:

- each lane has a clear scope, references, and exit criteria

### 7. Keep Upstream-Prep Parallel And Small

Why this matters:

- there are good small extraction candidates, but they should not disrupt Linux
  delivery

Good candidates:

- `ghostty` OSC 99 notification parser
- `ghostty` display-link restart fix
- minimal `bonsplit` fork delta
- standalone Zig library docs/packaging polish

Success:

- candidate slices stay visible without becoming the critical path

## Parallel Work Lanes

### Lane A: Repo Governance And Planning

Scope:

- merge `#205`
- tracker refresh
- milestone cleanup
- roadmap/status doc upkeep

### Lane B: KVM And Packaging Proof

Scope:

- current release-gated distro VM validation
- artifact taxonomy review
- exact-artifact validation discipline
- Fedora 42 / Rocky 10 harness strategy

### Lane C: Direct Linux QA

Scope:

- Ubuntu 24.04
- Fedora 42
- Debian 12
- Rocky 10

### Lane D: Linux Parity Implementation

Scope:

- WebAuthn bridge completion
- socket/control-plane completion
- restore/headless decisions and implementation

### Lane E: Dependency And Upstream-Prep Hygiene

Scope:

- `ghostty` watchlist
- `bonsplit` low-delta review
- `zig-ctap2`, `zig-keychain`, `zig-crypto`, `zig-notify` status checks
- small extraction candidates only

## Work Week Decision Rules

1. Do not open new architecture lanes until direct distro QA produces either
   proof or crisp blockers.
2. Do not promote a Linux feature based on source presence alone.
3. Do not let upstream-prep work outrun Linux delivery work.
4. Do not distort repo ownership or cache policy to satisfy builder tooling.
5. Treat Rocky 10 as terminal-first until proven otherwise in a real packaging
   path.

## End-Of-Week Desired Output

The week is successful if these are true:

1. `#205` is merged
2. public issues and milestones reflect current reality
3. direct QA results exist for `Ubuntu 24.04` and `Fedora 42`
4. Debian 12 browser status is explicitly recorded
5. Rocky 10 terminal-first status is explicitly recorded
6. the next VM-harness decision for `Fedora 42` and `Rocky 10` is made
7. the remaining parity gaps are split into dedicated work items
