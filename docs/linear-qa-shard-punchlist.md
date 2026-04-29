# Linear-Ready QA Shard Punchlist

This document is a sharding sheet for QA testers and parallel implementation
work.

It is designed to be easy to split into Linear issues, GitHub issues, or manual
work assignments without re-deriving scope from the codebase.

Use it with:

- [linux-graphical-qa-machine-plan.md](/Users/jess/git/cmux/docs/linux-graphical-qa-machine-plan.md:1)
- [program-review-2026-04-14.md](/Users/jess/git/cmux/docs/program-review-2026-04-14.md:1)
- [distro-testing-readiness-plan.md](/Users/jess/git/cmux/docs/distro-testing-readiness-plan.md:1)
- [linux-work-week-2026-04-14.md](/Users/jess/git/cmux/docs/linux-work-week-2026-04-14.md:1)
- [linux-parity-matrix.md](/Users/jess/git/cmux/docs/linux-parity-matrix.md:1)
- [linux-validation-checklist.md](/Users/jess/git/cmux/docs/linux-validation-checklist.md:1)
- [component-portfolio.md](/Users/jess/git/cmux/docs/component-portfolio.md:1)
- [flakehub-qa-ownership-notes.md](/Users/jess/git/cmux/docs/flakehub-qa-ownership-notes.md:1)
- [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:1)

## Instructions For Sharding

Each shard should capture:

- exact distro or component under test
- exact artifact or branch under test
- pass/fail result
- evidence
- blocker if any
- follow-up recommendation

Preferred evidence:

- package filename and version
- image or VM version
- screenshots when UI behavior matters
- command output for install/runtime failures
- log excerpt for actionable failures

## Lane 1: Governance And Tracker Hygiene

### GOV-001 Merge Linux Hygiene Stack

- Type: repo hygiene
- Priority: `P0`
- Goal: merge `#205` and stabilize the repo on `main`
- References:
  - [PR #205](https://github.com/Jesssullivan/cmux/pull/205)
  - [program-status.md](/Users/jess/git/cmux/docs/program-status.md:1)
- Exit criteria:
  - `#205` merged
  - post-merge Linux CI remains green

### GOV-002 Refresh Linux Umbrella Issue

- Type: tracker
- Priority: `P0`
- Goal: refresh `#55` so it reflects current implementation and proof work
- References:
  - [tracker-refresh-drafts.md](/Users/jess/git/cmux/docs/tracker-refresh-drafts.md:54)
  - [linux-program-plan.md](/Users/jess/git/cmux/docs/linux-program-plan.md:15)
- Exit criteria:
  - `#55` describes current Linux program reality, not greenfield architecture

### GOV-003 Refresh Rocky 10 Tracking

- Type: tracker
- Priority: `P0`
- Goal: refresh `#187` to reflect Rocky 10 GA and the real
  artifact/proxy blocker
- References:
  - [tracker-refresh-drafts.md](/Users/jess/git/cmux/docs/tracker-refresh-drafts.md:8)
  - [nix/tests-distro.nix](/Users/jess/git/cmux/nix/tests-distro.nix:156)
- Exit criteria:
  - `#187` reflects current Rocky reality and proxy coverage correctly

### GOV-004 Refresh Fork Landscape Issue

- Type: tracker
- Priority: `P1`
- Goal: refresh `#199` so it reflects current divergence and manual-upstream
  boundaries
- Current state:
  - completed on `2026-04-21`
  - `#199` now reflects the human-gated upstream policy and no longer advertises
    direct upstream PR/issue work
- References:
  - [tracker-refresh-drafts.md](/Users/jess/git/cmux/docs/tracker-refresh-drafts.md:108)
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:31)
- Exit criteria:
  - `#199` matches current repo graph and manual-submission policy

### GOV-005 Milestone Cleanup

- Type: tracker
- Priority: `P1`
- Goal: close or rename stale open milestones with zero open issues
- References:
  - [tracker-refresh-drafts.md](/Users/jess/git/cmux/docs/tracker-refresh-drafts.md:250)
