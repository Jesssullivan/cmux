# Linux Graphical QA Machine Plan

This note records the current decision for human graphical QA, physical target
machines, and how the existing KVM/QEMU infrastructure should be used.

Use it with:

- `docs/linux-qa-intake.md`
- `docs/linux-validation-checklist.md`
- `docs/distro-testing-readiness-plan.md`
- `docs/linear-qa-shard-punchlist.md`

## Decision

Public Linux QA should use physical standard installs or normal user-managed VMs
as the source of truth for graphical behavior.

The existing `honey` KVM/QEMU infrastructure remains valuable, but it should be
treated as a private lab substrate until the repo has a distro-specific
graphical harness that launches the release package inside the target desktop
session.

Current interpretation:

- release KVM tests prove package install, runtime dependencies, and binary
  launch behavior
- Linux socket tests prove control-plane behavior under Xvfb / no-surface mode
- NixOS desktop VMs prove that a reusable graphical lab substrate exists
- physical installs and ordinary VMs prove real distro desktop integration
- no Linux visual-regression or accessibility gate should be claimed until a
  dedicated harness exists

## Existing Local Lab Substrate

The repo already has useful graphical lab pieces:

- `nix run .#wayland-gnome`
- `nix run .#wayland-sway`
- `nix run .#wayland-hyprland`
- `nix build .#qcow2-gnome`
- `nix build .#qcow2-sway`
- `nix build .#qcow2-hyprland`
- `.github/workflows/release-qcow2.yml`

Those are NixOS desktop variants. They are useful for internal demos,
compositor smoke, screenshots, and future visual automation. They are not
currently a substitute for Ubuntu, Fedora, Debian, Rocky, Arch, or Mint QA.

Known limitation: `nix/tests.nix` still uses `foot` for the graphical GNOME
window check, so it verifies compositor and screenshot plumbing more than cmux
UI behavior.

## Physical / User-VM QA Matrix

| Priority | Distro | Desktop/session | Support posture | Why this target exists |
|---|---|---|---|---|
| P0 | Ubuntu 24.04 LTS | Ubuntu Desktop / GNOME Wayland | Tier A broad-feature | Mainstream LTS deb-family desktop and first public QA ask |
| P0 | Fedora 42 | Workstation / GNOME Wayland | Tier A broad-feature | Modern GNOME, Wayland, GTK, WebKitGTK, portal, notification, and Secret Service target |
| P0 | Fedora 42 | KDE Plasma Desktop | Tier A adjunct | Official Fedora KDE edition; catches KDE portal/session/notification differences |
| P0 | Debian 12 | GNOME first; Xfce optional | Tier B baseline | Stable deb-family install/runtime baseline; browser/WebAuthn status must be recorded explicitly |
| P0 | Rocky 10.1 | Workstation / GNOME; KDE optional | Tier C terminal-first | Enterprise/RHEL-family constrained target; no-WebKit RPM path stays terminal-first |
| P1 | Arch rolling | CachyOS KDE Plasma | Community early report | Opinionated Arch-family rolling desktop with a known KDE default path |
| P1 | Arch rolling | Omarchy Hyprland | Exploratory early report | Opinionated Arch + Hyprland developer desktop; good Wayland/tiling stress target, not a baseline support target |
| P1 | Linux Mint | Cinnamon | Community early report | Ubuntu-family mainstream desktop outside vanilla Ubuntu; good user-facing DE coverage |
| P1 | NixOS | GNOME, Sway, or Hyprland | Internal lab plus early report | Matches repo VM surfaces and Nix user expectations; useful for reproducible lab work |

If only one Arch-family machine is available, use CachyOS KDE Plasma first. Add
Omarchy only when there is room for a tiling/Hyprland compatibility lane.

If only one Mint-family machine is available, use Cinnamon first. Mint MATE and
Xfce are useful later for lower-resource or traditional-panel coverage, but
Cinnamon is the most representative first pass.

## Manual QA Evidence Required

Every physical or user-VM report should include:

- distro, version, desktop/session, architecture, and GPU/session notes
- exact cmux artifact filename or release tag
- install command and install result
- `cmux --version` output
- terminal and split smoke result
- socket/API smoke result
- browser status where expected
- notification status
- WebAuthn/FIDO2 status where practical
- lock/session status
- screenshots or short video for UI defects

## Promotion Rules

Do not promote a distro or capability from a manual report alone unless the
report includes enough evidence to reproduce the claim.

Recommended interpretation:

- one clean physical/user-VM pass can unblock early QA language
- repeated clean passes across different machines can support stronger docs
- package-install KVM proof is still required for release artifact confidence
- visual regression and accessibility automation remain future gates

## Source Notes

The desktop choices above are based on official current surfaces:

- Ubuntu official flavors: `https://ubuntu.com/desktop/flavors`
- Fedora Workstation/KDE/spins listing: `https://www.fedoraproject.org/workstation/`
- Debian live images: `https://www.debian.org/CD/live/index`
- Rocky Linux 10 live images: `https://dl.rockylinux.org/pub/rocky/10/live/x86_64/`
- Linux Mint edition guide: `https://linuxmint-installation-guide.readthedocs.io/en/latest/choose.html`
- CachyOS desktop environments: `https://wiki.cachyos.org/installation/desktop_environments/`
- Omarchy official site: `https://omarchy.org/`
