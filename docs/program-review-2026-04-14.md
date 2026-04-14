# Program Review And QA Punchlist

This document is a time-boxed program review for the native Linux `cmux`
initiative as of `2026-04-14`.

It is intentionally practical. The goal is to answer:

1. what is actually healthy
2. what is still incomplete
3. what must be tested next on real Linux VMs and hosts
4. which upstream-prep slices are worth isolating without putting them on the
   current Linux critical path

This review does not authorize external submission work.

- agents may identify, isolate, document, and test candidate slices
- agents do not contact upstreams or non-`Jesssullivan` / non-`tinyland-inc`
  repos
- manual upstream correspondence remains with Jess

Execution follow-up:

- [linux-work-week-2026-04-14.md](/Users/jess/git/cmux/docs/linux-work-week-2026-04-14.md:1)
- [linear-qa-shard-punchlist.md](/Users/jess/git/cmux/docs/linear-qa-shard-punchlist.md:1)

## Executive Readout

The project is in a stronger state than the public tracker suggests.

- `cmux` itself is healthy and current versus `upstream/main`
- Linux CI is green across the hosted container/build matrix
- fresh-install KVM package validation is real and now gates Linux release upload
- dependency hygiene is mostly clean
- `ghostty` is the only major carried dependency with meaningful upstream
  ingestion pressure

The main blocker has shifted.

- the blocker is no longer “can native Linux cmux build?”
- the blocker is “can the project prove the right capability level on the right
  distros without overstating what is finished?”

## Current Reality

### Repo and dependency health

- `cmux` is ahead of `upstream/main` and not behind it
- `ghostty` fork ancestry is repaired and the checked-in pin is reachable from
  fork `main`
- `ghostty` remains the largest carried delta and the main upstream-ingestion
  watchlist
- `vendor/bonsplit`, `vendor/ctap2`, `vendor/zig-crypto`,
  `vendor/zig-keychain`, and `vendor/zig-notify` are all currently healthy from
  a pin/ancestry perspective
- `homebrew-cmux` is slightly behind its tracked upstream and is packaging debt,
  not a Linux blocker

Primary references:

- [component-portfolio.md](/Users/jess/git/cmux/docs/component-portfolio.md:18)
- [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:31)
- [ghostty-fork.md](/Users/jess/git/cmux/docs/ghostty-fork.md:1)

### CI, builder, and cache posture

- `Jesssullivan/cmux` intentionally stays on Magic Nix Cache
- `tinyland-inc/lab` remains the FlakeHub-heavy org-owned builder lane
- Linux hosted CI is green across `Ubuntu 24.04`, `Fedora 42`, `Rocky 10`,
  `Debian 12` baseline, `Arch`, and the Linux vendor-library lane
- self-hosted KVM package-install tests currently cover `Ubuntu 24.04`,
  `Debian 12`, and `Rocky 9` as an RPM-path proxy
- tagged Linux releases now validate the just-built `DEB` and `RPM` artifacts in
  fresh distro VMs before Linux upload

Primary references:

- [program-status.md](/Users/jess/git/cmux/docs/program-status.md:99)
- [linux-packaging-cd-plan.md](/Users/jess/git/cmux/docs/linux-packaging-cd-plan.md:13)
- [test-distro.yml](/Users/jess/git/cmux/.github/workflows/test-distro.yml:1)
- [release-linux.yml](/Users/jess/git/cmux/.github/workflows/release-linux.yml:309)

### KVM / distro-test reality

Current KVM package-install validation is real, but not complete.

What is working:

- exact release artifact validation can be run from a release tag
- the checked-in manifest path is now replaceable by an exact release override
- Linux release upload waits for self-hosted distro validation
- post-install linker resolution is checked with `ldd`

What is not complete:

- KVM tests do not run on untrusted PRs by design
- KVM coverage still stops at `Ubuntu 24.04`, `Debian 12`, and `Rocky 9` proxy
- `Fedora 42` and `Rocky 10` VM package-install proof are still blocked by
  upstream `nix-vm-test` image coverage, not by repo-local indecision

Primary references:

- [nix/tests-distro.nix](/Users/jess/git/cmux/nix/tests-distro.nix:1)
- [test-distro.yml](/Users/jess/git/cmux/.github/workflows/test-distro.yml:3)

## Actual Linux Parity State

### Implemented enough to validate

- terminal surfaces and split tree are real enough to validate on live distros
- browser panel support exists on WebKit-capable builds
- notifications and logind integration exist in meaningful part
- Linux socket/API exists in meaningful part

These lanes need proof more than architecture work.

Primary reference:

