# FlakeHub QA And Ownership Notes

This document records the current FlakeHub, distro-QA, and `nix-vm-test`
ownership decisions for owned `Jesssullivan/*` and `tinyland-inc/*` surfaces.

Use it with:

- `docs/ci-cache-runbook.md`
- `docs/cache-ownership-policy.md`
- `docs/linux-packaging-cd-plan.md`
- `docs/linear-qa-shard-punchlist.md`

## Current Reality

As of 2026-04-25:

- both a personal FlakeHub subscription and a `tinyland-inc` organization
  subscription exist
- `Jesssullivan/cmux` is the canonical personal fork for the product and should
  keep `FLAKEHUB_CACHE_ENABLED=false`
- `tinyland-inc/lab` is the active org-owned FlakeHub and builder lane
- `numtide/nix-vm-test#172` merged on 2026-04-22 with `Fedora 42` and
  `Rocky 10.1` image support
- the repo now pins upstream `numtide/nix-vm-test` at `be5379d`
- `Jesssullivan/nix-vm-test` exists as the previous personal fallback fork, but
  it is no longer the cmux flake input
- `Jesssullivan/nix-vm-test` has issues disabled and currently has no open pull
  requests, so it is not a useful planning surface by itself

## Product Constraints From Current FlakeHub Docs

Current official FlakeHub docs say:

- individuals can log in, subscribe, and use FlakeHub on their own
- FlakeHub Cache and private flakes require a paid plan
- organization onboarding is where GitHub App installation, org billing, member
  invites, and repository authorization are managed
- GitHub Actions use OIDC-style auth and require `permissions.contents=read`
  plus `permissions.id-token=write`
- FlakeHub Cache is not available on pull requests coming from forks of an
  organization's repositories
- private flakes are granted through organization membership plus per-flake
  access

Relevant docs:

- `https://docs.determinate.systems/getting-started/individuals/`
- `https://docs.determinate.systems/getting-started/organizations/`
- `https://docs.determinate.systems/flakehub/cache/`
- `https://docs.determinate.systems/flakehub/private-flakes/`

## QA Implications

### 1. FlakeHub is not the current blocker for distro proof

The remaining distro-proof blockers are not about cache product or account
shape.

Current read:

- `Fedora 42` and `Rocky 10.1` image support now exists upstream in
  `numtide/nix-vm-test`
- `Fedora 42` is wired into the repo-owned VM harness using upstream
  `nix-vm-test`
- `Rocky 10` now has a repo-owned terminal-first RPM lane on the branch; the
  remaining work is first green proof and proxy retirement, not FlakeHub
  subscription shape

Current owned tracking surfaces for that blocker:

- `Jesssullivan/cmux#209`
- `Jesssullivan/cmux#187`
- Tinyland Linear initiative `cmux Linux Distribution & Tech Debt Reset`

### 2. Personal forks must remain testable without org cache privileges

`Jesssullivan/cmux` should remain reproducible with GitHub Actions cache and
`magic-nix-cache-action`. The previous `Jesssullivan/nix-vm-test` fallback
should not become a hidden cache or ownership dependency.

Interpretation:

- the personal subscription is useful, but it does not justify changing
  canonical repo ownership
- FlakeHub may accelerate owned org repos
- it must not become a hidden prerequisite for personal-fork CI health
- package-install proof and release gating should still work when FlakeHub Cache
  is unavailable

### 3. `tinyland-inc` is the right lane for shared builder work

Use `tinyland-inc/lab` for:

- FlakeHub App, billing, and membership validation
- shared cache experiments
- self-hosted runner throughput work
- published flake and builder ergonomics that are naturally org-owned

Do not use those benefits as a reason to re-home `cmux` or reintroduce a stale
`Jesssullivan/nix-vm-test` pin after upstream has the needed image support.

### 4. Planning notes must live on owned surfaces

Because `Jesssullivan/nix-vm-test` has issues disabled, decision notes must live
in:

- `Jesssullivan/cmux` GitHub issues
- Tinyland Linear
- checked-in docs in this repo

Do not let fork-carried harness work become invisible just because the fallback
fork itself has no issue tracker.

## Repo-Specific Rules

### `Jesssullivan/cmux`

- keep `FLAKEHUB_CACHE_ENABLED=false`
- keep the workflow gates in place so the same workflow shape still works on
  org-owned repos
- treat FlakeHub as optional acceleration learned from `tinyland-inc`, not as a
  requirement for repo health

### `Jesssullivan/nix-vm-test`

- treat it as a historical fallback now that `numtide/nix-vm-test#172` has
  merged and cmux has re-pinned to upstream
- if it diverges, record:
  - exact fork SHA
  - exact carried patch reason
  - exact re-pin or upstream-exit plan
- store that reasoning in `Jesssullivan/cmux` issue comments and Tinyland
  Linear, not in ad hoc local notes

### `tinyland-inc/lab`

- keep it as the org-owned FlakeHub and builder proving ground
- validate account, app-install, seat, and member-management assumptions there
  first
- feed the lessons back into `cmux` docs without changing canonical repo
  ownership

## Human-Gated Boundary

Agents may inspect upstream or vendor state, but they must stop at owned
`Jesssullivan/*` and `tinyland-inc/*` surfaces unless the user explicitly asks
for a specific upstream action.

That includes:

- upstream issues
- upstream pull requests
- upstream app-install or billing changes
- correspondence on third-party repo surfaces

## Current Decision Log

1. Keep `cmux` in personal ownership while its canonical role is fork-adjacent
   and upstream-sensitive.
2. Keep FlakeHub-heavy builder work in `tinyland-inc/lab`, where org billing and
   repository authorization actually belong.
3. Use `Jesssullivan/nix-vm-test` only as a future owned carry surface if
   upstream lacks a needed image or harness patch again.
4. Do not let FlakeHub account shape drive artifact taxonomy, distro promises,
   or repo ownership.

## Near-Term Follow-Up

1. Keep the wired `Fedora 42` VM lane and its first green run visible on
   `#209`.
2. Keep the wired `Rocky 10` terminal-first lane and its first green run
   visible on `#187`.
3. If `Jesssullivan/nix-vm-test` diverges from upstream again, link the exact SHA and
   patch set from `docs/linux-packaging-cd-plan.md`.
4. Keep the FlakeHub/account discussion on owned Jesssullivan and Tinyland
   trackers only.
