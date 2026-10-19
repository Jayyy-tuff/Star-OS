# ADR-0005: Installer framework

- Status: Proposed
- Date: 2026-10-19
- Deciders: pending owner approval

## Context

The installer is the most dangerous component in the project. It can destroy
user data. The specification asks to evaluate a mature framework such as
Calamares before considering a custom installer, and lists required behaviour:
explicit disk selection, separate whole-disk / dual-boot / manual flows,
data-loss warnings, explicit confirmation, recommended encryption with
recovery-key guidance, account creation, bootloader setup, verification, and
understandable errors with log access.

## Options considered

1. **Calamares** — a distribution-independent installer framework in Qt/C++
   with QML-capable views and Python modules. It handles partitioning through
   KPMcore, LUKS encryption, Btrfs subvolumes, user creation, and bootloader
   installation. Many Arch derivatives already use it. GPL-3.0-or-later. Active:
   the 3.4 series was released through 2026, and the project moved its
   releases from GitHub to Codeberg. As far as known it is **not** in Arch's
   official repositories *(verify)*, so Star OS would package it.
2. **archinstall** — Arch's official guided installer (Python, text UI), also
   usable as a library. Arch-native logic, but no graphical UI. A Star OS QML
   front end over the archinstall library would be a new, privileged
   architecture with its own risks.
3. **Fully custom installer** — maximum design freedom. It also means
   re-implementing partitioning, encryption, and bootloader logic where bugs
   destroy data. Highest risk.

## Decision (proposed)

Use **Calamares**, packaged in the Star OS repository at a recorded version,
with:

- Star OS branding and QML slideshow/views using the shared design system.
- A curated module sequence: welcome/requirements → locale → keyboard →
  partition (erase / alongside / manual, with explicit target selection) →
  encryption explanation and recovery guidance → users → summary with an
  explicit destructive-action confirmation → install → finished.
- Star OS–specific Python modules only where Calamares has no equivalent (for
  example, writing the snapshot configuration).

**Required verification before any real use:** an automated test matrix on
disposable QEMU disks proving that the installer touches only the disk the user
selected (multi-disk VMs, a disk with an existing Windows-like partition table,
and a disk with existing data). These are release-blocking tests.

## Consequences and trade-offs

- We inherit Calamares's UI structure. Some screens may look less original than
  the rest of Star OS until custom QML views are written.
- We depend on Calamares's release cadence and KPMcore. Both must be in the
  package baseline and tested.
- Calamares runs as root in the live session. Star OS modules must follow the
  privileged-code rules: no shell-string construction and validated inputs.

## Revisit if

- Required safeguards (for example, unambiguous target selection on
  multi-disk systems) cannot be achieved through configuration and custom
  views.
- Calamares maintenance stalls.

## Approval

- Approved by: pending