- [linux-parity-matrix.md](/Users/jess/git/cmux/docs/linux-parity-matrix.md:18)

### Not ready for promotion

These are the surfaces that still need explicit downgrade language and focused
follow-up work:

1. WebAuthn bridge
   The browser panel installs the bridge, but the native handler is still a
   stub. `onScriptMessage` still contains only `TODO`s and a log line.

   References:
   - [browser.zig](/Users/jess/git/cmux/cmux-linux/src/browser.zig:105)
   - [webauthn_bridge.zig](/Users/jess/git/cmux/cmux-linux/src/webauthn_bridge.zig:61)

2. Socket/control-plane parity
   `surface.send_text`, `surface.read_text`, `pane.break`, `pane.join`,
   `surface.move`, and `surface.reorder` are still placeholders or success-only
   stubs. Linux host callbacks for libghostty actions and clipboard are also
   mostly no-op.

   References:
   - [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:957)
   - [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:1120)
   - [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:1171)
   - [app.zig](/Users/jess/git/cmux/cmux-linux/src/app.zig:11)

3. Session restore
   Save-path scaffolding exists, but restore still returns `false`.

   Reference:
   - [session.zig](/Users/jess/git/cmux/cmux-linux/src/session.zig:221)

4. Headless/server mode
   `cmux-term` is still placeholder-only and does not yet initialize a real
   headless terminal runtime.

   Reference:
   - [main_headless.zig](/Users/jess/git/cmux/cmux-linux/src/main_headless.zig:23)

## Tracker And Milestone Reality

The planning surface is smaller than the open milestone list makes it look.

### Open issues that still matter

- `#55` `Epic: De-Attestation & Linux Porting Roadmap`
- `#76` `RFC: Linux client naming — cmux vs lmux`
- `#187` `ci(distro): Rocky 10 — track upstream nix-vm-test support`
- `#199` `audit: fork landscape, novel libraries, and upstream PR opportunities`
- `#201` `feat(cmuxd-remote): add TCP listener mode for Tailnet direct connections`

### Tracker problems

1. `#55` is stale
   It still reads like an early Linux MVP roadmap and still treats many current
   capabilities as future milestone items rather than implemented-but-unproven
   surfaces.

2. `#187` is stale
   It still says Rocky 10 has not been released yet, which is no longer true.
   The real blocker is upstream `nix-vm-test` coverage, not distro availability.

3. `#199` is stale in divergence numbers and still includes manual-upstream
   action items that should remain outside agent scope.

4. `#76` is a valid RFC, but it is non-blocking and should stay that way.

5. `#201` is a real future lane, but it is not on the Linux packaging/parity
   critical path.

### Milestone problems

Only one open milestone still has live open work.

- `M12 — QEMU Distro Testing` is the only open milestone with open issues
- `M6`, `M7`, `M8`, and `M9` are still open with `0` open issues each

Operational interpretation:

- milestone closure and renaming are now repo hygiene tasks
- the active milestone in practice is the distro-testing lane

## Participating Library Review

### `ghostty`

Current read:

- highest-churn carried dependency
- current pin is healthy from a fork-ancestry perspective
- still materially behind upstream while carrying meaningful local work

This is the only participating library that should stay on the active
ingestion-risk watchlist.

### `vendor/bonsplit`

Current read:

- low-delta
- effectively maintenance-level
- worth isolating only if a very small fork-only delta remains

### `vendor/ctap2`

Current read:

- repo hygiene is healthy
- standalone issue tracker already shows Linux transport/testing still matters
- the open item that matters most here is Linux hidraw end-to-end testing

### `vendor/zig-keychain`

Current read:

- repo hygiene is healthy
- remaining work is distro/runtime proof, not repo rescue

### `vendor/zig-crypto`

Current read:

- healthy and not on the critical path

### `vendor/zig-notify`

Current read:

- healthy
- remaining work is real notification proof on Linux desktops

### `homebrew-cmux`

Current read:

- minor sync debt only
- not relevant to the Linux proof critical path

## RFC / Upstream-Prep Opportunities

These should be kept deliberately small and parallel to Linux delivery.

### Best small-slice candidates

1. `ghostty`: OSC 99 notification parser
2. `ghostty`: macOS display-link restart fix
3. `vendor/bonsplit`: any remaining minimal fork delta after sync
4. `vendor/zig-ctap2`, `vendor/zig-keychain`, `vendor/zig-crypto`:
   packaging/docs polish as standalone library work

Primary reference:

- [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:31)

### Not good extraction candidates right now

- Linux WebAuthn bridge work
- Linux socket/control-plane parity work
- session restore and headless runtime work
- distro-testing harness changes tightly coupled to current release automation

