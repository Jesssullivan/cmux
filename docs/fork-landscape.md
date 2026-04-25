# Fork Landscape And Governance

This project is no longer just a single app repository. `cmux` now depends on a
set of forks, vendored components, standalone Zig libraries, packaging repos,
and CI infrastructure that all need to move coherently.

This document is the operating map for that work.

Operational inventory:
- `docs/program-status.md`
- `docs/component-portfolio.md`
- `docs/cache-ownership-policy.md`

## Why This Exists

- keep Linux delivery work grounded in the actual repository graph
- separate critical-path product work from upstream-prep work
- make fork hygiene and submodule policy explicit
- avoid plans drifting away from the current repo state

## Component Map

| Component | Role | Current posture | Notes |
|---|---|---|---|
| `cmux` | Primary app repo | Active product repo | macOS app, Linux tree, packaging, CI |
| `cmux-linux` | Native Linux implementation | Active product subtree | part of this repo, not a separate package |
| `ghostty` | Terminal core fork | Active fork with local carried patches | highest merge-risk dependency |
| `vendor/bonsplit` | Split/tab UI library | Mostly tracking upstream | small local delta, low-risk compared with Ghostty |
| `vendor/ctap2` | FIDO2/CTAP2 implementation | Fork-owned dependency | part of the attestation-free stack |
| `vendor/zig-crypto` | Shared crypto primitives | Standalone library | upstream-ready packaging/documentation lane |
| `vendor/zig-keychain` | Shared secret storage library | Standalone library | cross-platform support for app + Linux |
| `vendor/zig-notify` | Shared notification library | Standalone library | useful outside cmux, but not on critical path |
| `homebrew-cmux` | Homebrew packaging | Tracking repo | release hygiene, not product-critical |

## Operating Lanes

### 1. Core Delivery

This lane exists to ship `cmux` and `cmux-linux`.

Scope:
- app behavior
- Linux parity
- distro packaging and validation
- CI and release health

This is the critical path.

### 2. Fork Hygiene

This lane keeps dependencies reproducible and mergeable.

Scope:
- submodule pin correctness
- fork docs
- branch ancestry
- upstream sync discipline

This is mandatory maintenance. It is not optional cleanup.

### 3. Upstream Ingestion

This lane pulls in `manaflow-ai/cmux`, `ghostty-org/ghostty`, and
`manaflow-ai/bonsplit` changes safely.

Scope:
- scheduled syncs
- conflict classification
- regression review
- carried-patch validation

This should be continuous, not episodic.

Operational guide:
- `docs/upstream-ingestion-playbook.md`

### 4. Upstreamable Slices

This lane prepares code that could plausibly leave the fork.

Scope:
- standalone Zig libraries
- isolated `ghostty` patches
- isolated `bonsplit` patches
- reusable CI/templates

This lane is parallel and explicitly non-blocking for Linux delivery.

Publication rule:
- agents prepare candidates locally, but do not open upstream PRs, MRs,
  issues, review comments, or other correspondence
- candidate publication work should be staged in owned docs/trackers first
- external submission and correspondence are manual

Tracking ledger:
- `docs/upstream-candidate-ledger.md`

## Governance Rules

### Canonical Source Of Truth

- the checked-in repo state is authoritative for shipping work
- fork docs must match the checked-in submodule pins
- issue trackers should describe current reality, not historical intent
- cache strategy must follow canonical repository ownership, not override it

### Submodule Policy

- every parent-repo submodule bump must point at a commit reachable from that
  dependency's canonical fork branch
- do not rely on detached-only submodule commits
- update the dependency doc in the same change set as the submodule bump

### Merge-Ingestion Policy

- upstream syncs must classify files as `fork-owned`, `merge-carefully`, or
  `upstream-tracked`
- carried patches must be reviewed after every sync, even on clean merges
- high-churn dependencies, especially `ghostty`, need an explicit patch ledger

### Linux Parity Policy

- Linux parity is judged by capability, not by identical implementation
- distro-specific constraints must be recorded explicitly
- `terminal-first` support on a constrained distro is acceptable if documented
- do not silently downgrade a feature on Linux or on a specific distro

## Current Health Snapshot

As of 2026-04-13:

- `cmux` mainline health is good: recent CI is green and the working TODO is
  largely complete
- `cmux-linux` is real and materially implemented, not just a research branch
- `ghostty` remains the highest-churn dependency, but the earlier fork-main
  ancestry problem has been repaired
- `bonsplit` is comparatively healthy and close to upstream
- packaging and distro validation are behind the implementation

## Current Organizational Risks

### 1. Stale planning surfaces

Several issue and plan artifacts still describe older states of the Linux
program, Rocky support, or fork shape. That causes avoidable confusion when
deciding what is actually blocked.

### 2. Distro capability ambiguity

`cmux-linux` has different practical capability classes today:

- `Ubuntu 24.04`, `Fedora 42`: current broad-feature Linux targets
- `Debian 12`: package/runtime baseline with browser status still needing
  explicit proof
- `Rocky 10`: currently a constrained, terminal-first target because WebKitGTK
  is not a normal system-package path there

This distinction needs to stay explicit.

## Near-Term Priorities

1. Reconcile `ghostty` pin ancestry and update `docs/ghostty-fork.md`.
2. Keep `bonsplit` and `homebrew-cmux` in a known tracking state.
3. Maintain `docs/linux-parity-matrix.md` so it distinguishes full-feature and
   terminal-first distro support.
4. Groom stale issues so the tracker matches the codebase.
   Supporting notes: `docs/tracker-refresh-notes.md`
5. Keep upstreamable work in small, isolated slices so it never blocks core
   Linux delivery.

## Decision Framework

When work competes for attention, use this order:

1. release and CI breakage
2. fork hygiene that threatens reproducibility
3. Linux feature parity on supported distros
4. distro validation and packaging proof
5. upstream-prep and extraction work

That ordering is deliberate. The project only benefits from upstream
consideration if the forked program itself stays coherent and shippable.
