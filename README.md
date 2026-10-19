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

What has **not** been tested: VMware Workstation, any real hardware, any
installation (there is no installer yet), and any graphical session (there is
none yet). This README claims a capability only once a recorded test shows it.
Prototype ISOs are unsigned test artifacts.

What exists today:

| Area | Document | State |
| --- | --- | --- |
| Build environment inspection | [docs/development/environment-report-2026-10-19.md](docs/development/environment-report-2026-10-19.md) | Done |
| Phase 0 plan and first milestone | [docs/development/phase-0-plan.md](docs/development/phase-0-plan.md) | M0.1: CI build and QEMU boot pass; VMware test pending |
| Building and boot-testing the ISO | [docs/development/building.md](docs/development/building.md) | Draft |
| Architecture decision records | [docs/decisions/](docs/decisions/README.md) | Mostly accepted; ADR-0006 deferred to Phase 2 |
| Test plan | [docs/development/test-plan.md](docs/development/test-plan.md) | Draft |
| Initial threat model | [docs/security/threat-model.md](docs/security/threat-model.md) | Draft |
| Moon Browser integration checklist | [integrations/moon-browser/README.md](integrations/moon-browser/README.md) | Blocked: source not yet supplied |
| Contribution policy | [CONTRIBUTING.md](CONTRIBUTING.md) | Draft |
| Security reporting | [SECURITY.md](SECURITY.md) | Draft |

## Licensing

Original Star OS code is licensed under GPL-3.0-or-later, and documentation
under CC-BY-SA-4.0. See [LICENSES.md](LICENSES.md) and
[ADR-0007](docs/decisions/0007-licensing.md). Third-party software in Star OS
images keeps its own licenses.

## Name

"Star OS" is a working name. No trademark or software-name clearance has been
performed.
