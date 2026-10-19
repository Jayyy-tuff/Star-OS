# ADR-0001: Arch Linux base and archiso for live/installation media

- Status: Proposed
- Date: 2026-10-19
- Deciders: pending owner approval

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

## Decision (proposed)

Use **archiso**. Derive the Star OS profile from the `releng` profile of a
**specific, recorded archiso version**: copy that version's
`/usr/share/archiso/configs/releng`, commit it unchanged as the first step,
then apply Star OS changes as small, reviewable commits on top.

Starting from an unchanged copy makes every Star OS change visible in `git log`
and makes upgrading to a newer archiso a reviewable diff, rather than relying
on our memory of the profile format. (The profile format has changed between
archiso versions — for example, the names of boot modes — so the version in use
must be recorded and checked by the build script.)

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

- Approved by: pending
