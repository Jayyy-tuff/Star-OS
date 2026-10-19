# ADR-0001: Arch Linux base and archiso for live/installation media

- Status: Accepted
- Date: 2026-10-19
- Deciders: project owner

## Context

The project specification fixes Arch Linux as the base distribution and asks
for established ISO tooling "such as archiso, after verifying its suitability".
We need a way to produce a bootable live ISO that can later carry a graphical
session and an installer.

## Options considered

1. **archiso** — the tool Arch Linux uses to build its official monthly ISOs.
   Profiles are plain directories (package list, `pacman.conf`, `airootfs/`
   overlay, boot loader configs, `profiledef.sh`). It ships two reference
   profiles: `releng` (the official ISO) and `baseline` (minimal). Many Arch
   derivatives build their media with it.
2. **Custom image scripts** (pacstrap + mksquashfs + xorriso by hand) — full
   control, but re-implements what archiso already maintains, including
   hybrid BIOS/UEFI boot images.
3. **mkosi** (systemd project) — builds disk images and supports Arch, but is
   aimed at disk/OS images more than hybrid live ISOs; less common for Arch
   live media.

## Decision

Use **archiso**. Derive the Star OS profile from the `releng` profile of a
**specific, recorded archiso version**, and keep every Star OS change small and
reviewable.

The profile format has changed between archiso versions (for example, the
names of boot modes). So the version in use is recorded in
`distro/archiso/ARCHISO_VERSION`, and the build script refuses to run with any
other version.

### Implementation note (2026-10-19)

The proposal was to commit an unchanged copy of `releng` and then change it in
later commits. The agent that implemented M0.1 could not obtain `releng`: its
environment cannot reach Arch package sources. M0.1 therefore **assembles** the
profile at build time instead:

1. Copy `releng` from the pinned archiso package installed on the build host.
2. Apply the Star OS overlay in `distro/archiso/staros/` (extra files, and
   `profiledef.sh` settings appended so that they override releng's).
3. Apply two checked edits: pacman repositories pinned to the baseline
   snapshot, and boot menu titles. Each edit fails the build if the expected
   releng text is not found.

Every Star OS change is still a reviewable file in git. The assembled profile is
uploaded with each CI build (`profile.tar.gz`) so reviewers can see the
complete result. If the overlay grows to the point that reading it is harder
than reading a full profile, switch to a committed full copy.

## Consequences and trade-offs

- The ISO must be built on Arch Linux (or in an Arch container) with root
  privileges; archiso is not available on Ubuntu or Windows.
- The live environment inherits releng behaviour, including automatic root
  login on the console. That is acceptable for live media only and is
  documented in the threat model.
- archiso's own boot setup (systemd-boot for UEFI, syslinux for BIOS in the
  releng profile) is used for the **live ISO only**. The **installed system's**
  boot loader is a separate decision (ADR-0006).

## Revisit if

- archiso can no longer produce the media we need (for example, a Secure Boot
  chain we cannot express in a profile).
- The Arch project stops maintaining archiso.

## Approval

- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-19, in the AI agent session, as part of approving milestone M0.1
