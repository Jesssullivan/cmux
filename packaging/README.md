# Linux Packaging Scaffolds

This directory holds publication scaffolds for distribution channels that are
not yet canonical release surfaces.

## Policy

- These files are preparation artifacts until a maintainer reviews and submits
  them by hand.
- Agents may update these owned files.
- Agents must not publish to AUR, COPR, Flathub, distro bug trackers, or other
  third-party package registries.
- Package metadata must preserve the current support tiers:
  - Ubuntu 24.04 and Fedora 42: broad-feature targets
  - Debian 12: package/runtime baseline
  - Rocky 10: terminal-first target
  - Arch, Mint, NixOS: early QA targets

## Current Scaffolds

- `aur/PKGBUILD`: Arch/AUR source package draft
- `copr/cmux.spec`: COPR RPM source-build draft

Before publication, record at least one direct QA result for the target distro
in an owned issue or Linear note.
