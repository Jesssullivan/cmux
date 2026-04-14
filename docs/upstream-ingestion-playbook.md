# Upstream Ingestion Playbook

This document describes how `cmux` should ingest upstream changes from its
dependency and parent forks.

The GitHub Actions workflow automates part of this process. This document covers
the human review steps around that automation.

This playbook is about ingestion, not publication.

- agents may prepare upstreamable slices locally
- agents do not open upstream PRs or MRs
- external upstream correspondence is manual

## Purpose

Use this playbook when syncing from:

- `manaflow-ai/cmux` into `Jesssullivan/cmux`
- `ghostty-org/ghostty` into `Jesssullivan/ghostty`
- `manaflow-ai/bonsplit` into `Jesssullivan/bonsplit`

## Principles

1. keep the fork shippable at every step
2. prefer small, frequent syncs over large rebases after long gaps
3. classify conflicts explicitly
4. verify carried patches after every sync, even when the merge is clean
5. update the patch ledger or fork doc in the same change set

## File Classes

Every incoming change should be classified into one of three buckets.

### Fork-Owned

These are areas where the fork intentionally carries behavior that upstream does
not yet own.

Examples:
- FIDO2 / WebAuthn-specific integration
- fork-only workflows
- vendored fork-specific dependencies
- fork-specific entitlements or app packaging

Default stance:
- keep our version unless the upstream change is intentionally being adopted

### Merge-Carefully

These are high-churn files where both sides are likely correct but the merge can
silently break behavior.

Examples:
- terminal embedding glue
- browser panel integration points
- project files
- major workflow definitions
- core UI routing files

Default stance:
- inspect manually and validate behavior after merge

### Upstream-Tracked

These are files where upstream should generally win unless the fork has an
explicit reason to diverge.

Examples:
- generic docs
- base styles and assets not customized by the fork
- shared implementation areas with no carried patch

Default stance:
- accept upstream unless the fork doc says otherwise

## Workflow

### 1. Pre-Sync

- confirm the target branch is clean
- run `./scripts/report-fork-health.sh` and note any existing ancestry drift
- confirm the dependency doc reflects the current pin
- read the upstream changelog or recent PRs for risky areas
- note whether release artifacts, generated files, or project files are likely
  to move

### 2. Merge Or Rebase

- prefer normal merges for parent repo upstream ingestion unless there is a
  strong reason not to
- for submodule forks, follow the dependency’s own preferred sync strategy
- keep conflict resolution notes while merging; do not rely on memory later

### 3. Reconcile Carried Patches

After the merge completes:

- compare current carried patches against the dependency ledger
- drop patches that upstream has now absorbed
- repair patches that moved due to refactors
- update the dependency doc to reflect what is still carried

### 4. Validate

Validation should match the risk surface:

- workflow changes: confirm CI routes still make sense
- terminal embed changes: confirm terminal creation, focus, resize
- browser-related changes: confirm browser panel still loads and focuses
- FIDO2/WebAuthn changes: confirm the bridge still compiles and routes
- submodule changes: confirm the parent repo pin is reachable from the fork's
  canonical branch

### 5. Record The Result

- update the fork doc or patch ledger
- update `docs/component-portfolio.md` if the sync changes ownership posture,
  risk, or the primary blocker
- note the new upstream base or merge point
- call out any remaining drift or deferred cleanup

## Submodule-Specific Rules

### Ghostty

`ghostty` is the highest-risk upstream ingestion lane.

Always:
- update `docs/ghostty-fork.md`
- verify the parent repo pin is reachable from pushed fork `main`
- re-check carried patches touching terminal rendering, embedded runtime, and
  macOS platform glue

### Bonsplit

`bonsplit` is lower churn but still needs discipline.

Always:
- confirm whether the parent repo is tracking upstream directly or carrying a
  fork-only delta
- keep any fork-only delta small and documented

### Homebrew Packaging

`homebrew-cmux` is release hygiene, not product-critical.

Always:
- keep package metadata aligned with the latest release line
- do not let packaging drift obscure app-state reality

## Linux Program Tie-In

Upstream ingestion is not separate from Linux delivery.

It affects Linux directly when:

- `ghostty` platform or libghostty APIs move
- browser or embedding contracts change
- distro packaging paths change
- CI assumptions about release artifacts change

For Linux work, a sync is not complete until the parity matrix and distro plan
still describe reality.

## Done Criteria

An upstream ingestion pass is done only when:

1. the merge is complete
2. carried patches were reviewed
3. dependency docs were updated
4. pins are reproducible from canonical branches
5. the resulting repo state is still shippable
