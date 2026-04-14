# Upstream Candidate Ledger

This ledger tracks code that may be suitable for upstream consideration.

It is intentionally a preparation document, not a publication workflow.

## Rule

Upstream correspondence is manual.

- agents may identify, isolate, document, and test candidate slices
- agents do not open upstream PRs or MRs
- Jess handles any external submission, correspondence, or negotiation

## Purpose

- keep upstreamable work visible without putting it on the Linux critical path
- reduce the risk of losing good extraction candidates inside larger fork-only work
- make manual upstream submission cheap when the time is right

## Status Vocabulary

| Status | Meaning |
|---|---|
| `identified` | candidate exists but is not yet isolated cleanly |
| `prepared` | candidate has a clear scope and supporting notes |
| `ready-for-manual-submission` | candidate is small, documented, and can be submitted manually |
| `deferred` | useful, but not worth immediate extraction |
| `fork-only` | intentionally retained in the fork |

## Current Candidates

| Component | Candidate | Status | Notes |
|---|---|---|---|
| `ghostty` | OSC 99 notification parser | `prepared` | documented in `docs/ghostty-fork.md` |
| `ghostty` | macOS display-link restart fix | `prepared` | small carried patch, low conceptual risk |
| `ghostty` | resize stale-frame mitigation | `identified` | useful, but conflict-prone and larger |
| `ghostty` | Linux embedded platform variant | `identified` | relevant to Linux strategy, but depends on current integration shape |
| `vendor/bonsplit` | minimal fork delta | `identified` | track any divergence that remains after upstream sync |
| `vendor/zig-ctap2` | standalone Zig library packaging/docs polish | `prepared` | handled as a standalone project, not a cmux PR |
| `vendor/zig-keychain` | standalone Zig library packaging/docs polish | `prepared` | handled as a standalone project, not a cmux PR |
| `vendor/zig-crypto` | standalone Zig library packaging/docs polish | `prepared` | handled as a standalone project, not a cmux PR |
| `cmux` | upstream sync workflow pattern | `deferred` | useful as a template, non-critical |
| `cmux` | distro testing patterns | `deferred` | useful reference work, not on Linux critical path |

## Selection Rules

Prefer extraction candidates that are:

1. small
2. behaviorally self-contained
3. low-dependency
4. already documented
5. not on the current Linux critical path

Avoid extracting work that is:

- still moving quickly in the fork
- tightly coupled to fork-only Linux delivery work
- hard to validate outside the current repository graph

## Relationship To The Linux Program

This ledger is parallel to Linux delivery.

The Linux program wins scheduling priority over upstream preparation whenever
they conflict.
