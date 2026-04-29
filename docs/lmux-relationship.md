# lmux Relationship Draft

This is the working relationship language for an `lmux` Linux-focused fork or
derivative distribution. It is a draft for owned docs, release notes, and future
site copy. It is not a Manaflow outreach message by itself; Jess handles any
Manaflow-facing correspondence manually.

## Positioning

`lmux` is a friendly Linux-focused downstream of Manaflow's `cmux` project.

The intent is to widen the Linux testing and packaging surface around the same
core product idea while keeping attribution, support boundaries, and upstream
contribution etiquette clear. `lmux` should not present itself as the official
Manaflow Linux product unless Manaflow explicitly chooses that language.

Preferred wording:

- "`lmux` is a Linux-focused downstream of `cmux`."
- "`lmux` is based on Manaflow's open source `cmux` work and carries Linux,
  packaging, and WebAuthn/FIDO2 integration work in a separate fork."
- "`lmux` prepares small upstreamable fixes as handoff packets; Jess submits and
  discusses non-owned upstream PRs by hand."
- "Manaflow is invited to adopt, redirect, or coordinate any Linux work from
  this fork that is useful to upstream `cmux`."

Avoid wording that implies:

- Manaflow endorses, owns, or supports `lmux`
- `lmux` replaces upstream `cmux`
- upstream Ghostty, Bonsplit, Flathub, AUR, COPR, or distro maintainers should
  triage fork-specific reports before local review
- Tinyland can offer a non-GPL commercial license for Manaflow-owned code
  without a separate agreement

## License Posture

The current parent project license is `GPL-3.0-or-later`, with Manaflow also
offering separate commercial license terms for organizations that need them.

The practical `lmux` posture is:

- distribute `lmux` under `GPL-3.0-or-later`
- preserve upstream copyright and license notices
- mark Tinyland/Jess modifications clearly in source control, release notes,
  and docs where relevant
- publish corresponding source for distributed GPL binaries
- keep `THIRD_PARTY_LICENSES.md` current for bundled dependencies
- do not claim the right to relicense Manaflow-owned code outside the GPL path

Current dependency license facts in this checkout:

| Component | License posture |
|---|---|
| `cmux` parent work | `GPL-3.0-or-later` plus Manaflow commercial dual-license terms |
| `ghostty` | MIT |
| `vendor/bonsplit` | MIT |
| `vendor/ctap2` / `zig-ctap2` | Zlib or MIT |
| `vendor/zig-crypto` | Zlib or MIT |
| `vendor/zig-keychain` | Zlib or MIT |
| `vendor/zig-notify` | Zlib or MIT |

Re-check the exact repo or submodule before publishing a license statement.
Do not carry stale missing-license notes forward after a local verification pass.

## Support Boundary

Linux testers should start with owned `lmux`/`cmux` reporting surfaces:

- `Jesssullivan/cmux` issues for public, reproducible fork reports
- Tinyland Linear for private planning and synthesis
- checked-in docs for support-tier wording and runbooks

Only route a report outward after local triage shows it belongs upstream. For
non-owned projects, agents prepare handoff artifacts only; Jess submits and
corresponds manually.

## Manaflow Outreach Shape

When the time is right, the outreach should be short and specific:

```md
Hi Manaflow team,

I am maintaining a Linux-focused downstream of cmux under the lmux name. The
goal is to build out Linux packaging, distro QA, and WebAuthn/FIDO2 integration
without creating support confusion for the upstream cmux project.

The fork keeps the GPL path intact, preserves attribution, and treats Manaflow
as the upstream product/source of the original work. I am also keeping
upstreamable patches small and human-submitted rather than asking agents to
interact with your repos directly.

I would like lmux to be a friendly downstream that can grow the pool of Linux
users and produce careful fixes where they make sense upstream.

If you want to coordinate directly, I am reachable at jess@sulliwood.org.
```

## Operating Rule

Relationship work should not block urgent Linux packaging, QA, or submodule
sync work. Keep it visible, professional, and separate from bug triage.
