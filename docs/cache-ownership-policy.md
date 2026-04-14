# CI Cache And Repo Ownership Policy

This document defines how `cmux` and adjacent repositories should use GitHub
Actions cache, Magic Nix Cache, and FlakeHub Cache.

Operational runbook:

- `docs/ci-cache-runbook.md`

The governing rule is simple:

- repository ownership determines cache strategy
- cache tooling does not determine repository ownership

We do not move a repository into an organization just to satisfy a cache
product.

## Why This Exists

FlakeHub Cache works well for organization-owned repositories where the
FlakeHub GitHub App is installed into the organization and the repository is
authorized there.

That model is not a reason to migrate personal forks or upstream-adjacent repos
into `tinyland-inc`. Doing so would distort ownership, fork intent, and the
upstreaming workflow.

## Policy

### 1. Personal forks stay personal

Examples:

- `Jesssullivan/cmux`
- adjacent personal forks used for upstream sync, carried patch work, or manual
  correspondence

Default cache posture:

- use GitHub Actions cache and `DeterminateSystems/magic-nix-cache-action`
- do not require FlakeHub Cache for normal CI health

Rationale:

- personal forks are often the correct place for upstream-facing work
- FlakeHub org authorization should not drive ownership decisions
- avoiding forced migration keeps external collaboration and provenance clear

### 2. Org-owned repos use FlakeHub Cache where it fits naturally

Examples:

- `tinyland-inc/lab`
- other naturally org-owned infra or product repos

Default cache posture:

- prefer FlakeHub Cache when the repository is authorized in the
  `tinyland-inc` FlakeHub organization
- keep the workflow gate explicit so unauthorized repos can fall back cleanly

Rationale:

- this is the path FlakeHub is designed to support operationally
- org-owned CI, shared caches, and org billing all line up cleanly

### 3. Do not migrate `cmux` to `tinyland-inc` just for cache

This is an explicit non-goal.

If `cmux` remains a personal fork, its CI should remain healthy without
depending on FlakeHub Cache.

### 4. Mirrors are optional and only justified by real operational need

If a future mirror exists, it must be treated as an operational convenience,
not as the canonical ownership surface.

Allowed use:

- burst CI
- org-scoped artifact/cache publication
- release automation that genuinely benefits from org ownership

Not allowed use:

- replacing the real fork as the primary collaboration surface by accident
- obscuring which repository is authoritative for carried patches and upstream
  sync work

Mirrors are extra complexity. They should be introduced only when the queue,
cost, or artifact-sharing benefit is large enough to justify that complexity.

## Current Application

As of 2026-04-13:

- `Jesssullivan/cmux` should keep `FLAKEHUB_CACHE_ENABLED=false`
- `tinyland-inc` may keep `FLAKEHUB_CACHE_ENABLED=true` at the org level
- `tinyland-inc` repos that are actually authorized for FlakeHub Cache should
  use it
- personal forks should not emit repeated FlakeHub `401 Unauthorized` noise in
  CI when Magic Nix Cache is sufficient

## Workflow Guidance

For repos that may or may not be FlakeHub-authorized:

- gate `flakehub-cache-action` behind `FLAKEHUB_CACHE_ENABLED == 'true'`
- fall back to `magic-nix-cache-action` otherwise
- keep `permissions` explicit: `contents: read`, `id-token: write`

This keeps a single workflow shape usable across both repo classes.

## Decision Rule

When evaluating a repository:

1. Ask who should canonically own the repo.
2. Choose the cache strategy that fits that ownership.
3. Only consider mirrors if the operational benefit is concrete and recurring.

Never reverse that order.
