# CI Governance

This runbook defines the merge gate for `Jesssullivan/cmux`.

It is intentionally scoped to owned-fork governance. It does not publish,
comment on, or configure any third-party upstream repository.

## Current Rule

Normal PR merges into `main` should wait for the hosted required checks below
to pass. Self-hosted proof lanes remain advisory until runner availability is
steady enough that they can be required without blocking unrelated work.

Do not use auto-merge as a substitute for branch protection. Auto-merge is only
safe after GitHub itself knows which checks are required.

## Required Hosted Checks

Require these status checks for normal PRs into `main`:

| Check | Workflow | Why |
|---|---|---|
| `build-ghosttykit` | `Build GhosttyKit` | proves the embedded macOS framework can be built or fetched for the pinned Ghostty commit |
| `Build macOS (LAB)` | `Fork CI` | proves the macOS app still builds in Debug and Release |
| `Fork Nix flake check` | `Fork CI` | proves the fork-wide Nix checks and best-effort socket/graphical checks still run |
| `Linux Nix flake check` | `Linux CI` | proves the Linux flake checks remain healthy in the Linux workflow |
| `Zig vendor libs (Linux)` | `Linux CI` | proves the Zig vendor libraries, `cmuxd`, `libghostty`, and Linux binary build path remain wired |
| `Ubuntu 24.04 (broad-feature)` | `Linux CI` | primary broad-feature Linux build target |
| `Fedora 42 (GTK4 4.18)` | `Linux CI` | primary current GTK/Fedora target |
| `Debian 12 (baseline, no-webkit)` | `Linux CI` | conservative no-WebKit baseline target |
| `Rocky Linux 10 (RHEL 10)` | `Linux CI` | terminal-first RHEL-family target |
| `Arch Linux (bleeding edge)` | `Linux CI` | rolling distro compatibility signal |

The two Nix jobs are deliberately named differently. Do not collapse them back
to the same check name; duplicate status contexts make branch-protection
configuration ambiguous.

## Advisory Checks

Keep these checks visible, but do not require them for every normal PR yet:

| Check or workflow | Reason |
|---|---|
| `Distro Package Tests (Self-Hosted)` | depends on the `honey-cmux` KVM runner; it is the proof lane for Fedora/Rocky package installs, not a default merge blocker |
| `Socket Tests (Self-Hosted Linux)` | useful Linux runtime evidence, but runner capacity and surface readiness are still being expanded |
| `GPU Smoke Test (Self-Hosted)` | hardware-specific smoke coverage |
| `CJK Input Tests (Self-Hosted)` | hardware/runner-specific input coverage |
| `SSH Proxy E2E Tests (Self-Hosted)` | integration proof, not a default gate for unrelated changes |
| `Flatpak CI` | path-filtered; requiring it globally would block PRs where the workflow legitimately does not run |
| `Package Draft Lint` | path-filtered packaging lint; require per-PR by review judgment until a sentinel check exists |
| `Greptile Review` | review signal, not a build or runtime proof |
| `Claude Code` | comment/review automation; skipped runs should not block merges |

If a path-filtered workflow should become required, first add a stable sentinel
job that always reports success or failure for every PR. Then update this file
and the branch-protection rule together.

## Branch Protection Setup

For `main`, configure either a GitHub ruleset or classic branch protection with:

- pull requests required before merge
- required status checks enabled
- the required hosted checks listed above
- stale approvals dismissed when new commits are pushed, if practical
- admins included only if Jess wants the fork to prevent accidental manual
  bypasses

Leave self-hosted proof lanes advisory until `TIN-184` has repeated green runs
and runner availability is no longer the dominant failure mode.

## Operating Notes

- `merge on greens` means the required hosted checks are green in GitHub, not
  merely that an operator skimmed the Actions page.
- If a required check is renamed, update the branch-protection rule and this
  document in the same PR.
- If a required workflow becomes path-filtered, add a sentinel job first or
  remove that check from the required set.
- Failed advisory checks should be triaged and linked to the relevant Linear or
  GitHub proof issue, but they should not automatically block unrelated PRs.
