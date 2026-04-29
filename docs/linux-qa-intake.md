# Linux QA Intake And Cadence

This document defines how to recruit and process early Linux QA reports without
overstating support.

Use it with:

- `docs/distro-testing-readiness-plan.md`
- `docs/linux-graphical-qa-machine-plan.md`
- `docs/linux-validation-checklist.md`
- `docs/release/linux-install.md`
- `docs/linear-qa-shard-punchlist.md`

## Operating Rule

QA reports are evidence, not support promises. Every report should preserve the
current distro tier and the exact artifact under test.

Graphical QA should use physical standard installs or normal user-managed VMs as
the source of truth for public claims. The existing `honey` KVM/QEMU and NixOS
desktop VM surfaces are useful private lab infrastructure, but they are not yet
a distro-specific graphical QA replacement for Ubuntu, Fedora, Debian, Rocky,
Arch, or Mint installs.

## Distro Tiers

| Tier | Distros | QA ask |
|---|---|---|
| Tier A broad-feature | Ubuntu 24.04, Fedora 42 | terminal, splits, socket/API, browser, notifications, lock, and WebAuthn status where practical |
| Tier B baseline | Debian 12 | package/runtime baseline plus explicit browser and WebAuthn status |
| Tier C terminal-first | Rocky 10 | terminal, splits, focus, socket/API, and clear browser-unavailable behavior |
| Community early reports | Arch, Mint, NixOS | compatibility discovery; no broad support claim until repeated evidence exists |

## First Machine Targets

Use the full matrix in `docs/linux-graphical-qa-machine-plan.md` for provisioning
details. The first physical/user-VM pool should prioritize:

- Ubuntu 24.04 LTS, default GNOME Wayland
- Fedora 42 Workstation, GNOME Wayland
- Fedora 42 KDE Plasma Desktop as the first DE-variance target
- Debian 12 GNOME first, with Xfce optional later
- Rocky 10.1 Workstation/GNOME for terminal-first proof
- CachyOS KDE Plasma as the first Arch-family rolling target
- Omarchy Hyprland only as an exploratory Arch/tiling target
- Linux Mint Cinnamon as the first Ubuntu-family community target
- NixOS GNOME/Sway/Hyprland as an internal lab and early Nix report target

## Cadence

Weekly while the Linux matrix is moving:

1. Publish one owned status note with current artifact names, known blockers,
   and the next requested distro reports.
2. Review incoming QA reports and collapse duplicates into the smallest
   actionable blockers.
3. Promote only evidence-backed claims into docs, release notes, or package
   metadata.

Before a tagged Linux release:

1. Open a release-candidate QA window.
2. Request one clean Tier A Ubuntu report and one clean Tier A Fedora report.
3. Request one Debian baseline report.
4. Request one Rocky terminal-first report when a distinct Rocky RPM exists.
5. Do not publish the release as broad Linux support until the support-tier
   language matches the evidence.

After a tagged Linux release:

1. Keep an installer/runtime regression window open.
2. Prioritize reproducible package install failures over feature requests.
3. Move feature gaps into parity issues only after the packaging/runtime story
   is clear.

## Intake Surface

Use owned surfaces first:

- `Jesssullivan/cmux` issues for public, reproducible cmux-specific reports
- Tinyland Linear for private planning and synthesis
- checked-in docs for stable runbooks and support-tier wording

Do not ask early testers to file upstream Ghostty, Bonsplit, Manaflow, Flathub,
AUR, COPR, or distro bugs until Jess has reviewed the report and decided that a
third-party submission is appropriate.

## Report Template

Ask testers to include:

```md
## Environment

- Distro:
- Version:
- Desktop/session:
- CPU architecture:
- GPU/session notes, if relevant:

## Artifact

- Artifact filename:
- Download URL or release tag:
- SHA256, if available:
- Install command used:

## Results

- Install result:
- `cmux --version` output:
- Terminal/split smoke:
- Socket/API smoke:
- Browser status:
- Notification status:
- WebAuthn/FIDO2 status:
- Lock/session status:

## Failure Detail

- Exact error:
- Logs:
- Screenshots or short video:
- Reproduction steps:
```

## Community Messaging Guardrails

Use wording that is specific and friendly:

- "Linux-native cmux/lmux testing is open for Ubuntu 24.04 and Fedora 42 first."
- "Debian 12 is being treated as a package/runtime baseline while browser and
  WebAuthn behavior are recorded."
- "Rocky 10 is terminal-first until the browser-capable path is proven."
- "Arch, Mint, and NixOS reports are welcome as early compatibility reports."

Avoid wording that implies:

- every Linux distro is supported
- browser/WebAuthn parity is complete
- Rocky has the same artifact contract as Fedora
- upstream projects are responsible for fork-specific bugs before local triage

## Manaflow Relationship Note

`lmux` should be described as a friendly Linux-focused fork/derivative planning
lane, not as a replacement for Manaflow's upstream `cmux`. Keep relationship
language separate from technical bug reports and upstream patch handoff packets.

Jess handles any Manaflow-facing outreach manually.
