# Component Portfolio And Health

This document is the operating inventory for the repositories, submodules,
libraries, and packaging lanes that currently make up the `cmux` program.

Use it to answer three practical questions:

1. what we actually carry
2. which components are healthy versus risky
3. which components are true blockers for Linux delivery

For live pin ancestry and worktree status, run:

```bash
./scripts/report-fork-health.sh
```

## Program Health Snapshot

As of 2026-04-13:

- core repo health is good: `cmux` mainline is ahead of upstream and recent CI
  has been green
- Linux implementation health is medium-good: `cmux-linux` is real and broad,
  but distro validation and capability proof are still incomplete
- dependency hygiene is improved: the `ghostty` fork ancestry problem is
  repaired, and the remaining dependency work is mostly routine sync discipline
- packaging health is medium: Homebrew is non-critical and slightly behind, and
  Linux packaging proof still needs explicit distro validation
- tracker health is medium: several public issues still describe an older phase
  of the Linux effort

## Actual Blockers

These are the real blockers or risk areas right now.

### 1. Broad-feature distro proof is still behind implementation

`cmux-linux` has broad implementation coverage, but the project still needs
repeatable proof on the target distro matrix.

Operational effect:
- Linux is no longer blocked on architecture
- Linux is still blocked on validation, packaging proof, and parity promotion

Primary references:
- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-validation-checklist.md`

### 2. Rocky 10 is a constrained target

Rocky 10 should currently be treated as terminal-first, not as a full browser
parity distro. The Linux tree explicitly supports `-Dno-webkit` for this class
of target.

Operational effect:
- Rocky validation should proceed, but browser parity should not be assumed
- Rocky should not block Ubuntu/Fedora broad-feature Linux progress

Primary references:
- `cmux-linux/build.zig`
- `docs/linux-program-plan.md`

### 3. Session restore is still not promotable

Linux session restore remains incomplete. The restore path is documented but is
not yet ready to be called `full`.

Operational effect:
- session persistence must stay below the full-parity line until it is proven

Primary references:
- `cmux-linux/src/session.zig`
- `docs/linux-parity-matrix.md`

### 4. Tailnet-direct remote sessions are a future lane

`cmuxd-remote` still centers on the existing stdio-serving model. Tailnet-direct
transport is a valid roadmap item, but it is not a current Linux distro blocker.

Operational effect:
- keep it tracked
- do not let it distract from distro validation and fork hygiene

Primary references:
- `daemon/remote/README.md`
- `docs/tracker-refresh-notes.md`

## Portfolio

| Component | Path | Ownership posture | Linux relevance | Current health | Primary blocker / risk | Next move |
|---|---|---|---|---|---|---|
| `cmux` | repo root | primary product repo | critical | `green` | issue tracker and validation docs needed cleanup more than core architecture | keep CI green and use docs to drive Linux proof |
| `cmux-linux` | `cmux-linux/` | in-tree product subtree | critical | `yellow` | validation and parity proof lag implementation | validate Ubuntu/Fedora broad-feature lanes first, then Debian baseline and Rocky terminal-first |
| `cmuxd` / `cmuxd-remote` | `cmuxd/`, `daemon/remote/` | in-tree service/runtime | medium | `yellow` | Tailnet-direct transport is not implemented yet | keep as separate remote/fleet lane |
| `ghostty` | `ghostty/` | active fork with carried patches | critical | `yellow` | highest-churn carried dependency, even though pin ancestry is now repaired | keep fork docs current and keep parent bumps on canonical fork `main` |
| `vendor/bonsplit` | `vendor/bonsplit/` | mostly tracking upstream | medium | `green` | low merge risk compared with Ghostty | keep sync posture clean and record any remaining fork-only delta |
| `vendor/ctap2` | `vendor/ctap2/` | fork-owned standalone library | high | `green` | Linux/WebAuthn still needs distro-level proof, not repo hygiene work | validate hardware-backed broad-feature distro ceremony |
| `vendor/zig-keychain` | `vendor/zig-keychain/` | fork-owned standalone library | high | `green` | distro-specific secret-service behavior still needs validation | validate libsecret path on Ubuntu/Fedora, then record Debian status |
| `vendor/zig-crypto` | `vendor/zig-crypto/` | fork-owned standalone library | medium | `green` | not currently blocking product delivery | keep standalone docs and mainline healthy |
| `vendor/zig-notify` | `vendor/zig-notify/` | fork-owned standalone library | medium | `green` | notification behavior still needs manual Linux validation | validate notification delivery during broad-feature distro smoke |
| `homebrew-cmux` | `homebrew-cmux/` | packaging repo | low | `yellow` | submodule pin is behind `origin/main` by 2 commits | resync when doing the next release hygiene pass |

## Health Interpretation

### `green`

- checked-in state is reproducible
- pin is reachable from the canonical branch
- current work is maintenance or validation, not rescue

### `yellow`

- component is usable and broadly healthy
- remaining work is real, but not a repo-integrity crisis
- shipping risk comes from validation or planning drift, not from branch loss

### `red`

- branch topology or dependency hygiene is in a state that can make rebases,
  audits, or future bumps harder than necessary
- this should be fixed before more dependency-sensitive work piles on top

## Operational Priority Order

When work competes for time, use this order:

1. CI or release breakage in `cmux`
2. Ubuntu/Fedora broad-feature validation
3. Debian 12 package/runtime baseline validation
4. Rocky 10 terminal-first validation
5. packaging cleanup
6. upstream-prep and extraction work

That ordering is deliberate. Linux delivery depends more on reproducible carried
dependencies and real distro proof than on expanding the project graph.
