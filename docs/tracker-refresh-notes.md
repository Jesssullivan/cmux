# Tracker Refresh Notes

These notes are for issue and roadmap grooming. They are local planning aids and
should be treated as prep material for GitHub issue updates, not as the tracker
itself.

Ready-to-edit text lives in:

- `docs/tracker-refresh-drafts.md`

## Purpose

- identify where the public tracker no longer matches repo reality
- separate code blockers from stale descriptions
- make issue updates cheap and precise

## Open Fork Issues

### `#55` Epic: De-Attestation & Linux Porting Roadmap

Current problem:
- still reads like a forward-looking Linux architecture epic
- does not reflect how much of `cmux-linux` already exists in-tree
- currently hides several important Linux gaps inside one large umbrella

Current repo reality:
- `cmux-linux` has substantial terminal, workspace, socket, browser, cookie,
  notification, and WebAuthn-related implementation
- the real remaining work is parity classification, distro validation, and
  packaging proof

Recommended refresh:
- keep it open, but rewrite it as a program umbrella
- split implementation-complete milestones from validation/packaging milestones
- either add checklist items or spin out dedicated issues for WebAuthn bridge completion, socket/API parity, and headless/session restore
- reference `docs/linux-program-plan.md` and `docs/linux-parity-matrix.md`

### `#76` RFC: Linux client naming

Current problem:
- the issue still assumes the naming decision is blocking early Linux work

Current repo reality:
- the bigger blockers are distro validation and parity proof

Recommended refresh:
- keep it low-priority
- explicitly mark naming as non-blocking for the Linux delivery program

### `#187` Rocky 10 tracking

Current problem:
- the issue body still says Rocky 10 has not been released

Current repo reality:
- Rocky 10 is GA, but `nix-vm-test` support remains the blocker
- Rocky is also a constrained distro for browser parity because system WebKitGTK
  is not the normal path

Recommended refresh:
- update the issue body to say Rocky 10 is available, but current automation
  support is lagging
- distinguish package-install validation from browser parity

### `#199` Fork landscape and upstream opportunities

Current problem:
- directionally correct, but should stay clearly non-blocking

Current repo reality:
- still useful as a maintenance umbrella for upstreamable slices

Recommended refresh:
- keep open
- explicitly mark it as a parallel maintenance lane, not part of Linux critical
  path
- note that any upstream submission work is manual and outside agent scope

### `#201` Tailnet direct `cmuxd-remote`

Current problem:
- none; this is a valid future-facing issue

Current repo reality:
- `cmuxd-remote` still documents `serve --stdio` only
- this is not a Linux distro-validation blocker

Recommended refresh:
- keep open
- explicitly mark it as a remote/fleet enhancement lane

## Local Docs That Should Be Referenced In Future Issue Updates

- `docs/fork-landscape.md`
- `docs/component-portfolio.md`
- `docs/upstream-ingestion-playbook.md`
- `docs/upstream-candidate-ledger.md`
- `docs/ghostty-fork.md`
- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-mvp-architecture.md`

## Missing Explicit Tracker Coverage

Current problem:
- several high-priority Linux gaps are visible in code and docs, but not as
  dedicated tracker items

Current repo reality:
- Linux WebAuthn install exists, but the handler is stubbed
- Linux socket/control-plane parity still has stubbed verbs and host callbacks
- session restore and `cmux-term` are not yet promotable

Recommended refresh:
- either open dedicated issues for those gaps or add explicit checklist items
  under `#55`
- keep them separate from distro-validation tracking so implementation gaps do
  not get mislabeled as “just needs testing”

## Suggested Update Order

1. `#187` Rocky 10
2. `#55` Linux epic
3. missing explicit Linux gap coverage under `#55` or new issues
4. `#76` naming RFC
5. `#199` fork landscape
6. `#201` remote/Tailnet lane wording

## Rule

When refreshing an issue, prefer:

- exact current repo state
- explicit blockers
- links to checked-in docs

Avoid:

- historical plans presented as current
- broad aspirational language without a capability or validation status
