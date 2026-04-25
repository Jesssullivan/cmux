# lmux Release And Ingestion Cadence

This document turns the `lmux` management lane into an operating cadence. It
builds on `docs/upstream-sync.md` and `docs/linux-qa-intake.md`.

## Cadence Summary

| Surface | Cadence | Owner action |
|---|---:|---|
| Ghostty drift | weekly | inspect upstream commits, sync owned fork before drift exceeds about 50 commits, rebuild GhosttyKit for chosen parent pins |
| cmux upstream drift | bi-weekly | read-only classify upstream changes; ingest only after Linux fork risks are understood |
| Bonsplit drift | monthly | track upstream, keep fork delta small, move parent pointer only to pushed/reachable commits |
| Linux QA intake | weekly while active | publish one owned status note and ask for the next distro reports |
| Release candidate QA | before each Linux tag | collect Tier A/B/C evidence that matches the package artifacts |
| Upstreamable prep | at most one candidate per session | prepare a handoff packet; Jess submits non-owned PRs by hand |

## Channels

Use three release channels:

| Channel | Purpose | Gate |
|---|---|---|
| canary | fast feedback from known testers and local VMs | builds and installs on at least one Tier A distro |
| release candidate | public QA window for specific artifacts | signed packages, install docs, and support-tier wording are ready |
| stable | monthly or evidence-backed release | QA evidence matches the release notes and package metadata |

Nightly or canary builds can be frequent, but stable releases should not imply
broad Linux support until the QA evidence supports that claim.

## Distro QA Gate

Before a stable Linux release, collect or explicitly defer:

- Ubuntu 24.04 broad-feature report
- Fedora 42 broad-feature report
- Debian 12 package/runtime baseline
- Rocky 10 terminal-first report when a distinct Rocky artifact exists
- Arch, Mint, and NixOS reports as early compatibility evidence only

If one of these is missing, keep the release notes honest about the missing
proof. Do not block every release on every community distro, but do not upgrade
support-tier language without evidence.

## Weekly Operating Loop

1. Check Ghostty drift and owned fork PR state.
2. Check Bonsplit and cmux upstream drift only if the urgent Ghostty lane is not
   consuming the whole session.
3. Review open packaging and QA issues for artifact truth.
4. Publish one status note in Linear or an owned issue.
5. Pick no more than one upstreamable candidate to prepare.
6. Keep relationship/Manaflow language separate from technical bug reports.

## Monthly Release Loop

1. Pick a release-candidate commit and artifact set.
2. Verify license and third-party notice facts.
3. Verify package signing and install docs.
4. Open a focused QA window.
5. Promote only evidence-backed distro claims into release notes.
6. File follow-up issues for missing distro evidence instead of burying gaps in
   the release text.

## Current Management Mapping

| Linear item | Lane | Current interpretation |
|---|---|---|
| `TIN-594` | Ghostty parent pin | blocked on owned-fork PR #13 checks/merge before parent pointer moves |
| `TIN-174` | Bonsplit | upstream PR #104 is open; cmux pointer waits on upstream merge or explicit fork posture |
| `TIN-575` | relationship docs | satisfied by `docs/lmux-relationship.md` once reviewed |
| `TIN-576` | third-party licenses | satisfied by `THIRD_PARTY_LICENSES.md` once the Zig library entries are present |
| `TIN-578` | cadence | satisfied by this document plus `docs/upstream-sync.md` |
| `TIN-579` | QA onboarding | covered by `docs/linux-qa-intake.md` and `docs/linear-qa-shard-punchlist.md` |
| `TIN-580` | Manaflow/upstream pipeline | relationship doc and upstream candidate ledger are the first planning surfaces |

## Stop Conditions

Pause broad planning and return to urgent execution when:

- Ghostty cannot build for the selected parent pin
- parent repo submodule pointers would reference commits not reachable from the
  chosen owned remote
- package artifacts or signatures are not reproducible enough for QA testers
- upstream relationship language starts to blur support ownership
