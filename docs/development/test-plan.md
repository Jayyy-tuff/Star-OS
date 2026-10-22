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

## Phase 0 tests (milestone M0.2, ADR-0008)

Each M0.2 test has evidence at up to three levels: unit tests of the
`StarOS.Shell` QML module (offscreen, no Plasma), the real CI-built ISO in
QEMU/KVM, and the owner's VMware run. A QEMU result is never reported as a
VMware or hardware result. The "CI now" column says what is automated today;
the rest is planned (design spec, iterations 4–8) or owner-run.

| ID | Test | Env | Pass condition | CI now |
| --- | --- | --- | --- | --- |
| T0-20 | Live graphical session starts | E-CI, E-VMW | On the booted ISO (UEFI and BIOS), `staros-session-report` prints `STAROS-SESSION-CHECK` with `logind_type=wayland`, `seat=seat0`, `shell=org.staros.shell`, the layout (one bottom, non-floating `org.staros.taskbar` panel; `org.staros.desktop` with the `org.kde.color` wallpaper), `grant=ok`, no `plasmashellrc` override, `PLASMA_DEFAULT_SHELL` set in plasmashell, and no variable from `scripts/ci/forbidden-env.txt` in KWin or plasmashell; then `STAROS-SESSION-OK`. A PNG screen dump is uploaded. The QML unit tests pass at 100, 150 and 200 % | Session report and checks: **yes** (`boot-test`). Screen band line: informational. Unit tests: **yes** (`shell-checks`) |
| T0-20b | Session stays up | E-CI, E-VMW | `STAROS-SESSION-STABLE` 330 s after ready: same plasmashell and KWin processes, no restarts of `plasma-plasmashell` or `staros-live-session` | **yes** (`idle`, three runs) |
| T0-21 | Taskbar and launcher work | E-CI, E-VMW | Unit: one task button per window, activation signals, search, launch, empty states. Session: launch two apps from the launcher, see both in the taskbar, switch between them (KWin's active window agrees). Owner: the same with the mouse | Unit: **yes**. Session: **yes** (`session-test` S5–S7) |
| T0-22 | Keyboard-only operation | E-CI, E-VMW | Unit: Tab and arrow order, Return/Space/Escape, search ↔ grid, the empty window list never focused, focus-ring pixels at each scale. Session: the T0-21 path with keys only (Meta or Alt+F1, typing, arrows, Return, Escape, Meta+Alt+P). Owner: no mouse; the amber ring always visible | Unit: **yes**. Session: **yes** (`session-test` S4, S8, S9) |
| T0-23 | Scaling | E-CI, E-VMW | Unit, at scale factors 1, 1.5 and 2 on a 1920×1080 offscreen screen: tiles inside the launcher and non-overlapping, minimum target size, names up to 20 characters not truncated, the taskbar fits Applications, three task buttons and Leave at 960 px. Session: `kscreen-doctor` 1.5/2/1 with AT-SPI geometry. Owner: screenshots at 100/150/200 % | Unit: **yes**. Session: informational (`session-test` S11) |
| T0-24 | Screen reader | E-CI, E-VMW | Session: AT-SPI roles and names of the taskbar and launcher; Meta+Alt+S starts Orca; Orca's debug log shows each focused tile name. Owner: audible speech through both start paths | Informational (`session-test` S10) until three consecutive green runs |
| T0-25 | Resource baseline | E-CI, E-VMW | No pass/fail yet. `STAROS-IDLE-REPORT` 240 s after ready, 60 s window: PSS of every live-user process (smaps_rollup), session CPU % of one CPU, memory in use, renderer and package versions. CI reports median, min and max of three boots, labelled "not a performance claim" | **yes** (`idle`, `idle-summary`) |
| T0-26 | Image policy | E-CI | `check-image-policy.sh` on the built root file system: no forbidden variable names; root locked; `liveuser` 1000:1000 with `/bin/bash`, not in wheel; sudoers file 0440 and valid; sshd masked; no getty autologin; `display-manager.service` is the live session unit; `default.target` is graphical; `staros.desktop` valid; shell files installed with no private Plasma import; overlay files unowned or package backup files | **yes** (`build`; the build fails on a violation) |

How the CI evidence is produced:

- `staros-session-report` (live image, root, read-only) prints its lines to
  the journal and the first serial port; `tests/iso/boot_test.py --session`
  reads them from QEMU's serial log. The same lines are available in VMware
  with `sudo journalctl -b -u staros-session-report -o cat`.
- `tests/shell/run-qml-tests.sh` runs `qmllint` (fatal for `StarOS.Shell`),
  installs the three Plasma packages with `kpackagetool6` into a scratch home,
  and runs `qmltestrunner` at `QT_SCALE_FACTOR` 1, 1.5 and 2. Each run must
  report the scale it asked for.
- `tests/session/session_test.py` (job `session-test`) boots the ISO with a
  QEMU guest agent port and drives the session with real key presses over
  QMP. Each step is checked against KWin's own view (a test-time KWin script
  reporting the window list and active window over D-Bus), the shell's
  accessibility tree over AT-SPI, and screen dumps. Helpers are copied to
  `/run/staros-test` at test time; nothing is added to the image. It prints
  `EVIDENCE <scenario> PASS|FAIL|INFO` lines and a step summary.
