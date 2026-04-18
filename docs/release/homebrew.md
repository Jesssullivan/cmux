# Homebrew Cask bump runbook

This is a **human-driven** runbook. The cask repo lives at
`manaflow-ai/homebrew-cmux`, which is upstream and intentionally
off-limits to this fork's agent automation. Run the PR yourself.

## Current state (2026-04-17)

- Latest cmux stable tag: `v0.63.2`
- Pinned cask version: `0.62.1`
- Versions to skip past: `0.63.0`, `0.63.1`, `0.63.2`

Bump straight to `0.63.2` rather than landing three sequential PRs.

## 1. Derive artifact SHA256

Get the macOS DMG attached to the `v0.63.2` GitHub release:

```bash
# Either download from the release URL...
gh release download v0.63.2 --repo Jesssullivan/cmux --pattern 'cmux-macos.dmg' --dir /tmp
shasum -a 256 /tmp/cmux-macos.dmg
# ...or use the asset URL the cask already references and compute remotely:
curl -sL "https://github.com/Jesssullivan/cmux/releases/download/v0.63.2/cmux-macos.dmg" \
  | shasum -a 256
```

Save the resulting hash; you'll paste it into the cask.

## 2. Clone and branch

```bash
gh repo clone manaflow-ai/homebrew-cmux ~/git/homebrew-cmux
cd ~/git/homebrew-cmux
git checkout -b bump-cmux-0.63.2
```

## 3. Edit `Casks/cmux.rb`

```diff
 cask "cmux" do
-  version "0.62.1"
-  sha256 "<old-sha>"
+  version "0.63.2"
+  sha256 "<new-sha-from-step-1>"

   url "https://github.com/Jesssullivan/cmux/releases/download/v#{version}/cmux-macos.dmg"
   ...
 end
```

(If the cask already uses a `livecheck` block, no other changes needed.)

## 4. Local validate

```bash
brew style --fix Casks/cmux.rb
brew audit --new --strict --online Casks/cmux.rb
brew install --cask --force ./Casks/cmux.rb
brew uninstall --cask cmux  # cleanup after smoke test
```

## 5. Commit + PR

```bash
git add Casks/cmux.rb
git commit -m "cmux: bump to 0.63.2"
git push -u origin bump-cmux-0.63.2
gh pr create --repo manaflow-ai/homebrew-cmux \
  --title "cmux: bump to 0.63.2" \
  --body "$(cat <<'EOF'
Bump cmux cask to v0.63.2.

Skips 0.63.0 and 0.63.1 — cask is currently 3 versions stale (last bump 0.62.1).

## Verification
- [x] \`brew audit --new --strict --online Casks/cmux.rb\` clean
- [x] Local install + launch smoke test
- [x] SHA256 verified against the GitHub release artifact

Source release: https://github.com/Jesssullivan/cmux/releases/tag/v0.63.2
EOF
)"
```

## 6. After merge

Verify a fresh tap install pulls the new version:

```bash
brew untap manaflow-ai/cmux 2>/dev/null
brew tap manaflow-ai/cmux
brew install --cask cmux
brew info --cask cmux | head -5  # should show 0.63.2
```

## Future automation (not in scope for this bump)

Add a workflow in `Jesssullivan/cmux` that opens a homebrew PR on every
stable tag. Gate behind `workflow_dispatch` until cadence is stable.
Lives under `.github/workflows/homebrew-bump.yml` if added.

## Linear

- Project: cmux/C — Distribution Surfaces (`TIN-180`)
- Initiative: cmux Linux Distribution & Tech Debt Reset
