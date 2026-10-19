# ADR-0002: Package baseline pinned to Arch Linux Archive snapshots

- Status: Accepted
- Date: 2026-10-19
- Deciders: project owner

## Context

Arch is a rolling release. The specification requires a **supported package
baseline** per Star OS release, so that custom components are tested against a
known set of packages instead of whatever the mirrors serve on build day. It
also keeps the rolling model for users: Star OS is not to be presented as an
immutable or atomic OS.

## Options considered

1. **Build from live mirrors** — simplest, but two builds on different days use
   different packages. Test results cannot be tied to a package set.
2. **Arch Linux Archive date snapshots** — the official archive at
   `archive.archlinux.org/repos/YYYY/MM/DD/` serves the repositories exactly
   as they were on a given day. Pointing `pacman.conf` at one date gives a fixed
   package set while still using official Arch packages and signatures.
3. **A Star OS–hosted mirror snapshot** — same idea, but hosted by the project.
   More robust and faster, but needs infrastructure, storage, and an operator.

## Decision

- **Phase 0–1:** builds use option 2. The baseline date lives in one file
  (`distro/baseline/ARCH_SNAPSHOT_DATE`, to be created with the first build
  milestone). Changing it is a normal reviewed change, and CI rebuilds and
  re-tests on the new date.
- Every build writes a **manifest** (exact package names and versions in the
  ISO) next to the ISO, so test results can be tied to a package set.
- **Before public releases:** re-evaluate option 3 for reliability, and define
  how the installed system's update center moves users from one validated
  baseline to the next (Phase 4).
- Packages are still verified with pacman's normal signature checking against
  `archlinux-keyring`. Signature checking is never disabled to work around a
  stale keyring; the keyring is updated instead.

## Consequences and trade-offs

- Reproducible package inputs for every build and test.
- The Arch Linux Archive is a single, community-funded service. It may be slow
  or rate-limited, so CI should cache packages and must not hammer it.
- A pinned baseline goes stale. Security updates require moving the date, so
  the baseline must be advanced on a regular schedule (to be defined in the
  Phase 4 update policy).

## Revisit if

- The archive becomes unreliable for CI.
- The project gains infrastructure to host its own snapshots.

## Approval

- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-19, in the AI agent session, as part of approving milestone M0.1
