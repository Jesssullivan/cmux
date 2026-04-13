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

1. validate Tier A distros (`Ubuntu 24.04`, `Debian 12`, `Fedora 42`)
2. validate Rocky 10 as terminal-first
3. keep Linux delivery separate from manual upstream correspondence
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