- The screen dump analysis (`tests/iso/screen.py`) reports the strongest
  full-width horizontal edge in the bottom quarter of the screen (the frosted
  glass taskbar's top edge, M0.3), the band height below it and the mean
  colours on either side. The glass has no fixed colour, so this replaced the
  M0.2 count of reserved taskbar and desktop colours. It is informational;
  AT-SPI geometry is the authority.

## Phase 0 tests (milestone M0.3, ADR-0009, ADR-0010)

Design contract: `docs/architecture/m03-glass-files-store-design.md`. As for
M0.2, a QEMU result is never reported as a VMware or hardware result.

| ID | Test | Env | Pass condition | CI now |
| --- | --- | --- | --- | --- |
| T0-30 | Files | E-CI, E-VMW | Unit (`ctest` in the package build), on temporary folders: the folder model lists folders first then names ignoring case, describes items, follows the hidden-files setting and the name filter, refreshes, and reports a missing folder; copy, move, rename, new folder, clipboard copy/cut/paste, Trash, restore, empty Trash and permanent delete through KIO, with bad names refused; programs and desktop entries are never started; places list only existing folders; the view's keyboard paths (Return, Delete, Shift+Delete asks first, Ctrl+C/V, F2, Escape) and accessible names with fake models; the real window shows "Files — <folder>", "Places" and "Folder contents". Session: S12. Owner: the VMware steps below | Unit: **yes** (`packages`). Session: **yes** (`session-test` S12) |
| T0-31 | Sun Store | E-CI, E-VMW | Unit: flatpak output parsers (tables, permissions, app id check); AppStream catalogue reader (plain and gzip); the store against a fake `flatpak` (exact command lines, consent, offline with and without an earlier catalogue, install, remove, update, permissions, invalid ids never reach flatpak, missing flatpak); the view with a fake store (consent page, sections, list, app page, accessible names); the real window shows the consent text and "Enable Flathub". Session: S13, and no Flatpak remote exists afterwards. Owner: enabling Flathub and installing an app with network | Unit: **yes** (`packages`). Session: **yes** (`session-test` S13) |
| T0-32 | Star OS packages in the image | E-CI | `staros-files` and `staros-sunstore` installed from the build-time repository; desktop entries valid; `flathub.flatpakrepo` shipped by `staros-sunstore`; no Flatpak remote in `/etc/flatpak/remotes.d` or `/usr/share/flatpak/remotes.d` (the flatpak package's static Flathub remote is not extracted) and none configured; no `[staros]` in the image's pacman configuration; `cow_spacesize=50%` on every generated boot entry and on the booted kernel command line (S1) | **yes** (`build` policy check, `session-test` S1) |
| T0-33 | Frosted glass theme | E-CI, E-VMW | Unit: theme contrast on the worst-case glass (text 9.43:1, focus ring 5.79:1 over the lightest wallpaper colour), the opaque fallback under the software scene graph, wallpaper offsets of taskbar and launcher glass, every icon loads; artwork licence, SVG subset and size limits (`check_shell_sources.py`). Session: the screen dump edge (informational). Owner: glass looks frosted with 3D on, opaque and readable with 3D off | Unit: **yes** (`shell-checks`, `lint`). Session: informational |
| T0-34 | Launcher catalogue | E-CI | The launcher lists Files, Konsole, Sun Store and System Settings with their Star OS icons (unit); "fil" and "sun" launch Files and Sun Store (S12, S13); Orca's debug log names the first tile "Files" (S10, informational) | **yes** |

## Manual procedure: VMware Workstation, M0.3 (T0-30..T0-34)

Use the ISO of a green CI run and record that run's link in the log. The VM
needs network access (NAT is enough) for the Sun Store steps, and at least
4 GB RAM; Flatpak apps are stored in RAM on the live medium.

1. Boot as in the M0.2 procedure. Expected: the taskbar and launcher are
   frosted glass over a dark blue-violet wallpaper with stars. With
   **Accelerate 3D graphics** off the glass is an opaque dark blue; text and
   the amber focus ring must stay readable either way (T0-33).
2. Open the launcher. Expected tiles, in this order: Files, Konsole, Sun
   Store, System Settings, each with its own icon (T0-34).
3. Files (T0-30): open it from the launcher. Check Places (Home and the
   folders that exist, Trash, Computer). In Home: Ctrl+Shift+N creates a
   folder; F2 renames it; Ctrl+C then Ctrl+V copies it; Delete moves the copy
   to the Trash; in Trash, Restore brings it back; Shift+Delete asks before
   deleting permanently (Cancel is focused); Ctrl+H shows hidden files;
   Ctrl+L, type `/etc`, Return. Open a text file with Return. Note any step
   without a visible focus ring.
4. Sun Store (T0-31): open it. Expected: "Sun Store installs apps from
   Flathub, a community app store. Star OS does not review these apps." with
   "Enable Flathub" and "Not now". Choose "Not now": Sun Store closes. Open
   it again and choose "Enable Flathub"; the app list loads (this downloads
   Flathub's catalogue, tens of MB). Search for a small app, open its page,
   read the permissions, Install, then Open, then Remove. Disconnect the
   network and press F5: expected "Can't reach Flathub. Check your network
   connection."
5. In Konsole: `flatpak remotes --user` shows `flathub` only after step 4;
   `flatpak remotes --system` shows nothing; `cat /proc/cmdline` contains
   `cow_spacesize=50%`.
6. With Orca on (Meta+Alt+S), repeat steps 3 and 4 by keyboard and note what
   is spoken for the lists, the tabs ("Store sections") and the buttons.

## Manual procedure: VMware Workstation, M0.2 (T0-20..T0-25)

Use the ISO of a green CI run and record that run's link in the log.

1. Verify the checksum as in the M0.1 procedure. Create a VM with 4 vCPU and
   4 GB RAM, UEFI without Secure Boot, no virtual disk. Run each step once with
   **Accelerate 3D graphics** on and once with it off.
2. Boot the default entry. Expected: no login prompt; the Star OS taskbar at
   the bottom (Applications, Leave) on a blue-grey desktop.
3. T0-21 (mouse): Applications → Konsole; Applications → System Settings. Both
   appear in the taskbar. Switch by clicking; click the active button to
   minimise and again to restore.
4. T0-22 (keyboard only): Meta (or Alt+F1) opens the launcher with focus in
   the search field; type, use the arrows, Return to launch, Escape to close.
   Meta+Alt+P focuses the taskbar; Left/Right and Return switch windows.
   Ctrl+Alt+Del opens the logout prompt. Note any step where the amber focus
   ring is not visible or focus is lost.
5. T0-23: in Konsole, run `kscreen-doctor -o`, then
   `kscreen-doctor output.<name>.scale.1.5` (and `.2`, then `.1`). Screenshot
   the taskbar and the open launcher at each scale. Note clipping, blur or
   overlap.
6. T0-24: run `spd-say test` (must be audible), then Meta+Alt+S. Open the
   launcher and arrow through the entries and the taskbar; record what is
   spoken. Repeat once from the "speech" boot entry.
7. T0-25: three cold boots. Do not touch the VM for 6 minutes after the
   taskbar appears, then open Konsole and run
   `sudo journalctl -b -u staros-session-report -o cat`. Paste the
   `STAROS-SESSION-CHECK`, `STAROS-IDLE-REPORT` and `STAROS-SESSION-STABLE`
   lines into an issue and summarise them in the log below.
8. Stays up: leave the session running for 30 minutes and note anything that
   restarts or degrades. Log out from Leave and check that the session comes
   back after about 5 seconds.

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
| 2026-10-19 | T0-10 | A CI-built M0.1 ISO (run not recorded) | VMware Workstation on the owner's PC (version and firmware settings not recorded) | **Pass** — owner report: "Everything works fine" | — |