- Exit criteria:
  - `M6` through `M9` are no longer misleadingly open
  - `M12` remains the active distro-testing milestone

### GOV-006 Record FlakeHub And `nix-vm-test` Ownership Notes

- Type: tracker/infra governance
- Priority: `P0`
- Goal: keep FlakeHub account decisions and `nix-vm-test` fallback notes on
  owned surfaces only
- Current hiccups:
  - `Jesssullivan/nix-vm-test` has issues disabled
  - `numtide/nix-vm-test#172` has now merged with `Fedora 42` and
    `Rocky 10.1` image support
  - cmux now pins upstream `numtide/nix-vm-test`
  - FlakeHub Cache is unavailable on pull requests from forks
  - the remaining `Rocky 10` gap is an artifact-truth problem, not a reason to
    distort repo ownership
- References:
  - [flakehub-qa-ownership-notes.md](/Users/jess/git/cmux/docs/flakehub-qa-ownership-notes.md:1)
  - [cache-ownership-policy.md](/Users/jess/git/cmux/docs/cache-ownership-policy.md:1)
  - [Issue #209](https://github.com/Jesssullivan/cmux/issues/209)
  - [Issue #187](https://github.com/Jesssullivan/cmux/issues/187)
- Exit criteria:
  - one owned note set exists for FlakeHub, account, and fork-carry decisions
  - GitHub and Linear references point at the same policy
  - any future local `nix-vm-test` carry is tracked by exact SHA and rationale

## Lane 2: KVM And Release Artifact QA

### KVM-001 Verify Current Release-Gated VM Matrix

- Type: KVM/package QA
- Priority: `P0`
- Environment: self-hosted KVM runner
- Goal: keep current release-gated VM validation stable
- Distros:
  - `Ubuntu 24.04`
  - `Debian 12`
  - `Fedora 42`
  - `Rocky 9` RPM proxy
- References:
  - [test-distro.yml](/Users/jess/git/cmux/.github/workflows/test-distro.yml:42)
  - [release-linux.yml](/Users/jess/git/cmux/.github/workflows/release-linux.yml:309)
- Evidence:
  - package install success
  - `ldd` output with no unresolved libraries
  - binary launch proof
- Exit criteria:
  - current KVM matrix passes on the exact release artifacts under test

### KVM-002 Fedora 42 VM Harness Decision

- Type: infra/QA execution
- Priority: `P0`
- Goal: prove and keep the wired `Fedora 42` fresh-install lane green
- Current state:
  - upstream Fedora 42 image support landed in `numtide/nix-vm-test#172`
  - repo-local Fedora 42 image support now exists in `nix/tests-distro.nix`
  - the check now resolves to a real `.sandboxed` VM run
  - cmux now pins upstream `numtide/nix-vm-test`
  - remaining work is first green CI evidence and keeping the lane stable
- References:
  - [nix/tests-distro.nix](/Users/jess/git/cmux/nix/tests-distro.nix:156)
  - [linux-packaging-cd-plan.md](/Users/jess/git/cmux/docs/linux-packaging-cd-plan.md:234)
- Exit criteria:
  - first green Fedora 42 VM result is recorded
  - any temporary owned carry strategy remains explicit until it is retired

### KVM-003 Rocky 10 VM Harness Decision

- Type: infra/QA execution
- Priority: `P0`
- Goal: prove and keep the wired `Rocky 10` terminal-first lane green
- Current state:
  - upstream Rocky 10.1 image support landed in `numtide/nix-vm-test#172`
  - the branch now builds a distinct no-WebKit Rocky 10 RPM
  - release-gated validation now targets `distro-rocky10` when `rpmRocky` is
    present in the manifest
  - cmux now pins upstream `numtide/nix-vm-test`
  - remaining work is first green CI evidence and retirement of the Rocky 9
    proxy
- References:
  - [nix/tests-distro.nix](/Users/jess/git/cmux/nix/tests-distro.nix:156)
  - [linux-validation-checklist.md](/Users/jess/git/cmux/docs/linux-validation-checklist.md:214)
- Exit criteria:
  - first green Rocky 10 VM result is recorded
  - proxy retirement plan for `Rocky 9` is explicit

### KVM-005 Arm64 Distro-Test Follow-Up

- Type: infra/QA design
- Priority: `P1`
- Goal: close the gap between multi-arch release packaging and x86_64-only KVM
  validation
- Current blocker:
  - no arm64 KVM runner exists in the current release-gated lane
- References:
  - [release-linux.yml](/Users/jess/git/cmux/.github/workflows/release-linux.yml:346)
  - [distro-testing-readiness-plan.md](/Users/jess/git/cmux/docs/distro-testing-readiness-plan.md:1)
- Exit criteria:
  - one explicit arm64 validation plan exists
  - arm64 remains clearly documented as follow-on until that plan is real

### KVM-004 Artifact Taxonomy Review

- Type: packaging QA
- Priority: `P1`
- Goal: decide whether current Linux artifacts map cleanly to support tiers
- Questions:
  - should Debian consume the broad-feature `DEB`?
  - does Debian need a baseline/no-WebKit artifact?
  - does Rocky need a no-WebKit RPM or a different terminal-first artifact?
  - does Flatpak become the cross-distro broad-feature channel?
- References:
  - [linux-packaging-cd-plan.md](/Users/jess/git/cmux/docs/linux-packaging-cd-plan.md:102)
- Exit criteria:
  - one explicit artifact taxonomy decision recorded

## Lane 3: Direct Linux Distro QA

### QA-UBU-001 Ubuntu 24.04 Broad-Feature QA

- Type: direct VM/host QA
- Priority: `P0`
- Distro: `Ubuntu 24.04`
- Goal: establish one clean Tier A broad-feature proof pass
- Checklist:
  - install release `DEB`
  - launch app
  - verify terminal/split smoke
  - verify socket/API smoke
  - open browser panel
  - navigate and query current URL
  - use browser find
  - open and close devtools
  - verify notification delivery
  - verify lock/unlock does not break terminal state
- References:
  - [linux-validation-checklist.md](/Users/jess/git/cmux/docs/linux-validation-checklist.md:19)
- Exit criteria:
  - pass or one crisp blocker with evidence

### QA-FED-001 Fedora 42 Broad-Feature QA

- Type: direct VM/host QA
- Priority: `P0`
- Distro: `Fedora 42`
- Goal: establish one clean Tier A broad-feature proof pass
- Checklist:
  - install release `RPM`
  - launch app
  - verify terminal/split smoke
  - verify socket/API smoke
  - browser open/navigate/find/devtools
  - notification delivery
  - lock/unlock behavior
- References:
  - [linux-validation-checklist.md](/Users/jess/git/cmux/docs/linux-validation-checklist.md:19)
- Exit criteria:
  - pass or one crisp blocker with evidence

### QA-DEB-001 Debian 12 Baseline QA

- Type: direct VM/host QA
- Priority: `P0`
- Distro: `Debian 12`
- Goal: prove the baseline story and record browser status explicitly
- Checklist:
  - install release `DEB`
  - launch app
  - verify terminal baseline
  - verify split/focus baseline
  - verify basic socket/API baseline
  - record browser status explicitly
  - record WebAuthn status explicitly
- References:
  - [linux-validation-checklist.md](/Users/jess/git/cmux/docs/linux-validation-checklist.md:83)
- Exit criteria:
  - Debian is no longer implicitly treated as full-feature

### QA-RKY-001 Rocky 10 Terminal-First QA

- Type: direct VM/host QA
- Priority: `P0`
- Distro: `Rocky 10`
- Goal: prove the constrained terminal-first story directly
- Checklist:
  - install package or validated runtime artifact
  - launch app
  - verify terminal/split/focus smoke
  - verify socket/API baseline
  - verify session file path behavior
  - if `-Dno-webkit`, verify browser commands fail clearly
- References:
  - [linux-validation-checklist.md](/Users/jess/git/cmux/docs/linux-validation-checklist.md:114)
  - [linux-parity-matrix.md](/Users/jess/git/cmux/docs/linux-parity-matrix.md:52)
- Exit criteria:
  - Rocky 10 has explicit terminal-first proof

## Lane 3A: Community QA Intake

These shards are for recruiting careful Linux QA users without overstating
support. They should produce evidence, not broad support promises.

### QA-MACH-001 Physical/User-VM QA Machine Pool

- Type: QA infrastructure
- Priority: `P0`
- Goal: provision a concurrent pool of physical installs or normal user-managed
  VMs for graphical Linux QA
- Decision:
  - public graphical QA truth comes from physical installs or ordinary user VMs
  - `honey` KVM/QEMU remains the package-proof and private lab lane
  - NixOS desktop VMs are useful for internal demos, but not a substitute for
    distro-specific graphical claims
- First targets:
  - Ubuntu 24.04 LTS, GNOME Wayland
  - Fedora 42 Workstation, GNOME Wayland
  - Fedora 42 KDE Plasma Desktop
  - Debian 12 GNOME; Xfce optional later
  - Rocky 10.1 Workstation/GNOME
  - CachyOS KDE Plasma
  - Omarchy Hyprland as exploratory only
  - Linux Mint Cinnamon
  - NixOS GNOME/Sway/Hyprland for lab and early Nix reports
- References:
  - [linux-graphical-qa-machine-plan.md](/Users/jess/git/cmux/docs/linux-graphical-qa-machine-plan.md:1)
  - [linux-qa-intake.md](/Users/jess/git/cmux/docs/linux-qa-intake.md:1)
- Exit criteria:
  - each P0 machine has one current install note, artifact under test, and owner
  - P1 machines are clearly marked compatibility-discovery only
  - no public support claim depends only on internal NixOS/QEMU lab proof

### QA-CAD-001 Linux QA Cadence

- Type: QA program
- Priority: `P0`
- Goal: define a predictable cadence for testers on Rocky, Arch, Mint, NixOS,
  Ubuntu, Fedora, and Debian
- Cadence:
  - weekly owned status note while the distro matrix is moving
  - one release-candidate QA window before tagged Linux releases
  - one post-release intake window for installer/runtime regressions
- Exit criteria:
  - one public QA intake template exists
  - one owned tracker or discussion surface records tester reports
  - support tiers are visible in the intake text

### QA-ARCH-001 Arch Rolling QA

- Type: direct host/VM QA
- Priority: `P1`
- Distro: `Arch Linux`
- Goal: validate the rolling-user story before AUR publication claims
- Checklist:
  - build or install from the current package scaffold
  - launch app
  - verify terminal/split/socket smoke
  - record WebKitGTK/browser status explicitly
- Exit criteria:
  - AUR readiness has one real Arch report, or a clear blocker

### QA-MINT-001 Linux Mint QA

- Type: direct host/VM QA
- Priority: `P1`
- Distro: `Linux Mint`
- Goal: validate the Ubuntu-family user story outside vanilla Ubuntu
- Checklist:
  - install the Ubuntu-family `DEB`
  - launch app
  - verify terminal/split/socket smoke
  - record desktop integration, browser, and notification status
- Exit criteria:
  - Mint is documented as either compatible-by-evidence or unsupported pending
    a specific blocker

### QA-NIX-001 NixOS QA

- Type: direct host/VM QA
- Priority: `P1`
- Distro: `NixOS`
- Goal: validate the Nix user story separately from KVM package-install tests
- Checklist:
  - run the flake/app path
  - verify terminal/split/socket smoke
  - record GPU, WebKitGTK, and desktop integration constraints
- Exit criteria:
  - NixOS has one explicit proof note and an honest support posture

## Lane 4: Linux Parity Implementation Work

### PAR-001 Linux WebAuthn Bridge Completion

- Type: implementation
- Priority: `P0`
- Goal: move Linux WebAuthn from installed-stub to end-to-end implementation
- References:
  - [browser.zig](/Users/jess/git/cmux/cmux-linux/src/browser.zig:105)
  - [webauthn_bridge.zig](/Users/jess/git/cmux/cmux-linux/src/webauthn_bridge.zig:61)
  - [tracker-refresh-drafts.md](/Users/jess/git/cmux/docs/tracker-refresh-drafts.md:129)
- Scope:
  - parse bridge request
  - dispatch to CTAP2 path
  - reply to JavaScript
  - run one real ceremony on a Tier A distro
- Exit criteria:
  - parity docs can move WebAuthn above `unsupported`

### PAR-002 Linux Socket / Control Plane Parity

- Type: implementation
- Priority: `P0`
- Goal: close the highest-value Linux control-plane stubs
- References:
  - [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:957)
  - [socket.zig](/Users/jess/git/cmux/cmux-linux/src/socket.zig:1120)
  - [app.zig](/Users/jess/git/cmux/cmux-linux/src/app.zig:11)
  - [tracker-refresh-drafts.md](/Users/jess/git/cmux/docs/tracker-refresh-drafts.md:162)
- Scope:
  - `surface.send_text`
  - `surface.read_text`
  - `pane.break`
  - `pane.join`
  - `surface.move`
  - `surface.reorder`
  - action/clipboard callbacks
- Exit criteria:
  - high-value gaps are implemented or explicitly downgraded in docs

### PAR-003 Linux Restore And Headless Runtime

- Type: implementation / scoping
- Priority: `P1`
- Goal: decide and implement the next honest step for restore and `cmux-term`
- References:
  - [session.zig](/Users/jess/git/cmux/cmux-linux/src/session.zig:221)
  - [main_headless.zig](/Users/jess/git/cmux/cmux-linux/src/main_headless.zig:23)
  - [tracker-refresh-drafts.md](/Users/jess/git/cmux/docs/tracker-refresh-drafts.md:198)
- Exit criteria:
  - both surfaces have explicit supported-state language and a realistic next step

## Lane 5: Participating Libraries And Dependency QA

### LIB-001 Ghostty Ingestion Watchlist

- Type: dependency hygiene
- Priority: `P1`
- Goal: keep `ghostty` visible as the only major carried ingestion-risk dependency
- Current read:
  - pin ancestry is healthy
  - still meaningfully ahead and behind upstream
- References:
  - [component-portfolio.md](/Users/jess/git/cmux/docs/component-portfolio.md:90)
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:33)
- Exit criteria:
  - current carried patch set remains documented and tractable

### LIB-002 Bonsplit Delta Audit

- Type: dependency hygiene
- Priority: `P2`
- Goal: confirm whether any minimal fork-only `bonsplit` delta remains worth
  isolating
- References:
  - [component-portfolio.md](/Users/jess/git/cmux/docs/component-portfolio.md:97)
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:39)
- Exit criteria:
  - minimal delta recorded as either maintenance-only or candidate slice

