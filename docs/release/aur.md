# AUR Submission Runbook

This is a human-driven runbook. AUR publication is a third-party registry
action, so agents may prepare files in this repo but must not publish, submit,
or comment in AUR surfaces.

## Current Scaffold

- Draft package: `packaging/aur/PKGBUILD`
- Target package name: `cmux`
- Current release tag assumption: `lab-v<version>`

The scaffold builds from the Git tag and initializes submodules during
`prepare()`. It is intended for maintainer review before any upload.

## Pre-Submission Checklist

- [ ] One direct Arch QA report exists in an owned issue or Linear note
- [ ] `pkgver` matches the release tag
- [ ] `source` points at the intended tag
- [ ] dependencies match the current Arch package names
- [ ] `makepkg --printsrcinfo > .SRCINFO` was run by a human maintainer
- [ ] `makepkg -si` was tested on an Arch host or VM
- [ ] package wording does not claim browser/WebAuthn parity beyond evidence

## Manual Submission Flow

```bash
git clone ssh://aur@aur.archlinux.org/cmux.git aur-cmux
cd aur-cmux
cp /Users/jess/git/cmux/packaging/aur/PKGBUILD .
makepkg --printsrcinfo > .SRCINFO
git add PKGBUILD .SRCINFO
git commit -m "Update cmux to <version>"
git push
```

## QA Notes

For Arch, collect at least:

- install/build result
- desktop/session
- `cmux --version`
- terminal/split smoke
- socket/API smoke
- browser status
- notification status

Arch is an early community target until repeated reports justify stronger
support language.

## Linear

- Project: cmux/C — Distribution Surfaces (`TIN-181`)
- Related QA: `docs/linux-qa-intake.md`
