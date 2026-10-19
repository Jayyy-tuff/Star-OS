# Phase 0 plan: feasibility and architecture

Phase 0 goal (from the specification): prove a repeatable build and boot
process, document the major technology choices, identify licensing and
security uncertainties, and record human approval of the architecture.

## Phase 0 deliverables and status

| Deliverable | Where | Status |
| --- | --- | --- |
| Repository initialized | this repo | Done (documentation only) |
| License and contribution policy | ADR-0007, CONTRIBUTING.md | License: owner decision pending. Contribution policy: draft |
| Initial threat model | docs/security/threat-model.md | Draft |
| Architecture decision records | docs/decisions/ | Proposed |
| Supported hardware assumptions | below | Draft |
| Package baseline policy | ADR-0002 | Proposed |
| Wayland/compositor evaluation | ADR-0004 | Proposed; prototype gate defined |
| Installer framework evaluation | ADR-0005 | Proposed |
| Btrfs snapshot and recovery prototype plan | ADR-0006 | Deferred to Phase 2 with plan |
| Build environment setup | ADR-0003 + milestone M0.1 | Proposed, **not implemented** |
| Qt/QML shell prototype | milestone M0.2 | Blocked on ADR-0004 approval |
| Moon Browser integration checklist | integrations/moon-browser/ | Written; blocked on source |

## Smallest useful deliverable: M0.1 — console ISO prototype

The smallest deliverable that proves something real: **a Star OS–identified
Arch live ISO, built by CI from this repository with pinned package inputs,
that boots to a shell in QEMU (UEFI and BIOS) and in VMware Workstation.**

It has no desktop, installer, or branding artwork. Those depend on decisions
still awaiting approval. Every later milestone builds on this pipeline.

### Proposed contents

```
distro/archiso/
  ARCHISO_VERSION          # archiso version the profile was copied from
  staros/                  # profile: unchanged releng copy, then Star OS commits
    profiledef.sh          #   iso_name=staros, label, publisher, application
    pacman.conf            #   repositories pinned to the baseline date
    packages.x86_64
    airootfs/etc/os-release                    # NAME="Star OS", ID=staros, ID_LIKE=arch
    airootfs/etc/systemd/system/staros-boot-check.service
    airootfs/usr/local/libexec/staros-boot-check  # prints a boot marker + summary
    (boot loader configs: titles changed to "Star OS live (prototype)",
     serial console added to the kernel command line for automated tests)
distro/baseline/ARCH_SNAPSHOT_DATE
scripts/build-iso.sh       # checks host + archiso version, runs mkarchiso,
                           # writes SHA256SUMS and the package manifest
scripts/test-iso-qemu.sh   # boots the ISO headless (OVMF / SeaBIOS), waits for
                           # the marker on the serial console, saves the log
.github/workflows/iso.yml  # lint → build (archlinux container) → boot tests
docs/development/building.md
```

The first commit of `distro/archiso/staros/` is an **unchanged copy** of
`releng` from the recorded archiso version. Every Star OS change is a separate
commit (ADR-0001).

### Acceptance criteria

1. A clean checkout builds the ISO with one documented command in CI. The ISO,
   `SHA256SUMS`, the package manifest, and the build log are uploaded as
   artifacts.
2. Two CI builds with the same baseline date produce identical package
   manifests. (Package inputs are pinned. Byte-identical ISOs are **not**
   claimed.)
3. The CI-built ISO boots in QEMU with OVMF (UEFI) and with SeaBIOS (BIOS) and
   prints the boot marker on the serial console within the timeout. Logs are
   uploaded whether the boot passes or fails.
4. The live environment identifies itself as Star OS (boot menu, `/etc/os-release`).
5. All shell scripts pass `shellcheck`.
6. **Owner-run:** the same CI-built ISO boots to a shell in VMware Workstation
   (UEFI, Secure Boot off), recorded in the
   [test plan](test-plan.md#manual-test-log) with the VMware version and VM
   settings.

M0.1 is done when 1–5 pass in CI and 6 is recorded. Until 6 is recorded, the
README says "boots in QEMU (CI)" and nothing about VMware.

### Explicitly out of scope for M0.1

Graphical session, installer, accounts, Secure Boot, ISO signing, a Star OS
package repository, branding artwork, and hardware support claims.

## Next: M0.2 — shell prototype on the live ISO

After ADR-0004 is approved: add KWin, the Star OS shell prototype, and a live
graphical session to the M0.1 ISO. Then run the six prototype checks listed in
ADR-0004 in QEMU and VMware. M0.2 closes Phase 0 together with recorded
architecture approval.

## Supported hardware assumptions (Phase 0)

These are **assumptions to test**, not support claims.

- x86-64 CPUs from AMD and Intel that Arch Linux's kernel supports.
- UEFI firmware is the primary target. BIOS boot of the live ISO is kept while
  archiso provides it and CI tests it. BIOS **installation** is undecided
  (ADR-0006).
- Secure Boot must be disabled for now (ADR-0006).
- Virtual machines: VMware Workstation (priority, manual), QEMU/KVM (CI),
  VirtualBox (later, best effort).
- Phase 1 graphics in VMware are expected to use the `vmwgfx` kernel driver
  with Mesa. 3D acceleration may need to be enabled in the VM settings. This is
  to be verified in M0.2.
- Minimum RAM and disk for the live and installed systems will be set from
  measurements in M0.2 and Phase 1, not guessed.