### LIB-003 zig-ctap2 Linux Hidraw QA

- Type: library QA
- Priority: `P1`
- Goal: prove the Linux CTAP2 path on a real distro and hardware-backed flow
- Current note:
  - `zig-ctap2` already has an open Linux hidraw end-to-end testing issue
- Exit criteria:
  - one recorded Linux hidraw test result and blocker list if needed

### LIB-004 zig-keychain Distro Secret-Service QA

- Type: library QA
- Priority: `P1`
- Goal: validate Secret Service behavior on supported Linux distros
- Focus:
  - Ubuntu 24.04
  - Fedora 42
  - Debian 12 status if practical
- Exit criteria:
  - libsecret behavior is recorded for the distros that matter

### LIB-005 zig-notify Desktop Delivery QA

- Type: library QA
- Priority: `P1`
- Goal: validate notification delivery in the current GNOME/Wayland target path
- Exit criteria:
  - one recorded notification proof path on a Tier A distro

### LIB-006 Homebrew Sync Hygiene

- Type: packaging hygiene
- Priority: `P3`
- Goal: resync `homebrew-cmux` when doing the next release hygiene pass
- Exit criteria:
  - tracked only; not allowed to displace Linux QA work

## Lane 6: Upstream-Prep Candidates

These are not submission tasks. They are local preparation tasks only.

