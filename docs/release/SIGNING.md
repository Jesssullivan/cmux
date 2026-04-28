# Linux package signing runbook

This document covers GPG signing for the Linux release pipeline (DEB, RPM,
tarball). Signing is performed in CI via `scripts/sign-linux-packages.sh`,
gated on three GitHub Actions secrets in the `Jesssullivan/cmux` repo. If
the secrets are absent the script no-ops, so local/unsigned builds keep
working. Release CI sets `REQUIRE_LINUX_GPG=1`, so missing signing secrets
fail the workflow instead of uploading unsigned artifacts.

For end-user install and verification commands, see
`docs/release/linux-install.md`.

## What gets signed

| Artifact         | Signature              | Verification                   |
|------------------|------------------------|--------------------------------|
| `cmux_*.deb`     | Detached `*.deb.asc`   | `gpg --verify cmux_*.deb.asc`  |
| `cmux-*.rpm`     | In-package + `*.asc`   | `rpm -K cmux-*.rpm`            |
| `cmux-*.tar.gz`  | Detached `*.tar.gz.asc`| `gpg --verify *.tar.gz.asc`    |

RPMs get **both** an in-package signature (`rpmsign --addsign`, the form
`dnf` and `rpm -K` understand) and a sibling detached `.asc` for tooling
that prefers detached signatures (mirrors, repo-md indexers, package-sig
audit scripts).

## CI architecture

```
build-deb (matrix: amd64 + arm64)
  └─ assemble .deb + .tar.gz
  └─ Sign DEB and tarball with GPG  ← scripts/sign-linux-packages.sh
  └─ assert detached signatures     ← scripts/assert-linux-package-signatures.sh
  └─ upload-artifact: *.deb + *.deb.asc
  └─ upload-artifact: *.tar.gz + *.tar.gz.asc

build-rpm (matrix: amd64 + arm64)
  └─ assemble .rpm
  └─ Sign RPM with GPG              ← scripts/sign-linux-packages.sh
  └─ assert detached signatures     ← scripts/assert-linux-package-signatures.sh
  └─ upload-artifact: *.rpm + *.rpm.asc

release
  └─ download-artifact (all matrix legs)
  └─ gh release upload (.deb, .rpm, .tar.gz, and all .asc siblings)
```

The signing script is **idempotent**:

- Re-running on already-signed artifacts overwrites existing `.asc` files
- `rpmsign --addsign` replaces an existing in-package signature
- Each invocation creates a fresh ephemeral `GNUPGHOME` and tears it down
  on exit (via `trap cleanup EXIT`), so the host keyring is never touched

## Required GitHub Actions secrets

Set these on the **`Jesssullivan/cmux`** repo (Settings → Secrets and
variables → Actions). All three must be present for signing to run; if
`LINUX_GPG_PRIVATE_KEY_BASE64` is missing the script exits 0 with a
warning by default. Release CI sets `REQUIRE_LINUX_GPG=1`, so missing
secrets fail the workflow before artifacts are uploaded.

| Secret                            | Format                                | Notes                              |
|-----------------------------------|---------------------------------------|------------------------------------|
| `LINUX_GPG_PRIVATE_KEY_BASE64`    | base64-encoded ASCII-armored secret   | See "Generate the key" below      |
| `LINUX_GPG_PASSPHRASE`            | UTF-8 plaintext                        | Treat as high-sensitivity         |
| `LINUX_GPG_KEY_ID`                | fingerprint or short ID                | Used as `--local-user`/`%_gpg_name` |

The encrypted source of truth for the current release-signing material is
`secrets/linux-release-signing.sops.yaml`. To sync the SOPS values into
GitHub Actions after a rotation:

```bash
scripts/sync-linux-signing-secrets.sh
```

To inspect non-secret metadata without exposing the key material:

```bash
sops --decrypt --extract '["linux_release_signing"]["fingerprint"]' \
  secrets/linux-release-signing.sops.yaml
```

## Generate the key (one-time)

Generate a dedicated release-signing key (do not reuse a personal key).
Use a strong passphrase; rotate the key annually or on compromise.

