# TODO

This file is a short, repo-local pointer to the active lanes.
Detailed execution belongs in owned trackers and status docs, not here.

## Source Of Truth

- GitHub issues in `Jesssullivan/cmux` for repo-local execution lanes
- Tinyland Linear for cross-repo planning and status
- `docs/program-status.md`
- `docs/linux-parity-matrix.md`
- `docs/ghostty-fork.md`

## Active Lanes

- [ ] Upstream ingestion
  - Sync `Jesssullivan/cmux` with the remaining `manaflow-ai/cmux` delta in controlled batches
  - Reconcile `vendor/bonsplit` tracking posture and decide whether the Jess fork or upstream `main` is the canonical pin source
  - `TIN-621` bump cmux Zig vendor pins to productionized releases
  - Resync `homebrew-cmux` during the next release-hygiene pass
  - `TIN-619` require green checks before merging owned-fork PRs

- [ ] Linux proof and parity
  - `TIN-614` record first signed DEB/RPM artifact proof
  - `#209` Fedora 42 fresh-install VM proof
  - `#187` Rocky 10 fresh-install proof / proxy retirement
  - `#206` WebAuthn bridge completion
  - `#216` Expand Linux `tests_v2` socket coverage beyond the current stable baseline

- [ ] Remote/fleet follow-up
  - `#201` Tailnet-direct `cmuxd-remote` listener mode

- [ ] Non-blocking decision lane
  - `#76` Linux client naming RFC

## Hygiene Rules

- Keep this file short and current.
- Do not use this file as an archive of completed work.
- When a lane gains real scope, move the detail into GitHub/Linear/docs and leave only the pointer here.