### UPL-001 Ghostty OSC 99 Candidate Slice

- Type: candidate prep
- Priority: `P2`
- Goal: keep the OSC 99 notification parser slice documented and reviewable
- Reference:
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:35)

### UPL-002 Ghostty Display-Link Candidate Slice

- Type: candidate prep
- Priority: `P2`
- Goal: keep the macOS display-link restart fix isolated and documented
- Reference:
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:36)

### UPL-003 Ghostty Mode 2031 Candidate Slice

- Type: candidate prep
- Priority: `P2`
- Goal: keep the color scheme mode 2031 reporting fix isolated and documented
- Reference:
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:1)

### UPL-004 Ghostty APC Candidate Slice

- Type: candidate prep
- Priority: `P2`
- Goal: keep TerminalStream APC handling documented for a possible manual
  upstream submission
- Reference:
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:1)

### UPL-005 Bonsplit Sync Audit

- Type: candidate prep
- Priority: `P3`
- Goal: audit the remaining Bonsplit fork delta after bumping to upstream
  `origin/main`; default posture is maintenance-only unless a small behavior
  fix remains clearly isolated
- Reference:
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:1)

### UPL-006 Standalone Zig Library Polish

- Type: candidate prep
- Priority: `P2`
- Goal: keep `zig-ctap2`, `zig-keychain`, `zig-crypto`, and `zig-notify` in a
  state where packaging/docs polish can be submitted manually later
