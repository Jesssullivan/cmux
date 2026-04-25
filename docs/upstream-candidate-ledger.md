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
| `upstreamed` | already accepted upstream; track local cleanup or re-pin only |
| `deferred` | useful, but not worth immediate extraction |
| `fork-only` | intentionally retained in the fork |

## Current Candidates

| Component | Candidate | Status | Notes |
|---|---|---|---|
| `nix-vm-test` | Fedora 42 and Rocky 10.1 image definitions | `upstreamed` | landed in `numtide/nix-vm-test#172`; local work is re-pin/cleanup only |
| `ghostty` | macOS display-link restart fix | `prepared` | small carried patch, low conceptual risk; good first manual candidate |
| `ghostty` | color scheme mode 2031 DECRPM reporting | `prepared` | standards-aligned behavior fix; likely separable from cmux-specific hooks |
| `ghostty` | TerminalStream APC handling | `identified` | useful for libghostty integrators; needs isolation from cmux packaging context |
| `ghostty` | OSC 99 notification parser | `prepared` | documented in `docs/ghostty-fork.md`; protocol feature, likely needs careful parser API review |
| `ghostty` | resize stale-frame mitigation | `identified` | useful, but conflict-prone and larger |
| `ghostty` | Linux embedded platform variant | `identified` | relevant to Linux strategy, but high-touch; coordinate manually with upstream platform work |
| `ghostty` | cmux theme picker helper hooks | `fork-only` | host-app integration, not a good upstream slice |
| `ghostty` | macos-background-from-layer config flag | `fork-only` | cmux renderer integration and visual-hosting contract |
| `ghostty` | keyboard copy-mode selection C API re-export | `fork-only` | compatibility shim for current cmux keyboard copy mode |
| `vendor/bonsplit` | minimal fork delta | `identified` | audit after bump to `origin/main`; no agent-authored upstream work by default |
| `vendor/zig-ctap2` | standalone Zig library packaging/docs polish | `prepared` | handled as a standalone project, not a cmux PR; current checkout has a dual MIT/Zlib license |
| `vendor/zig-keychain` | standalone Zig library packaging/docs polish | `prepared` | handled as a standalone project, not a cmux PR; current checkout has a dual MIT/Zlib license |
| `vendor/zig-crypto` | standalone Zig library packaging/docs polish | `prepared` | handled as a standalone project, not a cmux PR; current checkout has a dual MIT/Zlib license |
| `vendor/zig-notify` | standalone Zig library packaging/docs polish | `prepared` | handled as a standalone project, not a cmux PR; current checkout has a dual MIT/Zlib license |
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

## Human Prep Cadence

Upstream preparation should happen on a small, deliberate cadence:

1. Run a weekly read-only drift check for `cmux`, `ghostty`, and
   `vendor/bonsplit`.
2. Pick at most one upstream candidate per prep session.
3. Create an owned handoff artifact before any external submission:
   - target repo and proposed title
   - exact branch or commit range
   - rationale and expected upstream benefit
   - validation performed or still needed
   - copy-ready issue or PR text for Jess to submit manually
4. Keep Ghostty, Bonsplit, and Manaflow/cmux relationship discussions separate
   unless Jess explicitly chooses to combine them.
5. Do not let upstream prep displace the Linux QA and packaging critical path.

Current first candidates by expected goodwill-to-risk ratio:

1. Ghostty display-link restart fix
2. Ghostty color scheme mode 2031 reporting
3. Ghostty TerminalStream APC handling
4. Ghostty OSC 99 parser

The Linux embedded platform variant is intentionally later. It is valuable, but
it intersects with upstream platform work and should get focused human review.

## License Checkpoint

Before preparing any upstream or downstream handoff, verify the license file in
the exact repo or submodule being referenced. Current checkout state:

- `ghostty` is MIT licensed
- `vendor/bonsplit` has an MIT `LICENSE`
- `vendor/ctap2`, `vendor/zig-crypto`, `vendor/zig-keychain`, and
  `vendor/zig-notify` each have dual MIT/Zlib `LICENSE` files

Do not carry stale "missing license" notes forward without re-checking the
submodule in the current checkout.

## Relationship To The Linux Program

This ledger is parallel to Linux delivery.

The Linux program wins scheduling priority over upstream preparation whenever
they conflict.
