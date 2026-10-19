# Phase 0 plan: feasibility and architecture

Phase 0 goal (from the specification): prove a repeatable build and boot
process, document the major technology choices, identify licensing and
security uncertainties, and record human approval of the architecture.

## Phase 0 deliverables and status

| Deliverable | Where | Status |
| --- | --- | --- |
| Repository initialized | this repo | Done (documentation only) |
| License and contribution policy | ADR-0007, LICENSES.md, CONTRIBUTING.md | License accepted (GPL-3.0-or-later; docs CC-BY-SA-4.0). Contribution policy: draft |
| Initial threat model | docs/security/threat-model.md | Draft |
| Architecture decision records | docs/decisions/ | 0001–0005 and 0007 accepted; 0006 deferred |
| Supported hardware assumptions | below | Draft |
| Package baseline policy | ADR-0002 | Accepted |
| Wayland/compositor evaluation | ADR-0004 | KWin accepted; shell hosting decided by M0.2 |
| Installer framework evaluation | ADR-0005 | Calamares accepted |
| Btrfs snapshot and recovery prototype plan | ADR-0006 | Deferred to Phase 2 with plan |
| Build environment setup | ADR-0003 + milestone M0.1 | Implemented; see CI results before claiming it works |
| Qt/QML shell prototype | milestone M0.2 | Not started (starts after M0.1 passes) |
| Moon Browser integration checklist | integrations/moon-browser/ | Written; blocked on source |

## Smallest useful deliverable: M0.1 — console ISO prototype

The smallest deliverable that proves something real: **a Star OS–identified
Arch live ISO, built by CI from this repository with pinned package inputs,
that boots to a shell in QEMU (UEFI and BIOS) and in VMware Workstation.**

It has no desktop, installer, or branding artwork. Those depend on decisions
still awaiting approval. Every later milestone builds on this pipeline.

### Contents (implemented 2026-10-19)

```
distro/archiso/
  ARCHISO_VERSION                  # archiso version the overlay is validated against
  staros/                          # Star OS overlay on top of releng (ADR-0001)
    profiledef.append.sh           #   iso_name=staros, label, publisher, application
    airootfs/etc/staros-release    #   Star OS identity (os-release format, ID=staros)
    airootfs/etc/motd              #   prototype warning
    airootfs/etc/systemd/system/staros-boot-check.service
    airootfs/usr/local/libexec/staros-boot-check   # boot report + marker on serial
distro/baseline/ARCH_SNAPSHOT_DATE  # package baseline date (ADR-0002)
distro/baseline/packages.x86_64.txt # recorded package list (added after the first CI build)
scripts/build-iso.sh                # host and version checks, profile assembly, mkarchiso, records
scripts/ci/prepare-arch-build-host.sh   # pins a throwaway Arch container to the baseline
scripts/ci/check-package-manifest.sh    # T0-05
tests/iso/boot_test.py              # QEMU boot test (OVMF / SeaBIOS), read-only ISO, no disks
tests/iso/test_boot_test.py         # unit tests for the boot test
.github/workflows/iso.yml           # lint → build → package check + boot tests
docs/development/building.md
```

The profile is assembled at build time rather than committed as a full copy.
ADR-0001's implementation note explains why.

**Change to acceptance criterion 4:** the live system's `/etc/os-release` stays
Arch's. That file belongs to Arch's `filesystem` package. Overwriting it from
the archiso overlay would make package installation fail on a file conflict,
and replacing it properly needs a Star OS package, which needs the Star OS
repository (Phase 1). Until then, Star OS identity is carried by the boot menu
titles and `/etc/staros-release`.

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
4. The live environment identifies itself as Star OS (boot menu titles in the
   assembled profile, `ID=staros` in `/etc/staros-release`, reported at boot).
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
