# Ghostty Fork Changes (Jesssullivan/ghostty)

This repo uses a fork of Ghostty for local patches that aren't upstream yet.
The submodule now points to `Jesssullivan/ghostty` (forked from `manaflow-ai/ghostty`).
When we change the fork, update this document and the parent submodule SHA.

## Fork update checklist

1) Make changes in `ghostty/` or `ghostty-dev/` (the Jesssullivan/ghostty clone).
2) Commit and push to `Jesssullivan/ghostty`.
3) Update this file with the new change summary + conflict notes.
4) In the parent repo: `git add ghostty` and commit the submodule SHA.

## Current fork changes

Fork rebased onto upstream `main` at `3509ccf78` (`v1.3.1-457-g3509ccf78`) on March 30, 2026.
Merged upstream through `0a492fdb3` (build: add pkg-config static linking support) on April 4, 2026.
Synced again with upstream on April 11, 2026 (through `d289f66f`).
Synced again with upstream on April 6, 2026 (PR #11, through `ca7516bea`).
Synced again with upstream on April 25, 2026 (PR #12, through `c47a8091f`).

As of April 18, 2026:

- Current cmux pinned fork head: `e0f650766`
- Current pushed fork `main`: `e0f650766`
- Current upstream `main`: `ca7516bea`

As of April 25, 2026:

- Current checked-in cmux parent pin: `e0f650766`
- Current pushed fork `main`: `9b1d5d389`
- Current upstream `main`: `b613ffcfd`
- Fork drift versus upstream: 64 commits ahead, 33 commits behind
- cmux cannot move the parent pin to `9b1d5d389` yet: the ReleaseFast
  universal GhosttyKit build exposed a missing `.manual` case in
  `src/termio/backend.zig`.
- The build fix is staged in `Jesssullivan/ghostty#13` at `9456e87a0`. The
  GhosttyKit-only build passes there with the macOS 15.4 SDK shim and
  `-Demit-macos-app=false`; the full default build still fails later in the
  optional macOS app bundle step while resolving a Swift package revision.
- The newest 33 upstream commits after `c47a8091f` remain intentionally outside
  the parent-pin bump. A dry merge check against `b613ffcfd` succeeds
  textually, but `src/Surface.zig` and `src/config/Config.zig` both changed on
  both sides and need a semantic review before the next fork sync.

### Current ownership posture

`Jesssullivan/ghostty#13` is an owned-fork maintenance PR, not a planned
`ghostty-org/ghostty` upstream submission.

The immediate goal is to keep the `Jesssullivan/ghostty` fork buildable for the
cmux/lmux parent pin after the April 25 upstream sync. Vouch or other upstream
social-gating concerns should not turn this into a `ghostty-org` contribution
lane by default.

Current policy:

- keep PR #13 in `Jesssullivan/ghostty`
- merge it into the owned fork's canonical `main` when the owned-repo gate is
  clear or Jess manually resolves the owned-fork gate
- move the cmux parent `ghostty` pointer only after the chosen commit is
  reachable from `Jesssullivan/ghostty/main`
- do not prepare or submit this specific build fix to `ghostty-org` unless Jess
  explicitly chooses that later

Ghostty upstream candidates remain tracked in `docs/upstream-candidate-ledger.md`
as future human handoff possibilities, not as part of the urgent parent-pin
work.

Branch cleanup (April 18, 2026): deleted 15 stale local branches and 16 stale
remote branches from the fork. Only `main` remains. All feature/sync branches
were already merged or superseded by upstream syncs.

### 1) macOS display link restart on display changes

- Commit: `05cf31b38` (macos: restart display link after display ID change)
- Files:
  - `src/renderer/generic.zig`
- Summary:
  - Restarts the CVDisplayLink when `setMacOSDisplayID` updates the current CGDisplay.
  - Prevents a rare state where vsync is "running" but no callbacks arrive, which can look like a frozen surface until focus/occlusion changes.

### 2) macOS resize stale-frame mitigation

The resize commits are grouped by feature because they touch the same stale-frame replay path and
tend to conflict together during rebases.

- Commits:
  - `a3588ac53` (macos: reduce transient blank/scaled frames during resize)
  - `9ba54a68c` (macos: keep top-left gravity for stale-frame replay)
- Files:
  - `pkg/macos/animation.zig`
  - `src/Surface.zig`
  - `src/apprt/embedded.zig`
  - `src/renderer/Metal.zig`
  - `src/renderer/generic.zig`
  - `src/renderer/metal/IOSurfaceLayer.zig`
- Summary:
  - Replays the last rendered frame during resize and keeps its geometry anchored correctly.
  - Reduces transient blank or scaled frames while a macOS window is being resized.

### 3) OSC 99 (kitty) notification parser

- Commits:
  - `2033ffebc` (Add OSC 99 notification parser)
  - `a75615992` (Fix OSC 99 parser for upstream API changes)
- Files:
  - `src/terminal/osc.zig`
  - `src/terminal/osc/parsers.zig`
  - `src/terminal/osc/parsers/kitty_notification.zig`
- Summary:
  - Adds a parser for kitty OSC 99 notifications and wires it into the OSC dispatcher.
  - Adapts the parser to upstream's newer capture API so the cmux OSC 99 hook survives the March 30 upstream sync.

### 4) cmux theme picker helper hooks

- Commits:
  - `1da7281fd` (Add cmux theme picker helper hooks)
  - `ea482b73e` (Fix cmux theme picker preview writes)
  - `c7ab66056` (Improve cmux theme picker footer contrast)
  - `c49f69f7b` (Respect system theme in cmux picker)
  - `599b0ff43` (Skip theme detection in cmux picker)
  - `b75388d95` (Match Ghostty theme picker startup)
  - `f985d2d04` (Harden cmux theme override writes)
- Files:
  - `build.zig`
  - `src/cli/list_themes.zig`
  - `src/main_ghostty.zig`
- Summary:
  - Adds a `zig build cli-helper` step so cmux can bundle Ghostty's CLI helper binary on macOS.
  - Lets `+list-themes` switch into a cmux-managed mode via env vars, writing the cmux theme override file and posting the existing cmux reload notification for live app-wide preview.
  - Keeps the preview UI readable in light mode, matches upstream picker startup behavior, and hardens writes to the cmux-managed theme override file.

### 5) Color scheme mode 2031 reporting

- Commits:
  - `2be58ee0e` (Fix DECRPM mode 2031 reporting wrong color scheme)
  - `74709c29b` (Send initial color scheme report when mode 2031 is enabled)
- Files:
  - `src/Surface.zig`
  - `src/termio/stream_handler.zig`
- Summary:
  - Keeps Ghostty's mode 2031 color-scheme response aligned with the surface's actual conditional state after config reloads.
  - Sends the initial DSR 997 report as soon as mode 2031 is enabled, which cmux relies on for immediate color-scheme awareness.

### 6) Keyboard copy mode selection C API

- Commit: `0b231db94` (Re-export cmux selection APIs removed from upstream)
- Files:
  - `include/ghostty.h`
  - `src/Surface.zig`
  - `src/apprt/embedded.zig`
- Summary:
  - Restores `ghostty_surface_select_cursor_cell` and `ghostty_surface_clear_selection`.
  - Keeps cmux keyboard copy mode working against the refreshed Ghostty base after upstream removed those exports.

### 7) macos-background-from-layer config flag

- Commit: `ae3cc5d29` (Restore macOS layer background hook)
- Files:
  - `src/config/Config.zig`
  - `src/renderer/generic.zig`
- Summary:
  - Adds a `macos-background-from-layer` bool config (default false).
  - When true, sets `bg_color[3] = 0` in the per-frame uniform update so the Metal renderer skips the full-screen background fill.
  - Allows the host app to provide the terminal background via `CALayer.backgroundColor` for instant coverage during view resizes, avoiding alpha double-stacking.
  - Replays the layer-background restore on top of the refreshed Ghostty base so cmux keeps the resize-coverage fix after the upstream sync.

### 8) TerminalStream kitty graphics APC handling

- Commit: `a8e92c9c5` (terminal: add APC handler to stream_terminal)
- Files:
  - `src/terminal/stream_terminal.zig`
- Summary:
  - Wires `.apc_start`, `.apc_put`, and `.apc_end` through the shared APC parser in `TerminalStream`.
  - Restores kitty graphics execution and APC OK/error replies for the non-termio stream path used by cmux/libghostty integrations.

Fork main now carries the section 8 APC handling fix plus later upstream merges;
the current cmux pin is the head listed above.

## Upstreamed fork changes

### cursor-click-to-move respects OSC 133 click-to-move

- Was local in the fork as `10a585754`.
- Landed upstream as `bb646926f`, so it is no longer carried as a fork-only patch.

### zsh prompt redraw follow-ups

- Were local in the fork as `8ade43ce5`, `0cf559581`, `312c7b23a`, and `404a3f175`.
- Dropped during the March 30, 2026 rebase because newer Ghostty prompt-marking changes on the refreshed base superseded these fork-only zsh redraw patches, so cmux no longer carries them separately.

### initial focus seeding and DECSET 1004 startup behavior

- Was local in the fork as `c19c82bfd`.
- Dropped from the current pinned fork head when cmux removed the corresponding
  app-side initial focus seed and went back to post-create focus sync.

## Merge conflict notes

These files change frequently upstream; be careful when rebasing the fork:

- `src/terminal/osc.zig`
  - OSC dispatch logic moves often. Re-check the integration points for the OSC 99 parser and keep
    the newer `capture`/`captureTrailing()` API usage intact.

- `src/terminal/osc/parsers.zig`
  - Ensure `kitty_notification` stays imported after upstream parser reorganizations.

- `src/cli/list_themes.zig`
  - cmux now relies on the upstream picker UI plus local env-driven hooks for live preview and restore.
    If upstream reorganizes the preview loop or key handling, re-check the cmux mode path and keep the
    stock Ghostty behavior unchanged when the cmux env vars are absent.

- `src/apprt/embedded.zig`
  - Platform union and PlatformTag enum. If upstream adds new platforms (e.g. visionOS from PR #11010),
    merge conflict at the union/enum definition. Resolution: add both platform variants.

- `include/ghostty.h`
  - Platform enum and union. Same conflict potential as embedded.zig above.

- `build.zig`
  - Upstream's new wasm/libghostty work touched the same build graph. Keep the cmux-only `cli-helper`
    step wired in without regressing the upstream `lib-vt` or wasm build paths.

- `include/ghostty.h`, `src/Surface.zig`, `src/apprt/embedded.zig`
  - Upstream removed cmux-used selection exports. Preserve the re-exported
    `ghostty_surface_select_cursor_cell` and `ghostty_surface_clear_selection` functions.

- `src/renderer/generic.zig`
  - The `macos-background-from-layer` check sits next to the glass-style check in `updateFrame`.
    If upstream refactors the bg_color uniform update or the glass conditional, re-check that both
    paths still zero out `bg_color[3]` correctly.

- `src/Surface.zig`, `src/apprt/embedded.zig`, `macos/Sources/Ghostty/Surface View/SurfaceView.swift`
  - The initial `focused` plumbing has to stay aligned across the C config, embedded runtime surface,
    and macOS wrapper. If upstream refactors surface creation or post-create focus sync, re-check that
    background panes can start unfocused without synthesizing a focus-loss transition during creation.

- `src/termio/stream_handler.zig`
  - Keep DECSET 1004 enablement side-effect free. xterm-compatible focus reporting should only emit
    `CSI I` / `CSI O` on actual focus transitions, not immediately when the mode is enabled.

- `src/terminal/stream_terminal.zig`
  - Keep the APC handler wired into `.apc_start`, `.apc_put`, `.apc_end`, and preserve the
    `apcEnd()` response path so kitty graphics still reach `Terminal.kittyGraphics()` and reply via
    `write_pty`.

If you resolve a conflict, update this doc with what changed.

### 8) Linux embedded platform variant

- Commit: `e109d653c` (Jesssullivan/ghostty#1)
- Files: `include/ghostty.h`, `src/apprt/embedded.zig`
- Description: Add `GHOSTTY_PLATFORM_LINUX` to the embedded runtime Platform union,
  enabling libghostty surface creation on Linux. The linux platform carries an opaque
  `surface` pointer (e.g. GtkGLArea widget) following the same pattern as macOS (nsview)
  and iOS (uiview).
- Style reference: upstream ghostty-org/ghostty#11010 (visionOS platform variant)
- Conflict notes: merge conflict possible in Platform union and ghostty_platform_e enum
  if upstream adds new platforms concurrently.
