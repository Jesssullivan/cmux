# Upstream Sync Cadence

This runbook defines the recurring intake cadence for upstream changes in the
cmux/lmux fork graph.

It complements `docs/upstream-ingestion-playbook.md`, which explains how to
review an ingestion pass. This file answers when to sync, what to check, and
where to record the result.

## Boundary

This is an ingestion runbook, not a publication runbook.

- Agents may fetch, inspect, merge into owned forks, update owned docs, and
  prepare handoff packets in owned surfaces.
- Agents may push only to `Jesssullivan/*` or `tinyland-inc/*` remotes unless
  Jess gives an explicit same-conversation instruction otherwise.
- Agents must not open, comment on, label, close, review, or otherwise update
  third-party upstream surfaces such as `manaflow-ai/*`, `ghostty-org/*`,
  `numtide/*`, Flathub, AUR, or COPR.
- Jess submits and discusses non-owned upstream PRs by hand.

## Cadence

| Surface | Cadence | Why |
|---|---:|---|
| `ghostty` | weekly drift check; sync before drift exceeds about 50 commits or before Zig/build-system churn lands | highest-churn dependency and highest conflict risk |
| `vendor/bonsplit` | monthly drift check; sync after upstream fixes tab/split behavior used by cmux | lower churn, but directly affects tab UI performance |
| `manaflow-ai/cmux` into the fork | bi-weekly drift check; sync opportunistically around macOS/app behavior fixes | parent project continues to move independently |
| upstreamable candidate prep | at most one candidate per session | keeps submission quality high and avoids distracting from Linux delivery |
| distro/package QA | after every release-candidate artifact and after dependency syncs that touch packaging or runtime surfaces | verifies Linux users can actually install and run the fork |

Do an immediate read-only drift check when:

- upstream ships a tag,
- Zig changes toolchain compatibility,
- Ghostty changes build, renderer, embedded runtime, or config APIs,
- Bonsplit changes tab identity, equality, drag, split, or focus behavior,
- release packaging fails on a distro lane.

## Read-Only Drift Check

Run from the parent repo:

```bash
git status --short --branch
git submodule status --recursive ghostty vendor/bonsplit
```

For Ghostty:

```bash
git -C ghostty fetch --all --prune
git -C ghostty rev-list --left-right --count origin/main...upstream/main
git -C ghostty log --oneline --reverse origin/main..upstream/main
git -C ghostty diff --name-only origin/main...upstream/main
```

For Bonsplit:

```bash
git -C vendor/bonsplit fetch --all --prune
git -C vendor/bonsplit rev-list --left-right --count jesssullivan/main...origin/main
git -C vendor/bonsplit log --oneline --reverse jesssullivan/main..origin/main
git -C vendor/bonsplit diff --name-only jesssullivan/main...origin/main
```

Record notable drift in Linear and, when it changes the technical truth, in the
relevant repo doc.

## Ghostty Sync

Ghostty is the highest-risk intake lane. Prefer a dedicated branch in the
submodule fork.

```bash
cd ghostty
git fetch --all --prune
git checkout main
git pull --ff-only origin main
git checkout -b sid/upstream-sync-YYYYMMDD
git merge upstream/main
```

Before pushing the submodule branch, inspect at least:

- `src/Surface.zig`
- `src/config/Config.zig`
- `src/apprt/embedded.zig`
- `include/ghostty.h`
- `build.zig`
- `src/renderer/generic.zig`
- `src/terminal/stream_terminal.zig`
- `src/terminal/osc.zig`
- `src/terminal/osc/parsers.zig`

After resolving the sync:

```bash
git status --short --branch
git merge-base --is-ancestor upstream/main HEAD
```

Push only to the owned fork:

```bash
git push origin sid/upstream-sync-YYYYMMDD
```

After the owned-fork PR or merge lands, update the parent repo only to a commit
reachable from the owned fork's canonical branch:

```bash
cd ..
git -C ghostty fetch origin
git -C ghostty checkout origin/main
git -C ghostty merge-base --is-ancestor HEAD origin/main
git add ghostty docs/ghostty-fork.md
```

When rebuilding GhosttyKit for the chosen pin, use release optimization:

```bash
cd ghostty
zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
```

Then update `docs/ghostty-fork.md` with:

- new cmux parent pin,
- new owned fork main,
- upstream base used for the sync,
- remaining ahead/behind drift,
- conflict notes and carried patch changes.

## Bonsplit Sync

Bonsplit is lower risk, but the parent pointer must still reference a pushed
commit.

```bash
cd vendor/bonsplit
git fetch --all --prune
git checkout main
git pull --ff-only jesssullivan main
git merge origin/main
```

If a Bonsplit fix is submitted upstream by Jess, do not treat the cmux pointer
as done until one of these is true:

- upstream merged the PR and the chosen fork/main contains that merge, or
- Jess explicitly chose a fork-only posture and the chosen commit is pushed to
  `Jesssullivan/bonsplit`.

Before moving the parent pointer:

```bash
git merge-base --is-ancestor HEAD jesssullivan/main
cd ../..
git add vendor/bonsplit
```

If any fork-only delta remains, document it in
`docs/upstream-candidate-ledger.md`.

## cmux Upstream Intake

Use a read-only pass first. The fork has Linux/WebAuthn/Nix work that should not
be blurred into Manaflow-owned product work.

```bash
git fetch upstream
git rev-list --left-right --count origin/main...upstream/main
git log --oneline --reverse origin/main..upstream/main
git diff --name-only origin/main...upstream/main
```

Classify incoming changes as:

- safe app bug fix,
- macOS-only product polish,
- shared runtime or socket behavior,
- packaging/CI/docs,
- conflicting with fork-owned Linux work.

Use `docs/upstream-ingestion-playbook.md` for merge review. Use
`docs/upstream-handoff-template.md` only when preparing a manual upstream
submission for Jess.

## Validation

Follow the repo test policy: do not run local E2E/UI/socket test suites by
default. Prefer GitHub Actions or the VM lanes.

Minimum validation records for sync work:

- `git diff --check` for changed parent-repo files,
- submodule commit reachability check,
- docs updated in the same change set,
- CI workflow or GitHub Actions run linked when a runtime surface changed,
- GhosttyKit rebuild result recorded for Ghostty parent-pin changes.

For distro/package impact, link the relevant Linux CI or VM proof issue rather
than treating source inspection as validation.

## Recording

Each sync pass should leave a short trail:

- Linear issue with before/after SHAs and drift counts,
- updated fork doc or candidate ledger,
- parent repo commit that moves the submodule pointer,
- CI or build proof link when applicable,
- explicit note for any deferred upstream commits or fork-only patches.

If the work produces a third-party upstream opportunity, prepare a handoff in
an owned surface and let Jess submit it manually.
