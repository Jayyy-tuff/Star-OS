# Test plan

Status: draft, covering Phase 0 in detail and later phases in outline.

## Rules

- **Never** run installer or disk tests against a real user disk. Use
  disposable virtual disks only. Automated tests must refuse to run if the
  target is not a disk image they created.
- A result is recorded only when the test was actually run. Each record names
  the commit, the environment, the date, and where the logs are.
- QEMU results are never reported as VMware or real-hardware results.
- If a target or threshold turns out to be unrealistic, change it in a reviewed
  commit that cites measurements. Never weaken a test silently.

## Environments

| ID | Environment | Runs | Owner |
| --- | --- | --- | --- |
| E-CI | GitHub Actions: `archlinux` container (build), Ubuntu runner with KVM (QEMU boot) | Automatically on every push | CI |
| E-VMW | VMware Workstation on the owner's PC | Manually per milestone and release candidate | Project owner |
| E-VBOX | VirtualBox | Later, best effort | TBD |
| E-HW | Real hardware matrix | From Phase 1 onward | TBD |

## Phase 0 tests (milestone M0.1)

| ID | Test | Env | Pass condition |
| --- | --- | --- | --- |
| T0-01 | Shell scripts pass lint | E-CI | `shellcheck` exits 0 on `scripts/` and profile scripts |
| T0-02 | Build host check | E-CI | `build-iso.sh` refuses to run if not on Arch, not root, or archiso version ≠ `ARCHISO_VERSION`, with a clear message |
| T0-03 | ISO builds | E-CI | `mkarchiso` exits 0. ISO, `SHA256SUMS`, and manifest exist and are uploaded |
| T0-04 | Checksum verifies | E-CI | `sha256sum -c SHA256SUMS` passes on the downloaded artifact |
| T0-05 | Pinned inputs | E-CI | The ISO's package list equals the recorded `distro/baseline/packages.x86_64.txt`, so every build at the same baseline date has the same packages |
| T0-06 | UEFI boot | E-CI | QEMU + OVMF: the boot report and marker `STAROS-LIVE-BOOT-OK` appear on the serial console within the timeout (start at 5 min, then tighten from measurements). The report must say `firmware=uefi` |
| T0-07 | BIOS boot | E-CI | Same as T0-06 with SeaBIOS and `firmware=bios` |
| T0-08 | Identity | E-CI | The build log shows the Star OS boot menu titles. The boot report has `id=staros` (from `/etc/staros-release`) |
| T0-09 | Failure detection | E-CI | The harness, given a non-bootable image, reports a failed boot (exit 1) and still writes its result file and logs. Boot logs are uploaded whether a boot passes or fails |
| T0-10 | VMware UEFI boot | E-VMW | See manual procedure. Shell reached, marker present in journal |
| T0-11 | VMware BIOS boot | E-VMW | Same with BIOS firmware (optional while BIOS support is undecided) |

## Phase 0 tests (milestone M0.2, after ADR-0004 approval)

| ID | Test | Env | Pass condition |
| --- | --- | --- | --- |
| T0-20 | Live graphical session starts | E-CI, E-VMW | Compositor and shell running. A screenshot is captured in CI |
| T0-21 | Taskbar and launcher work | E-VMW | Open, list, and switch two apps with the mouse |
| T0-22 | Keyboard-only operation | E-VMW | T0-21 completed without a mouse. Focus always visible |
| T0-23 | Scaling | E-VMW | Layout correct at 100/150/200%. Screenshots recorded |
| T0-24 | Screen reader | E-VMW | Orca announces launcher entries |
| T0-25 | Resource baseline | E-VMW, E-CI | Idle RAM/CPU after a defined settling period recorded (no pass/fail yet; this sets the first budget) |

## Later phases (outline, from specification Part VII)

- **Phase 1:** hardware detection; NetworkManager (Ethernet in VMs); PipeWire
  output device present; install to a disposable disk and boot the installed
  system; local account login.
- **Phase 2 (release-blocking class):** installer touches only the selected disk
  (multi-disk VMs, a disk with existing partitions, a disk with data);
  destructive-confirmation cannot be bypassed; LUKS2 install and unlock;
  recovery-key workflow review; snapshot/rollback matrix in ADR-0006; dual boot
  with a Windows-layout disk.
- **Phase 3:** shell/settings integration; accessibility checks (keyboard,
  focus, contrast, reduced motion, scaling, screen reader); offline operation
  with networking disabled; shell crash does not lose user data.
- **Phase 4:** signed-package verification; untrusted repository rejected;
  update interrupted (network cut, power loss simulated with a VM reset); low
  disk space blocks the update before changes; pre-update snapshot verified
  before proceeding.
- **Phase 5:** app install/remove; system monitor shows "unavailable" for
  missing sensors instead of made-up values; backup and restore round-trip;
  default browser handling.
- **Phase 6:** mode switching; controller navigation; game library detection
  against fixture libraries; compatibility labels backed by evidence records.
- **Security, continuous:** dependency/vulnerability scanning; fuzzing of parsers
  and privileged D-Bus interfaces; privilege-boundary review per privileged
  service; diagnostic bundle privacy review.
- **Performance:** benchmark profiles and measurements per specification §20,
  starting when the reference machines are named.

## Manual procedure: VMware Workstation boot (T0-10 / T0-11)

1. Download the ISO and `SHA256SUMS` from the CI run's artifacts.
2. Verify the checksum. In PowerShell:
   `Get-FileHash .\staros-*.iso -Algorithm SHA256`, then compare with
   `SHA256SUMS`. Stop if they differ.
3. Create a new VM: guest OS "Other Linux 6.x kernel 64-bit", 2 vCPU, 4 GB RAM,
   NAT network. No virtual disk is needed for a live boot test.
4. VM Settings → Options → Advanced → Firmware type: **UEFI**, with
   **Secure Boot unchecked**. (For T0-11, choose BIOS.)
5. CD/DVD: use the ISO file. Power on.
6. Record: does the boot menu say "Star OS live (prototype)"? Does it reach a
   shell prompt? How long does it take, measured roughly from power-on to the
   prompt?
7. At the prompt, run and photograph or copy the output:
   `cat /etc/staros-release`, `systemctl is-system-running`,
   `journalctl -b -u staros-boot-check --no-pager`, `ip -br link`, `lsblk`.
8. Fill in a row in the log below. Attach any errors or screenshots to an issue.

## Manual test log

| Date | Test | Commit / CI run | Environment (VMware version, host OS, firmware) | Result | Notes / logs |
| --- | --- | --- | --- | --- | --- |
| — | — | — | — | No manual tests run yet | — |