```bash
# 1. Generate the key (interactive). RSA 4096 / sign-only / no expiry,
#    or set --expire-date 1y if you want forced annual rotation.
gpg --full-generate-key
#   Real name:    cmux release signing
#   Email:        releases@example.invalid     (use a non-personal addr)
#   Comment:      cmux Linux release packages

# 2. Capture the key fingerprint
gpg --list-secret-keys --keyid-format=long
#   sec   rsa4096/ABCDEF0123456789 2026-04-17 [SC]
#         FULL40CHARFINGERPRINTGOESHEREFOR...

# 3. Export and base64-encode the secret key
gpg --export-secret-keys --armor "ABCDEF0123456789" | base64 -w0 > linux-gpg-key.b64

# 4. Set the three GitHub Actions secrets
gh secret set LINUX_GPG_PRIVATE_KEY_BASE64 \
  --repo Jesssullivan/cmux \
  --body "$(cat linux-gpg-key.b64)"
gh secret set LINUX_GPG_PASSPHRASE --repo Jesssullivan/cmux
gh secret set LINUX_GPG_KEY_ID --repo Jesssullivan/cmux \
  --body "ABCDEF0123456789"

# 5. Wipe the local copy
shred -u linux-gpg-key.b64
```

Also export the **public** key — users need it to verify:

```bash
gpg --export --armor "ABCDEF0123456789" > docs/release/cmux-release-signing-key.asc
```

Commit `docs/release/cmux-release-signing-key.asc` to the repo and link
it from the project README so users have a stable place to fetch it.

## End-user verification

Steps to give to users (paste into the release notes / README):

```bash
# Import the cmux release-signing public key
curl -L https://github.com/Jesssullivan/cmux/raw/main/docs/release/cmux-release-signing-key.asc \
  | gpg --import

# Verify a DEB
gpg --verify cmux_0.75.0_amd64.deb.asc cmux_0.75.0_amd64.deb

# Verify a tarball
gpg --verify cmux-0.75.0-linux-amd64.tar.gz.asc cmux-0.75.0-linux-amd64.tar.gz

# Verify an RPM (in-package signature)
rpm --import https://github.com/Jesssullivan/cmux/raw/main/docs/release/cmux-release-signing-key.asc
rpm -K cmux-0.75.0-1.x86_64.rpm
# expected: digests signatures OK
```

`apt-get` users with a third-party repo would normally pin the key under
`/etc/apt/keyrings/`; for direct `.deb` downloads the detached `.asc`
verification above is the supported path.

## Local testing of the signing script

The script is safe to run locally — it only signs when all three env
vars are present, and uses an ephemeral `GNUPGHOME`:

```bash
# No-op path (no secrets in env): exits 0 with a warning
bash scripts/sign-linux-packages.sh /tmp/some-empty-dir

# Required-signing path (used by release CI): fails if secrets are absent
REQUIRE_LINUX_GPG=1 bash scripts/sign-linux-packages.sh /tmp/some-empty-dir

# Real signing locally (e.g. against a test key in your own keyring)
LINUX_GPG_PRIVATE_KEY_BASE64="$(gpg --export-secret-keys --armor TESTKEYID | base64 -w0)" \
LINUX_GPG_PASSPHRASE='your-test-passphrase' \
LINUX_GPG_KEY_ID='TESTKEYID' \
  bash scripts/sign-linux-packages.sh /path/to/dir/with/artifacts
```

## Rotation

To rotate the signing key:

1. Generate a new key per "Generate the key" above
2. Update the three GitHub Actions secrets
3. Commit the new public key to `docs/release/cmux-release-signing-key.asc`
   (replace, not append — a single current key is simpler for users)
4. Mention the rotation in the next release's notes
5. Optionally publish a revocation cert for the old key:
   `gpg --gen-revoke OLDKEYID > old-key-revoke.asc` and import that
   into a public keyserver

## Troubleshooting

- **CI logs show "LINUX_GPG_PRIVATE_KEY_BASE64 not set"**: the secret is
  missing on this fork. Release CI should fail loudly; set it (see above)
  and re-run the release workflow.
- **rpmsign quoting issues with passphrase**: the script reads the
  passphrase via `--passphrase-file` (file lives inside the ephemeral
  `GNUPGHOME`), so passphrase contents are not subject to shell quoting
  rules. If you see quoting errors in `rpmsign` output, the script has
  been edited to embed the passphrase in `%__gpg_sign_cmd` directly —
  revert to the `--passphrase-file` form.
- **`gpg: decryption failed: No secret key`**: `LINUX_GPG_KEY_ID`
  doesn't match the imported key. Use the long key ID from
  `gpg --list-secret-keys --keyid-format=long`.
- **Detached `.asc` missing from release**: check the matrix-leg
  artifact (`cmux-linux-deb-amd64`, etc.) actually contains the
  `.asc`. `scripts/assert-linux-package-signatures.sh` should fail the
  job before upload if any package lacks a detached signature.
