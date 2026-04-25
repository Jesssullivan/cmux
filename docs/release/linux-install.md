# Linux Install And Verification

This document is the user-facing install and verification surface for Linux
release artifacts.

Use it with:

- `docs/release/SIGNING.md`
- `docs/linux-packaging-cd-plan.md`
- `docs/linux-validation-checklist.md`

## Support Tiers

Current Linux support should be described by distro tier, not as one flat
promise.

| Distro family | Artifact | Current posture |
|---|---|---|
| Ubuntu 24.04 | `DEB` | broad-feature target |
| Fedora 42 | Fedora `RPM` | broad-feature target |
| Debian 12 | `DEB` | package/runtime baseline; browser and WebAuthn status must be recorded explicitly |
| Rocky 10 | Rocky `RPM` | terminal-first target; uses the no-WebKit package path |
| Arch, Mint, NixOS | source/package-manager follow-up | early QA target, not a broad support claim yet |

## Download

Download artifacts from the `Jesssullivan/cmux` GitHub release page for the
tag under test.

Expected Linux artifacts:

- `cmux_<version>_amd64.deb`
- `cmux_<version>_arm64.deb`
- `cmux-<version>-1.fc42.x86_64.rpm`
- `cmux-<version>-1.fc42.aarch64.rpm`
- `cmux-<version>-1.el10.x86_64.rpm`
- `cmux-<version>-1.el10.aarch64.rpm`
- `cmux-<version>-linux-amd64.tar.gz`
- `cmux-<version>-linux-arm64.tar.gz`

Each signed artifact should have a sibling `.asc` signature.

## Import The Signing Key

The release-signing public key is expected at:

```bash
curl -L https://github.com/Jesssullivan/cmux/raw/main/docs/release/cmux-release-signing-key.asc \
  | gpg --import
```

If that URL is not available for the release you are testing, use the public key
attached to the release notes or treat the release as unsigned.

For RPM verification:

```bash
sudo rpm --import https://github.com/Jesssullivan/cmux/raw/main/docs/release/cmux-release-signing-key.asc
```

## Verify And Install A DEB

Use this path for Ubuntu 24.04 and Debian 12.

```bash
gpg --verify cmux_<version>_amd64.deb.asc cmux_<version>_amd64.deb
sudo apt-get update
sudo apt-get install ./cmux_<version>_amd64.deb
cmux --version
```

On Debian 12, record browser and WebAuthn status explicitly. A successful
package install is baseline proof, not a full-feature claim.

## Verify And Install A Fedora RPM

Use this path for Fedora 42.

```bash
rpm -K cmux-<version>-1.fc42.x86_64.rpm
sudo dnf install ./cmux-<version>-1.fc42.x86_64.rpm
cmux --version
```

Fedora 42 is a broad-feature target, so QA should include terminal/split,
socket/API, browser, notification, and lock behavior where practical.

## Verify And Install A Rocky RPM

Use this path for Rocky 10.

```bash
rpm -K cmux-<version>-1.el10.x86_64.rpm
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --set-enabled crb
sudo dnf install ./cmux-<version>-1.el10.x86_64.rpm
cmux --version
```

Rocky 10 is terminal-first until a browser-capable package path is proven. QA
should verify terminal/split/focus, basic socket/API behavior, and clear
behavior for browser commands when WebKitGTK is unavailable.

## Verify And Install A Tarball

Use the tarball only when a native package is not appropriate.

```bash
gpg --verify cmux-<version>-linux-amd64.tar.gz.asc cmux-<version>-linux-amd64.tar.gz
tar xzf cmux-<version>-linux-amd64.tar.gz
cd cmux-<version>-linux-amd64
sudo ./install.sh /usr/local
cmux --version
```

The tarball installer writes the udev rules needed for FIDO2/U2F hardware keys.
Reload udev rules if the package manager did not do it for you:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw
```

## QA Report Template

When reporting Linux install results, include:

- artifact filename
- artifact SHA256 if available
- distro name and version
- install command used
- `cmux --version` output
- terminal/split smoke result
- socket/API smoke result
- browser status
- notification status
- WebAuthn status
- logs or screenshots for failures