- Reference:
  - [upstream-candidate-ledger.md](/Users/jess/git/cmux/docs/upstream-candidate-ledger.md:1)

### UPL-007 Human Handoff Packet

- Type: candidate prep
- Priority: `P1`
- Goal: standardize the owned handoff packet Jess uses before manually
  submitting to Ghostty, Bonsplit, Manaflow, or other busy upstreams
- Required contents:
  - target repo and proposed title
  - exact branch or commit range
  - rationale and expected upstream benefit
  - validation already performed and validation still needed
  - copy-ready PR or issue text
  - risk notes and conflict areas
- Exit criteria:
  - every upstream candidate has a handoff packet before any external action

## Lane 7: Reintegration / RFC Futures

### FUT-001 cmux vs lmux Naming Decision

- Type: RFC / product
- Priority: `P3`
- Goal: keep the naming decision visible without letting it block Linux proof
- References:
  - [Issue #76](https://github.com/Jesssullivan/cmux/issues/76)
  - [distro-testing-readiness-plan.md](/Users/jess/git/cmux/docs/distro-testing-readiness-plan.md:1)
  - [linux-work-week-2026-04-14.md](/Users/jess/git/cmux/docs/linux-work-week-2026-04-14.md:1)
- Exit criteria:
  - current recommendation is explicit
  - revisit triggers are documented
  - naming remains non-blocking until those triggers become real

### FUT-002 Reintegration / Proposal Readiness

- Type: strategy
- Priority: `P3`
- Goal: keep a future path open for manaflow reintegration proposals once Linux
  proof is stronger
- Questions:
  - which Linux deltas are fork-only?
  - which are reintegration candidates?
  - which participating libraries are mature enough to present as stable
    building blocks?
- Exit criteria:
  - strategy questions are documented without forcing premature proposal work

## Recommended First Shards For The Week

If the goal is a productive parallel week, start here:

1. `KVM-002` record the first green Fedora 42 VM run
2. `KVM-003` record the first Rocky 10 terminal-first VM run
3. `QA-CAD-001` publish the QA cadence/intake shape before recruiting users
4. `QA-UBU-001` Ubuntu 24.04 broad-feature QA
5. `QA-FED-001` Fedora 42 broad-feature QA
6. `QA-DEB-001` Debian 12 baseline QA
7. `QA-RKY-001` Rocky 10 terminal-first QA
8. `QA-ARCH-001`, `QA-MINT-001`, and `QA-NIX-001` as early community-target
   reports
9. `PAR-001` and `PAR-002` as the next implementation lanes after QA results
   land
10. `UPL-007` before preparing any Ghostty, Bonsplit, or Manaflow-facing
    upstream submission
