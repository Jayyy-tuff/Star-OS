# Star OS

Star OS is a planned free and open-source Linux operating system for x86-64 PCs,
based on Arch Linux, with an original Qt Quick / QML desktop focused on gaming,
everyday computing, and recoverability.

## Current status: Phase 0 (feasibility and architecture)

What has been tested:

- **Builds in CI:** a console-only live ISO, built by GitHub Actions from this
  repository with packages pinned to the Arch Linux Archive snapshot of
  2026-10-15.
- **Boots in QEMU (CI):** that ISO boots to its live environment in QEMU with
  UEFI (OVMF) and with BIOS (SeaBIOS).
- **Boots in VMware Workstation:** reported working by the project owner on
  2026-10-19 (manual test T0-10).
- **Star OS shell prototype in QEMU (CI, milestone M0.2):** the live ISO
  starts a Wayland session on KWin with the Star OS taskbar and launcher;
  keyboard-only launching and window switching were checked with real key
  presses against KWin's own window list and the accessibility tree (CI run 12,
  2026-10-21).

- **Frosted glass, Files and Sun Store in QEMU (CI, milestone M0.3):** both
  apps are built and unit-tested as packages, open from the launcher, and
  expose their accessible lists and buttons; Sun Store asks before adding
  Flathub and adds nothing on its own (CI run 18, 2026-10-22).
- **Apps, Star Lens and Star Storage in QEMU (CI, milestone M0.4):** Firefox,
  VLC, Okular, Gwenview, Ark, KWrite and KCalc are in the image and the
  launcher; quick answers, desktop sticky notes and the System status meter
  work in the session; Star Lens takes its screenshot through KWin's grant;
  Star Storage sets up a 10 GiB virtual disk by keyboard, and what was saved
  on it was still there two restarts later (CI run 24, 2026-10-23).
- **Deep Space desktop in QEMU (CI, milestone M0.5):** a floating glass
  taskbar and start menu; apps installed with Flatpak appear in Applications
  at once; quick settings change PipeWire's volume; notifications show as
  toasts and in the clock's notification centre; clipboard history (Meta+V)
  keeps copies after the app that made them closes; desktop widgets; Game
  Center; a Welcome tour; and the Star OS lock and logout screens (CI run
  49, 2026-10-26).

What has **not** been tested: any real hardware, any installation (there is no
installer yet), the graphical session in VMware, installing an app from
Flathub (CI places an installed app's files instead), Google Lens and web search (the CI virtual machine has no internet
access), and Star Storage on a real USB stick or disk. This README claims a capability only once a recorded test
shows it.
Prototype ISOs are unsigned test artifacts.

What exists today:

| Area | Document | State |
| --- | --- | --- |
| Build environment inspection | [docs/development/environment-report-2026-10-19.md](docs/development/environment-report-2026-10-19.md) | Done |
| Phase 0 plan and milestones | [docs/development/phase-0-plan.md](docs/development/phase-0-plan.md) | M0.1 complete; M0.2 (shell prototype), M0.3 (glass, Files, Sun Store), M0.4 (apps, Star Lens, Star Storage) and M0.5 (Deep Space desktop) green in CI, VMware runs pending |
| Building and boot-testing the ISO | [docs/development/building.md](docs/development/building.md) | Draft |
| Architecture decision records | [docs/decisions/](docs/decisions/README.md) | Mostly accepted; ADR-0006 deferred to Phase 2 |
| Test plan | [docs/development/test-plan.md](docs/development/test-plan.md) | Draft |
| Initial threat model | [docs/security/threat-model.md](docs/security/threat-model.md) | Draft |
| Contribution policy | [CONTRIBUTING.md](CONTRIBUTING.md) | Draft |
| Security reporting | [SECURITY.md](SECURITY.md) | Draft |

## Licensing

Original Star OS code is licensed under GPL-3.0-or-later, and documentation
and original artwork under CC-BY-SA-4.0. See [LICENSES.md](LICENSES.md) and
[ADR-0007](docs/decisions/0007-licensing.md). Third-party software in Star OS
images keeps its own licenses.

## Name

"Star OS" is a working name. No trademark or software-name clearance has been
performed.
