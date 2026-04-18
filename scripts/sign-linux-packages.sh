#!/usr/bin/env bash
# Sign Linux release artifacts (.deb, .rpm, .tar.gz) with GPG in CI.
#
# Reads the signing key + passphrase + key ID from environment:
#   LINUX_GPG_PRIVATE_KEY_BASE64   base64-encoded ASCII-armored private key
#                                  (gpg --export-secret-keys --armor <KEYID> | base64 -w0)
#   LINUX_GPG_PASSPHRASE           passphrase for the key
#   LINUX_GPG_KEY_ID               key fingerprint or short ID (used as default-key)
#
# If LINUX_GPG_PRIVATE_KEY_BASE64 is empty or unset, the script no-ops with a
# warning so that local builds (without secrets) continue to work.
#
# Signs every matching artifact in $1 (default: current directory):
#   *.deb     → detached *.asc next to the file
#   *.tar.gz  → detached *.asc next to the file
#   *.rpm     → in-package signature via `rpmsign --addsign` (verify with `rpm -K`)
#
# The script uses an ephemeral GNUPGHOME under a `mktemp -d` so the host
# keyring is never touched, and cleans up on exit via trap.
#
# Idempotent: re-running on already-signed artifacts is harmless (existing
# `.asc` is overwritten; `rpmsign --addsign` replaces the existing signature).

set -euo pipefail

ARTIFACT_DIR="${1:-.}"

if [ -z "${LINUX_GPG_PRIVATE_KEY_BASE64:-}" ]; then
  echo "sign-linux-packages: LINUX_GPG_PRIVATE_KEY_BASE64 not set — skipping (no-op for local/unsigned builds)"
  exit 0
fi

if [ -z "${LINUX_GPG_PASSPHRASE:-}" ]; then
  echo "sign-linux-packages: ERROR — LINUX_GPG_PRIVATE_KEY_BASE64 is set but LINUX_GPG_PASSPHRASE is missing" >&2
  exit 1
fi

if [ -z "${LINUX_GPG_KEY_ID:-}" ]; then
  echo "sign-linux-packages: ERROR — LINUX_GPG_PRIVATE_KEY_BASE64 is set but LINUX_GPG_KEY_ID is missing" >&2
  exit 1
fi

if [ ! -d "$ARTIFACT_DIR" ]; then
  echo "sign-linux-packages: ERROR — artifact dir not found: $ARTIFACT_DIR" >&2
  exit 1
fi

for tool in gpg base64; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "sign-linux-packages: ERROR — required tool not found: $tool" >&2
    exit 1
  fi
done

# Ephemeral keyring — never touch the host's ~/.gnupg
GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
chmod 700 "$GNUPGHOME"

cleanup() {
  # Best-effort agent shutdown so the temp dir cleanup doesn't race
  gpgconf --kill gpg-agent 2>/dev/null || true
  rm -rf "$GNUPGHOME"
}
trap cleanup EXIT

# Allow non-interactive operation
cat > "$GNUPGHOME/gpg.conf" <<'GPGCONF'
batch
no-tty
pinentry-mode loopback
trust-model always
GPGCONF

# Import the key
echo "sign-linux-packages: importing key $LINUX_GPG_KEY_ID into ephemeral GNUPGHOME"
echo "$LINUX_GPG_PRIVATE_KEY_BASE64" | base64 -d | gpg --import 2>&1 | sed 's/^/  gpg: /'

# Verify the key is present
if ! gpg --list-secret-keys "$LINUX_GPG_KEY_ID" >/dev/null 2>&1; then
  echo "sign-linux-packages: ERROR — key $LINUX_GPG_KEY_ID not found after import" >&2
  exit 1
fi

# rpmsign reads ~/.rpmmacros — point it at the imported key
RPMMACROS="$HOME/.rpmmacros"
if command -v rpmsign >/dev/null 2>&1; then
  cat > "$RPMMACROS" <<RPMCONF
%_signature gpg
%_gpg_name $LINUX_GPG_KEY_ID
%__gpg_sign_cmd %{__gpg} gpg --batch --no-armor --pinentry-mode loopback --passphrase-fd 3 --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} %{__plaintext_filename} 3<<<"\$LINUX_GPG_PASSPHRASE"
RPMCONF
fi

sign_detached() {
  local file="$1"
  local out="${file}.asc"
  echo "sign-linux-packages: signing $file → $out"
  gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase-fd 0 \
    --local-user "$LINUX_GPG_KEY_ID" \
    --armor --detach-sign \
    --output "$out" \
    "$file" <<<"$LINUX_GPG_PASSPHRASE"
}

sign_rpm() {
  local file="$1"
  echo "sign-linux-packages: rpmsign --addsign $file"
  if ! command -v rpmsign >/dev/null 2>&1; then
    echo "sign-linux-packages: WARN — rpmsign not available; skipping in-package RPM signature for $file" >&2
    sign_detached "$file"
    return
  fi
  LINUX_GPG_PASSPHRASE="$LINUX_GPG_PASSPHRASE" rpmsign --addsign "$file"
  # Also produce a detached sig for tooling that prefers it
  sign_detached "$file"
}

shopt -s nullglob

signed_count=0
for f in "$ARTIFACT_DIR"/*.deb "$ARTIFACT_DIR"/*.tar.gz; do
  sign_detached "$f"
  signed_count=$((signed_count + 1))
done

for f in "$ARTIFACT_DIR"/*.rpm; do
  sign_rpm "$f"
  signed_count=$((signed_count + 1))
done

if [ "$signed_count" -eq 0 ]; then
  echo "sign-linux-packages: WARN — no artifacts found in $ARTIFACT_DIR (looked for *.deb, *.rpm, *.tar.gz)" >&2
else
  echo "sign-linux-packages: signed $signed_count artifact(s) in $ARTIFACT_DIR"
fi
