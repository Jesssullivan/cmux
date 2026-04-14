# Linux Parity Matrix

This is the working parity matrix for native Linux `cmux`.

It is intentionally conservative:

- `full` means implemented and validated
- `partial` means implemented in meaningful part, but still missing behavior
  and/or validation
- `distro-specific` means availability depends on distro or packaging mode
- `unsupported` means not present yet

Do not promote a capability based on source presence alone. Promotion requires
runtime proof, CI proof, or explicit manual validation.

## Matrix

| Capability | Current state | Evidence | Distro note | Next proof needed |
|---|---|---|---|---|
| Terminal surfaces and split tree | `partial` | [surface.zig](/Users/jess/git/cmux/cmux-linux/src/surface.zig:1), [split_tree.zig](/Users/jess/git/cmux/cmux-linux/src/split_tree.zig:1), [workspace.zig](/Users/jess/git/cmux/cmux-linux/src/workspace.zig:1), [tab_manager.zig](/Users/jess/git/cmux/cmux-linux/src/tab_manager.zig:1) | all Linux targets | runtime/UI validation across Ubuntu 24.04 and Fedora 42, plus Debian/Rocky baseline proof |
| Socket/API control plane | `partial` | [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:1), [app.zig](/Users/jess/git/cmux/cmux-linux/src/app.zig:1) | all Linux targets; `surface.send_text` and `surface.read_text` now exist, but structural verbs and host callbacks are still incomplete | validate Linux `surface.send_text` and `surface.read_text`, then implement and validate `pane.break`, `pane.join`, `surface.move`, `surface.reorder`, and Linux action/clipboard callbacks |
| Browser panel | `distro-specific` | [browser.zig](/Users/jess/git/cmux/cmux-linux/src/browser.zig:1), [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:232) | unavailable in `-Dno-webkit` builds; Rocky is currently constrained | browser smoke on Ubuntu, Debian, Fedora |
| Browser navigation/focus commands | `distro-specific` | [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:232) | same WebKit constraint as browser panel | command-level browser smoke |
| Browser devtools and find | `distro-specific` | [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:240), [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:243) | same WebKit constraint as browser panel | interactive validation on Ubuntu 24.04 and Fedora 42 |
| WebAuthn bridge | `unsupported` | [webauthn_bridge.zig](/Users/jess/git/cmux/cmux-linux/src/webauthn_bridge.zig:1), [browser.zig](/Users/jess/git/cmux/cmux-linux/src/browser.zig:9) | browser availability is distro-specific, and the native message handler is still a stub | implement request parsing/dispatch/reply and run one hardware-backed ceremony on a Tier A distro |
| Persistent cookies | `distro-specific` | [browser.zig](/Users/jess/git/cmux/cmux-linux/src/browser.zig:170) | same WebKit constraint as browser panel | cookie persistence/import validation |
| Notifications | `partial` | [notifications.zig](/Users/jess/git/cmux/cmux-linux/src/notifications.zig:1), [main.zig](/Users/jess/git/cmux/cmux-linux/src/main.zig:56) | all Linux targets | desktop notification smoke on GNOME/Wayland |
| Session lock/unlock integration | `partial` | [logind.zig](/Users/jess/git/cmux/cmux-linux/src/logind.zig:1), [main.zig](/Users/jess/git/cmux/cmux-linux/src/main.zig:30) | systemd/logind environments | lock/unlock runtime verification |
| Session save/restore | `partial` | [session.zig](/Users/jess/git/cmux/cmux-linux/src/session.zig:150), [session.zig](/Users/jess/git/cmux/cmux-linux/src/session.zig:245) | save path exists, but restore currently falls back to a fresh session | restore implementation proof; current file shows restore returns `false` |
| Headless / server mode (`cmux-term`) | `unsupported` | [main_headless.zig](/Users/jess/git/cmux/cmux-linux/src/main_headless.zig:1) | intended for SSH/container use, but current entrypoint is placeholder-only | implement libghostty/socket/PTY runtime and prove one real headless workflow |
| Remote SSH daemon path | `partial` | [daemon/remote/README.md](/Users/jess/git/cmux/daemon/remote/README.md:1), [main.go](/Users/jess/git/cmux/daemon/remote/cmd/cmuxd-remote/main.go:125) | cross-platform daemon, but current transport is stdio/SSH-oriented | Linux-native remote flow validation |
| Tailnet direct remote transport | `unsupported` | [README.md](/Users/jess/git/cmux/daemon/remote/README.md:8) documents `serve --stdio` only | future enhancement | implementation of direct listener mode |
| Distro package install tests | `partial` | [nix/tests-distro.nix](/Users/jess/git/cmux/nix/tests-distro.nix:1), [.github/workflows/test-distro.yml](/Users/jess/git/cmux/.github/workflows/test-distro.yml:1) | Debian 12 and Ubuntu 24.04 are covered directly; Rocky 9 is currently an RPM-path proxy while Fedora 42 and Rocky 10 VM package tests remain blocked by `nix-vm-test` image support; current KVM tests run on push/manual, not as PR-gating | expand the VM package-install matrix, retire Rocky 9 as the proxy, and decide how fresh-install proof should gate release confidence |
| Container build validation | `partial` | [.github/workflows/linux-ci.yml](/Users/jess/git/cmux/.github/workflows/linux-ci.yml:1) | Fedora 42 and Rocky 10 already have containerized build/static validation; this is useful but not the same as user-facing package install proof | keep container builds green and pair them with package/runtime proof |

## Distro Interpretation

### Broad-Feature Targets

These should move toward broad feature parity:

- Ubuntu 24.04
- Fedora 42

### Package / Runtime Baseline

These are important supported distros, but the repo should record browser
status explicitly instead of assuming broad feature parity:

- Debian 12

### Constrained Targets

These are supported with explicit constraints:

- Rocky 10: terminal-first until browser packaging is practical

## Promotion Rules

Only promote a row when the proof exists.

Examples:

- source file present: not enough
- unit test only: usually not enough
- package installs and binary launches: enough for package/runtime rows
- browser/WebAuthn/manual ceremony: enough for browser-related rows
- repeated use on a real distro host: enough if documented
