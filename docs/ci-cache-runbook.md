# CI Cache Runbook

This runbook describes when to use FlakeHub Cache and when to use Magic Nix
Cache in GitHub Actions.

Use this together with:

- `docs/cache-ownership-policy.md`
- `docs/flakehub-qa-ownership-notes.md`
- `docs/program-status.md`

## Default Posture

| Repo class | Default cache path | Notes |
|---|---|---|
| personal fork | `magic-nix-cache-action` | use when canonical ownership is personal or upstream-adjacent |
| org-owned repo | `flakehub-cache-action` | use when the repo is authorized in the org's FlakeHub setup |
| mixed or unknown | gated fallback | enable FlakeHub only behind `FLAKEHUB_CACHE_ENABLED == 'true'` |

## Preconditions For FlakeHub Cache

Do not enable FlakeHub Cache just because the action is available.

All of the following should be true:

1. the repository is naturally org-owned, or there is an explicit operational
   reason to use an org-owned mirror
2. the FlakeHub GitHub App is installed into the organization
3. the repository is actually authorized in that FlakeHub organization
4. the workflow sets:
   - `permissions.contents = read`
   - `permissions.id-token = write`
5. the repository or organization variable `FLAKEHUB_CACHE_ENABLED` is set to
   `true`

If any of those are false, use Magic Nix Cache instead.

## Workflow Shape

Preferred pattern:

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - uses: DeterminateSystems/determinate-nix-action@v3

  - name: Enable FlakeHub Cache
    if: vars.FLAKEHUB_CACHE_ENABLED == 'true' && (github.event_name != 'pull_request' || github.event.pull_request.head.repo.fork != true)
    uses: DeterminateSystems/flakehub-cache-action@v3

  - name: Enable Magic Nix Cache
    if: vars.FLAKEHUB_CACHE_ENABLED != 'true' || (github.event_name == 'pull_request' && github.event.pull_request.head.repo.fork == true)
    uses: DeterminateSystems/magic-nix-cache-action@v13
```

This keeps one workflow usable across both repo classes.

## How To Validate FlakeHub Cache

Use a fresh GitHub Actions run created after the variable state is changed.

Expected success signals in the log:

- `Logged in to FlakeHub.`
- `Using cache "..."`
- `FlakeHub cache is enabled.`
- `Native GitHub Action cache is disabled.`

Expected failure signals:

- `401 Unauthorized`
- `User is not authorized for this resource.`
- `Native GitHub Action cache is enabled.`

If the failure pattern appears, do not keep forcing FlakeHub in that repo.
Disable it and fall back cleanly.

## How To Disable Cleanly

If a repo is not authorized for FlakeHub Cache:

1. set `FLAKEHUB_CACHE_ENABLED=false` for that repo
2. keep the workflow gate in place
3. rerun CI and confirm the job uses Magic Nix Cache instead

This avoids repeated authorization noise while preserving a shared workflow.

## Current Application

As of 2026-04-21:

| Repository scope | Current posture |
|---|---|
| `Jesssullivan/cmux` | `FLAKEHUB_CACHE_ENABLED=false`; use Magic Nix Cache |
| `Jesssullivan/nix-vm-test` | personal contingency fork; keep Magic Nix Cache posture until it actually carries owned patches |
| `tinyland-inc` org | `FLAKEHUB_CACHE_ENABLED=true` at org scope |
| `tinyland-inc/lab` | FlakeHub Cache validated successfully |

Interpretation:

- `tinyland-inc` is the active FlakeHub-heavy lane
- personal forks should remain healthy without requiring FlakeHub Cache
- repository ownership is the policy boundary, not cache-product preference

## QA And Account Notes

- `Jesssullivan/nix-vm-test` is the owned contingency fork for VM-image carry
  work, but it is not an org-cache surface
- FlakeHub Cache is unavailable on fork PRs, so distro/package proof must not
  depend on FlakeHub hits to be considered healthy
- validate FlakeHub App install, billing, and membership assumptions on
  `tinyland-inc/lab` before widening any org-owned cache usage
- keep fallback decisions and hiccup notes in `Jesssullivan/cmux` issues,
  Tinyland Linear, and checked-in docs because `Jesssullivan/nix-vm-test` has
  issues disabled
