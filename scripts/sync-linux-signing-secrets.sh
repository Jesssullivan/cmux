#!/usr/bin/env bash
# Sync Linux package-signing GitHub Actions secrets from the SOPS source file.

set -euo pipefail

REPO="${GITHUB_REPOSITORY:-Jesssullivan/cmux}"
SECRETS_FILE="${1:-secrets/linux-release-signing.sops.yaml}"

if [ ! -f "$SECRETS_FILE" ]; then
  echo "sync-linux-signing-secrets: ERROR - secrets file not found: $SECRETS_FILE" >&2
  exit 1
fi

for tool in gh sops; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "sync-linux-signing-secrets: ERROR - required tool not found: $tool" >&2
    exit 1
  fi
done

extract_secret() {
  local key="$1"
  sops --decrypt --extract "[\"linux_release_signing\"][\"github_actions\"][\"$key\"]" "$SECRETS_FILE"
}

echo "sync-linux-signing-secrets: syncing Linux signing secrets to $REPO"
gh secret set LINUX_GPG_PRIVATE_KEY_BASE64 --repo "$REPO" --body "$(extract_secret LINUX_GPG_PRIVATE_KEY_BASE64)" >/dev/null
gh secret set LINUX_GPG_PASSPHRASE --repo "$REPO" --body "$(extract_secret LINUX_GPG_PASSPHRASE)" >/dev/null
gh secret set LINUX_GPG_KEY_ID --repo "$REPO" --body "$(extract_secret LINUX_GPG_KEY_ID)" >/dev/null
echo "sync-linux-signing-secrets: done"
