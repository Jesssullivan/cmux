# Flathub submission runbook

This is a **human-driven** runbook. The Flathub repos live under `flathub/*`
on GitHub, which is third-party and intentionally off-limits to this fork's
agent automation. Run these steps yourself; the agent can stage local
changes (manifest tweaks, validation) but does not push to Flathub.

## Prerequisites

- A Flathub-enabled GitHub account (sign in at <https://flathub.org/login>)
- `flatpak` and `flatpak-builder` installed locally (Linux only)
- Network access; first-time builds pull large runtimes
- A current cmux release tag in `Jesssullivan/cmux` (e.g. `lab-v0.75.0`) so the manifest can pin a verifiable source

## 1. Local build verification (do before submitting)

The manifest already lives at `flatpak/com.jesssullivan.cmux.yml`. Build it
locally to confirm the current main branch produces a working bundle:

```bash
cd /Users/jess/git/cmux
flatpak-builder --user --install --force-clean build-flatpak \
  flatpak/com.jesssullivan.cmux.yml
flatpak run com.jesssullivan.cmux
```

If that fails, fix in `flatpak/com.jesssullivan.cmux.yml` and `flatpak/dependencies.yml` *before* opening the Flathub PR. CI runs the same build via `.github/workflows/flatpak-ci.yml`; check its latest green run.

## 2. Pin manifest to a release tag

Flathub will not accept a manifest that builds from a moving branch. Edit
the manifest (or maintain a Flathub-only copy at submission time) so the
`cmux` source module references a tagged ref:

```yaml
- name: cmux
  sources:
    - type: git
      url: https://github.com/Jesssullivan/cmux.git
      tag: lab-v0.75.0   # bump on every release
      commit: <sha>      # optional but Flathub-preferred
```

Same for the `ghostty` submodule source if it is fetched separately.

## 3. Fork and PR against `flathub/flathub`

The submission flow uses the `flathub/flathub` repo's submission process,
not the per-app repo (which Flathub creates *after* acceptance):

1. Read <https://github.com/flathub/flathub/wiki/App-Submission>
2. `gh repo fork flathub/flathub --clone --remote`
3. `cd flathub && git checkout -b new-pr/com.jesssullivan.cmux`
4. Copy the pinned manifest in as `com.jesssullivan.cmux.yml`
5. Add a `flathub.json` if needed (allow extra sources, baseapps, etc.)
6. Commit and push to your fork
7. Open a PR titled `Add com.jesssullivan.cmux` against `flathub/flathub:new-pr`
8. Address reviewer feedback (the Flathub buildbot runs `flatpak-builder` on every push)

## 4. Post-acceptance: manage `flathub/com.jesssullivan.cmux`

Once accepted, Flathub creates `flathub/com.jesssullivan.cmux`. You are
added as a maintainer. From then on, version bumps are PRs against that
per-app repo:

1. `gh repo clone flathub/com.jesssullivan.cmux`
2. Edit the `tag:` and `commit:` fields in `com.jesssullivan.cmux.yml`
3. PR. The Flathub buildbot will build, then a human reviewer will merge.

## 5. Wire auto-PR on cmux release (later, optional)

Add a workflow under `.github/workflows/flathub-bump.yml` in
`Jesssullivan/cmux` that, on tag push, opens a PR against the per-app
Flathub repo using a PAT. Keep this gated behind a manual `workflow_dispatch`
until the cadence is stable.

## QA checklist before submission

- [ ] Local `flatpak-builder ... && flatpak run` works end-to-end
- [ ] `flatpak-ci.yml` is green on `main`
- [ ] Manifest pins to a tag (not a branch)
- [ ] AppStream metainfo at `dist/linux/com.jesssullivan.cmux.metainfo.xml` validates: `appstreamcli validate dist/linux/com.jesssullivan.cmux.metainfo.xml`
- [ ] Desktop file validates: `desktop-file-validate dist/linux/com.jesssullivan.cmux.desktop`
- [ ] Icons exist at 16/128/256/512 px (already in `dist/linux/icons/`)
- [ ] `finish-args` lists are minimal and justified (current set is OK)
- [ ] License fields are correct in metainfo:
  - `metadata_license`: `MIT`
  - `project_license`: `GPL-3.0-or-later`
- [ ] `developer_name`, `summary`, and `description` in metainfo read well

## Reference links

- Submission docs: <https://docs.flathub.org/docs/for-app-authors/submission>
- Manifest reference: <https://docs.flatpak.org/en/latest/manifests.html>
- finish-args reference: <https://docs.flatpak.org/en/latest/sandbox-permissions-reference.html>

## Linear

- Project: cmux/C — Distribution Surfaces (`TIN-179`)
- Initiative: cmux Linux Distribution & Tech Debt Reset