These are still on the product critical path and should not be decomposed for
manual submission before they stabilize.

## QA Punchlist

### A. KVM / package-install punchlist

1. Keep the current release-gated KVM path stable on:
   - `Ubuntu 24.04`
   - `Debian 12`
   - `Rocky 9` RPM proxy
2. Add exact-artifact validation as the standard pre-release confidence path for
   every Linux tag.
3. Decide whether to extend the current harness or add a second VM path for:
   - `Fedora 42`
   - `Rocky 10`
4. Retire `Rocky 9` as the proxy once `Rocky 10` fresh-install proof exists.
5. Decide whether Debian should keep consuming the broad-feature `DEB` or needs
   an explicit baseline/no-WebKit artifact.

### B. Direct VM feature QA punchlist

Run these on fresh VMs or real distro hosts and record outcomes explicitly.

#### Ubuntu 24.04

- install release `DEB`
- launch app
- verify terminal/split smoke
- verify socket baseline
- verify browser open/navigate/focus/find/devtools
- verify notification delivery
- verify lock/unlock does not break terminal state
- verify current session-restore behavior matches documented `partial`

#### Fedora 42

- install release `RPM`
- launch app
- verify terminal/split smoke
- verify socket baseline
- verify browser open/navigate/focus/find/devtools
- verify notification delivery
- verify lock/unlock behavior

#### Debian 12

- install release `DEB`
- launch app
- verify terminal and socket baseline
- record browser/WebAuthn status explicitly instead of assuming parity

#### Rocky 10

- validate terminal-first path directly
- verify package/runtime path
- verify splits/focus/socket baseline
- verify browser commands fail clearly if `-Dno-webkit`
- record whether Flatpak becomes the only practical broad-feature path

### C. Parity implementation punchlist

1. Finish Linux WebAuthn bridge request handling:
   - parse message
   - dispatch CTAP2 work
   - reply to JavaScript
   - prove one real hardware-backed ceremony on a Tier A distro
2. Implement real Linux control-plane gaps:
   - `surface.send_text`
   - `surface.read_text`
   - `pane.break`
   - `pane.join`
   - `surface.move`
   - `surface.reorder`
   - host action/clipboard callbacks
3. Either implement Linux restore enough to promote it, or keep the docs and
   release metadata conservative
4. Either implement `cmux-term` enough to promote it to `partial`, or keep it
   clearly out of release claims

### D. Tracker / milestone punchlist

1. Rewrite `#55` as the current Linux umbrella:
   - distro proof
   - package taxonomy
   - parity gaps
   - feature QA
2. Refresh `#187` to say:
   - Rocky 10 is GA
   - blocker is upstream `nix-vm-test`
   - Rocky 9 is current RPM-path proxy only
3. Refresh `#199` so it reflects current divergence and manual-upstream policy
4. Keep `#76` explicitly non-blocking
5. Keep `#201` separate from Linux distro delivery
6. Close, rename, or archive stale open milestones with zero open issues:
   - `M6`
   - `M7`
   - `M8`
   - `M9`

### E. Reintegration / future proposal punchlist

This is not a current delivery blocker, but it is worth structuring now.

Questions to settle after Linux proof is stronger:

1. When does “Linux native cmux” become strong enough to justify a
   `cmux`/`lmux` naming decision?
2. Which Linux deltas are fork-only versus reintegration candidates?
3. Which participating libraries are mature enough to be treated as stable
   external building blocks?
4. Which carried behaviors in `ghostty` or `bonsplit` should stay local until
   the Linux product surface itself settles?

## Recommended Near-Term Sequence

1. Merge `#205`
2. Refresh tracker issue bodies and stale milestones
3. Run direct VM feature QA on `Ubuntu 24.04` and `Fedora 42`
4. Record explicit Debian 12 browser status
5. Decide how to get fresh-install proof for `Fedora 42` and `Rocky 10`
6. Open or isolate dedicated work items for:
   - Linux WebAuthn bridge completion
   - Linux socket/control-plane parity
   - Linux restore/headless runtime
7. Keep upstream-prep work parallel and small; do not let it displace distro
   proof

## Bottom Line

The program is in a credible delivery phase.

- repo hygiene is broadly good
- package/build CI is broadly good
- KVM distro validation is real
- the carried library graph is mostly healthy

The remaining work is now mostly about truth, proof, and scope control:

- truthful parity language
- fresh-install proof on the intended distros
- direct feature QA on real VMs and hosts
- small, disciplined upstream-prep slices that do not disrupt Linux delivery
