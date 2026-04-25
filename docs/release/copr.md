# COPR Submission Runbook

This is a human-driven runbook. COPR publication is a third-party package
registry action, so agents may prepare files in this repo but must not create
projects, submit builds, or comment in Fedora/COPR surfaces.

## Current Scaffold

- Draft spec: `packaging/copr/cmux.spec`
- Fedora posture: broad-feature RPM
- Rocky posture: terminal-first RPM using `--without webkit`

The COPR spec expects a source archive that already contains submodules.
GitHub auto-generated tag archives are not sufficient for this repo.

## Source Archive

Create the source archive from a clean checkout after the target release tag is
available:

```bash
git clone --recursive https://github.com/Jesssullivan/cmux cmux-<version>
cd cmux-<version>
git checkout lab-v<version>
git submodule update --init --recursive
cd ..
tar czf cmux-<version>.tar.gz cmux-<version>
```

Upload that archive with the spec when submitting the COPR build.

## Fedora Build

Fedora should use the default WebKit-enabled build:

```bash
copr-cli build <project> cmux-<version>.src.rpm
```

Before publication, record one Fedora 42 package/runtime QA result in an owned
tracker.

## Rocky Build

Rocky should use the terminal-first build until a browser-capable path is
proven:

```bash
rpmbuild -bs packaging/copr/cmux.spec --without webkit
copr-cli build <project> <generated-src-rpm>
```

Before publication, record one Rocky 10 terminal-first QA result in an owned
tracker.

## Pre-Submission Checklist

- [ ] `Version` matches the release tag
- [ ] source archive contains submodules
- [ ] Fedora build was reviewed as broad-feature
- [ ] Rocky build was reviewed as terminal-first
- [ ] package descriptions avoid unsupported WebAuthn/session-restore claims
- [ ] direct QA evidence exists for the target distro

## Linear

- Project: cmux/C — Distribution Surfaces (`TIN-181`)
- Related QA: `docs/linux-qa-intake.md`
