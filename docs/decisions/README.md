# Architecture decision records

Short records of significant decisions: the problem, the options, the decision,
the trade-offs, and what would make us revisit it.

## Status values

- **Proposed** — written up, waiting for human approval. Do not build on it.
- **Accepted** — approved by a named human on a recorded date.
- **Deferred** — options documented; the decision is intentionally postponed to
  a later phase, with the evidence needed to make it.
- **Superseded by ADR-NNNN** — replaced; kept for history.

Architecture, security-sensitive, licensing, destructive-installation, and
release decisions require explicit human approval before they become
**Accepted**. Approval is recorded in the ADR's *Approval* section.

## Index

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-arch-base-and-archiso.md) | Arch Linux base and archiso for live/installation media | Accepted |
| [0002](0002-package-baseline.md) | Package baseline pinned to Arch Linux Archive snapshots | Accepted |
| [0003](0003-build-and-test-infrastructure.md) | Build and test infrastructure | Accepted |
| [0004](0004-compositor-and-shell-foundation.md) | Wayland compositor and shell foundation | Accepted (KWin) |
| [0005](0005-installer-framework.md) | Installer framework | Accepted (Calamares) |
| [0006](0006-boot-snapshots-secure-boot.md) | Bootloader, Btrfs snapshots, and Secure Boot | Deferred to Phase 2 |
| [0007](0007-licensing.md) | Licensing of original components | Accepted (GPL-3.0-or-later) |
| [0008](0008-m02-shell-hosting-and-live-session.md) | M0.2 shell hosting and live session | Accepted (option A2; implementation in progress) |

## Template

```markdown
# ADR-NNNN: Title

- Status: Proposed
- Date: YYYY-MM-DD
- Deciders: (names)

## Context
## Options considered
## Decision
## Consequences and trade-offs
## Revisit if
## Approval
- Approved by: (name), (date) — or "pending"
```
