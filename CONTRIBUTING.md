# Contributing to cmux

## Prerequisites

- macOS 14+
- Xcode 15+
- [Zig](https://ziglang.org/) (install via `brew install zig`)

## Getting Started

1. Clone the repository with submodules:
   ```bash
   git clone --recursive https://github.com/Jesssullivan/cmux.git
   cd cmux
   ```

2. Run the setup script:
   ```bash
   ./scripts/setup.sh
   ```

   This will:
   - Initialize git submodules (ghostty, homebrew-cmux)
   - Build the GhosttyKit.xcframework from source
   - Create the necessary symlinks

3. Build the debug app:
   ```bash
   ./scripts/reload.sh --tag my-feature
   ```
   The script prints the `.app` path. Cmd-click to open, or pass `--launch` to open automatically.

## Development Scripts

| Script | Description |
|--------|-------------|
| `./scripts/setup.sh` | One-time setup (submodules + xcframework) |
| `./scripts/reload.sh` | Build Debug app (pass `--launch` to also open it) |
| `./scripts/reloadp.sh` | Build and launch Release app |
| `./scripts/reload2.sh` | Reload both Debug and Release |
| `./scripts/rebuild.sh` | Deprecated compatibility shim for `./scripts/reload.sh --tag <tag>` |
| `./scripts/report-fork-health.sh` | Report parent/submodule hygiene and pin ancestry |

## Project Maps

These docs describe the current multi-repo and Linux program shape:

- `docs/fork-landscape.md` — repository graph, governance lanes, and fork hygiene
- `docs/cache-ownership-policy.md` — repository ownership boundary for FlakeHub Cache vs Magic Nix Cache
- `docs/ci-cache-runbook.md` — tactical guide for enabling FlakeHub Cache or falling back to Magic Nix Cache
- `docs/program-status.md` — short operational readout of current health, blockers, and next actions
- `docs/component-portfolio.md` — health and ownership view of carried repos and packages
- `docs/upstream-ingestion-playbook.md` — human process for upstream merges and carried patches
- `docs/upstream-candidate-ledger.md` — local ledger for upstream-prep work; manual submission only
- `docs/ghostty-fork.md` — carried Ghostty patches and current submodule notes
- `docs/linux-program-plan.md` — execution plan for Linux-native `cmux`
- `docs/linux-parity-matrix.md` — conservative Linux capability matrix
- `docs/linux-validation-checklist.md` — concrete distro validation checklist
- `docs/tracker-refresh-notes.md` — local prep notes for issue and roadmap grooming
- `docs/linux-mvp-architecture.md` — architecture decision record for the Linux port

## Rebuilding GhosttyKit

If you make changes to the ghostty submodule, rebuild the xcframework:

```bash
cd ghostty
zig build -Demit-xcframework=true -Doptimize=ReleaseFast
```

## Running Tests

### Basic tests (run on VM)

```bash
ssh cmux-vm 'cd /Users/cmux/GhosttyTabs && xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination "platform=macOS" build && pkill -x "cmux DEV" || true && APP=$(find /Users/cmux/Library/Developer/Xcode/DerivedData -path "*/Build/Products/Debug/cmux DEV.app" -print -quit) && open "$APP" && for i in {1..20}; do [ -S /tmp/cmux.sock ] && break; sleep 0.5; done && python3 tests/test_update_timing.py && python3 tests/test_signals_auto.py && python3 tests/test_ctrl_socket.py && python3 tests/test_notifications.py'
```

### UI tests (run on VM)

```bash
ssh cmux-vm 'cd /Users/cmux/GhosttyTabs && xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Debug -destination "platform=macOS" -only-testing:cmuxUITests test'
```

## Ghostty Submodule

The `ghostty` submodule points to [Jesssullivan/ghostty](https://github.com/Jesssullivan/ghostty), a fork of the upstream Ghostty project.

### Making changes to ghostty

```bash
cd ghostty
git checkout -b my-feature
# make changes
git add .
git commit -m "Description of changes"
git push origin my-feature
```

### Keeping the fork updated

```bash
cd ghostty
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

Then update the parent repo:

```bash
cd ..
git add ghostty
git commit -m "Update ghostty submodule"
```

See `docs/ghostty-fork.md` for details on fork changes, current carried patches,
and conflict notes.

## License

By contributing to this repository, you agree that:

1. Your contributions are licensed under the project's GNU General Public License v3.0 or later (`GPL-3.0-or-later`).
2. You grant Manaflow, Inc. a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license to use, reproduce, modify, sublicense, and distribute your contributions under any license, including a commercial license offered to third parties.
