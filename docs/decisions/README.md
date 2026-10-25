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
| [0009](0009-star-os-apps-build-and-packaging.md) | Star OS applications: C++/Qt Quick, built as pacman packages | Accepted |
| [0010](0010-sun-store-flatpak.md) | Sun Store installs Flatpak apps from Flathub, per user, after consent | Accepted |
| [0011](0011-star-storage-persistence.md) | Star Storage keeps the live system's changes on a disk the person erases for it | Accepted (option); live polkit rule awaits owner review |
| [0012](0012-star-lens.md) | Star Lens reads the screen offline and sends images to Google Lens only when asked | Accepted |
| [0013](0013-live-application-catalogue.md) | The launcher lists every installed application, live, from KService | Accepted |
| [0014](0014-shell-desktop-services.md) | The Star OS shell provides notifications, quick settings and clipboard history | Accepted (features); backends await review |
| [0015](0015-weather-widget-network.md) | The weather widget contacts Open-Meteo only after the person enters a city | Accepted |
| [0016](0016-look-and-feel-lock-screen.md) | Star OS look and feel: Inter, a dark colour scheme, and a lock screen on the live medium | Accepted |
| [0017](0017-game-center-and-welcome.md) | Game Center lists installed games and runs them with GameMode; Welcome opens once | Accepted |

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
