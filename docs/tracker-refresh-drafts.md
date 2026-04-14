# Tracker Refresh Drafts

These are ready-to-edit draft updates for the current `Jesssullivan/cmux`
issues. They are intentionally local prep material.

Use them as source text for manual issue edits or comments.

## `#187` Rocky 10

Suggested replacement body:

```md
## Summary

Track Rocky Linux 10 support for Linux-native `cmux`.

Rocky 10 itself is available. The remaining blockers are:

1. automation support in `nix-vm-test`
2. clearly documenting Rocky as a constrained distro for browser parity

## Current State

- Rocky 10 is GA
- `nix-vm-test` support is still the automation gap
- Rocky 9 is still serving as a temporary RPM-install proxy in VM tests
- `cmux-linux` can already build in a constrained mode without WebKitGTK
- Rocky should currently be treated as a **terminal-first** target, not a full browser-parity target

## What This Issue Covers

- Rocky 10 package-install validation
- Rocky 10 runtime validation for terminal-first workflows
- automation support once `nix-vm-test` or an equivalent path is ready

## What This Issue Does Not Cover

- treating Rocky as the primary browser-validation distro
- blocking Linux delivery until Rocky reaches full parity

## References

- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-validation-checklist.md`

## Exit Criteria

- Rocky 10 package/runtime path is validated
- Rocky 10 terminal-first workflow is validated
- Rocky’s browser limitation is explicitly documented
```

## `#55` Linux Program Epic

Suggested update comment:

```md
This epic needs to be read as a program umbrella now, not as a greenfield architecture note.

Current repo state:

- `cmux-linux` already has substantial implementation in-tree
- the remaining work is less about initial architecture and more about:
  - parity classification
  - distro validation
  - packaging proof
  - explicit constrained-distro handling for Rocky 10

The current execution docs are now:

- `docs/component-portfolio.md`
- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
- `docs/linux-validation-checklist.md`

The critical-path interpretation is:

1. validate broad-feature distros (`Ubuntu 24.04`, `Fedora 42`)
2. validate `Debian 12` as a package/runtime baseline and record browser status explicitly
3. validate `Rocky 10` as terminal-first
4. keep Linux delivery separate from manual upstream correspondence
```

## `#76` Naming RFC

Suggested update comment:

```md
This RFC is still valid, but it is no longer on the critical path.

The current blocker set for Linux-native `cmux` is:

- dependency hygiene
- parity classification
- distro validation
- packaging proof

Naming should be treated as non-blocking for Linux delivery until those are in a healthier state.

References:

- `docs/component-portfolio.md`
- `docs/linux-program-plan.md`
- `docs/linux-parity-matrix.md`
```

## `#199` Fork Landscape

Suggested update comment:

```md
This issue remains useful, but it should stay explicitly parallel to Linux delivery.

The current checked-in docs for this lane are:

- `docs/component-portfolio.md`
- `docs/fork-landscape.md`
- `docs/upstream-ingestion-playbook.md`
- `docs/upstream-candidate-ledger.md`

Important boundary:

- upstreamable slices are tracked and prepared locally
- upstream PR/MR submission is manual
- this lane should not block Linux parity or distro validation
```

## Proposed issue: Linux WebAuthn bridge completion

Suggested issue body:

```md
## Summary

Linux browser panels currently install a WebAuthn bridge, but the native handler
is still stubbed.

This is an implementation gap, not just a validation gap.

## Current State

- browser panel setup installs the bridge
- the native message handler still has TODOs for request parsing, CTAP2 dispatch,
  and JS reply handling
- current parity docs should treat Linux WebAuthn as not yet supported end-to-end

## Scope

- parse WebKit bridge messages
- route requests through the Linux CTAP2 path
- reply to the page with success/error responses
- run one real hardware-backed ceremony on a Tier A distro

## Exit Criteria

- Linux WebAuthn request handling is implemented end-to-end
- one real hardware-backed ceremony succeeds on Ubuntu 24.04 or Fedora 42
- parity docs can move WebAuthn above `unsupported`
```

## Proposed issue: Linux socket/control-plane parity audit

Suggested issue body:

```md
## Summary

Linux socket/API coverage is materially broader on paper than in actual
implementation.

Several important verbs still acknowledge success without performing the real
behavior, and some host callbacks are still no-op.

## Current Gaps

- `surface.send_text`
- `surface.read_text`
- `pane.break`
- `pane.join`
- `surface.move`
- `surface.reorder`
- Linux action/clipboard host callbacks

## Scope

- audit Linux socket/API coverage against the macOS control plane
- implement the highest-value stubbed verbs first
- document any intentionally deferred commands explicitly

## Exit Criteria

- high-value stubbed verbs are either implemented or explicitly documented as unsupported
- Linux parity docs stop overstating socket/control-plane readiness
- one validated Linux distro exercises the implemented command surface
```

## Proposed issue: Linux session restore and headless runtime

Suggested issue body:

```md
## Summary

Linux session save/restore and `cmux-term` headless mode are both still below
the promotable line.

## Current State

- session restore still returns `false` after loading a valid snapshot
- `cmux-term` is still a placeholder entrypoint and does not start a real
  terminal/socket runtime

## Scope

- decide whether restore and headless mode should stay one lane or split later
- implement restore behavior or narrow the documented promise
- implement a real headless runtime only if it remains part of the supported
  Linux surface

## Exit Criteria

- session restore status is explicit and proven
- `cmux-term` is either a real supported mode or explicitly documented as deferred
```

## `#201` Tailnet Direct Remote Sessions

Suggested update comment:

```md
This remains a valid enhancement lane, but it is not a Linux distro-validation blocker.

Current state:

- `cmuxd-remote` still documents and implements the `serve --stdio` transport path
- direct Tailnet listener mode is still future work

This issue should be treated as:

- remote/fleet enhancement
- parallel to the Linux validation program

References:

- `docs/linux-program-plan.md`
- `daemon/remote/README.md`
```

## Milestone Cleanup

Suggested action:

```md
Milestone hygiene is behind the codebase.

Current state:

- `M6`, `M7`, `M8`, and `M9` are still open with `0` open issues
- `M12 — QEMU Distro Testing` is the only milestone with active open work

Suggested cleanup:

1. close `M6`, `M7`, `M8`, and `M9` after confirming they are fully historical
2. keep `M12` as the active validation milestone
3. if a broader Linux milestone is still useful, create one that reflects parity + distro proof rather than older architecture phases
```
