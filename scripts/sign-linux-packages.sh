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
# warning so that local builds (without secrets) continue to work. Set
# REQUIRE_LINUX_GPG=1 in release CI to fail instead.
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
REQUIRE_LINUX_GPG="${REQUIRE_LINUX_GPG:-0}"

if [ -z "${LINUX_GPG_PRIVATE_KEY_BASE64:-}" ]; then
  if [ "$REQUIRE_LINUX_GPG" = "1" ]; then
    echo "sign-linux-packages: ERROR — LINUX_GPG_PRIVATE_KEY_BASE64 not set and REQUIRE_LINUX_GPG=1" >&2
    exit 1
  fi
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

PUBLIC_KEY_FILE="$GNUPGHOME/public.asc"
gpg --batch --armor --export "$LINUX_GPG_KEY_ID" > "$PUBLIC_KEY_FILE"
RPM_DBPATH="$GNUPGHOME/rpmdb"
mkdir -p "$RPM_DBPATH"

# Write the passphrase to a file inside the ephemeral GNUPGHOME so it
# gets cleaned up by `trap cleanup EXIT`. Using --passphrase-file avoids
# embedding shell-specific syntax (here-strings) in %__gpg_sign_cmd —
# rpmsign may invoke the macro under /bin/sh which is not always bash.
PASSPHRASE_FILE="$(mktemp "$GNUPGHOME/passphrase.XXXXXX")"
chmod 600 "$PASSPHRASE_FILE"
printf '%s' "$LINUX_GPG_PASSPHRASE" > "$PASSPHRASE_FILE"

# rpmsign reads ~/.rpmmacros — point it at the imported key
RPMMACROS="$HOME/.rpmmacros"
if command -v rpmsign >/dev/null 2>&1; then
  cat > "$RPMMACROS" <<RPMCONF
%_signature gpg
%_gpg_name $LINUX_GPG_KEY_ID
%__gpg_sign_cmd %{__gpg} gpg --batch --no-armor --pinentry-mode loopback --passphrase-file ${PASSPHRASE_FILE} --no-secmem-warning -u "%{_gpg_name}" -sbo %{__signature_filename} %{__plaintext_filename}
RPMCONF
fi

sign_detached() {
  local file="$1"
  local out="${file}.asc"
  echo "sign-linux-packages: signing $file → $out"
  gpg --batch --yes \
    --pinentry-mode loopback \
    --passphrase-file "$PASSPHRASE_FILE" \
    --local-user "$LINUX_GPG_KEY_ID" \
    --armor --detach-sign \
    --output "$out" \
    "$file"
  # Verify immediately so a bad passphrase / wrong key ID / corrupted
  # import surfaces here in CI rather than at user-verify time.
  echo "sign-linux-packages: verifying $out"
  gpg --batch --verify "$out" "$file" 2>&1 | sed 's/^/  gpg: /'
}

sign_rpm() {
  local file="$1"
  echo "sign-linux-packages: rpmsign --addsign $file"
  if ! command -v rpmsign >/dev/null 2>&1; then
    echo "sign-linux-packages: WARN — rpmsign not available; skipping in-package RPM signature for $file" >&2
    sign_detached "$file"
    return
  fi
  rpmsign --addsign "$file"
  # Verify the in-package signature was actually applied.
  echo "sign-linux-packages: verifying in-package RPM signature for $file"
  if command -v rpmkeys >/dev/null 2>&1; then
    rpmkeys --dbpath "$RPM_DBPATH" --import "$PUBLIC_KEY_FILE"
  else
    rpm --dbpath "$RPM_DBPATH" --import "$PUBLIC_KEY_FILE"
  fi
  rpm --dbpath "$RPM_DBPATH" -K "$file" 2>&1 | sed 's/^/  rpm: /'
  if ! rpm --dbpath "$RPM_DBPATH" -K "$file" | grep -q 'signatures OK'; then
    echo "sign-linux-packages: ERROR — RPM signature verification failed for $file" >&2
    exit 1
  fi
  # Also produce a detached sig for tooling that prefers it (and verify it).
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
  # Reaching here means secrets ARE set (the early no-secret no-op exited
  # at line ~31). If no artifacts exist the build is broken — fail loud
  # so the release pipeline doesn't silently ship unsigned bits.
  echo "sign-linux-packages: ERROR — secrets are set but no artifacts found in $ARTIFACT_DIR" >&2
  echo "  (looked for *.deb, *.rpm, *.tar.gz; check the build step)" >&2
  exit 1
else
  echo "sign-linux-packages: signed $signed_count artifact(s) in $ARTIFACT_DIR"
fi
