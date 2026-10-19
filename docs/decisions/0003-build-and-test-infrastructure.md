# ADR-0003: Build and test infrastructure

- Status: Proposed
- Date: 2026-10-19
- Deciders: pending owner approval

## Context

The owner's primary workstation may run Windows, with VMware Workstation as the
first-priority VM environment. The AI agent's cloud container is Ubuntu, has no
KVM, and cannot reach Arch package sources (see the
[environment report](../development/environment-report-2026-10-19.md)). We need
builds that anyone on the team can repeat and boot tests that run without a
person watching.

## Options considered

1. **GitHub Actions**: build in an `archlinux` container on a GitHub-hosted
   Linux runner (privileged, because archiso needs root and bind mounts), then
   boot the ISO with QEMU + OVMF on a runner with KVM enabled. GitHub documents
   enabling KVM on hosted Linux runners with a udev rule. Free for public
   repositories, within usage limits.
2. **Local Arch Linux VM in VMware Workstation** on the owner's PC — good for
   interactive development and the real VMware test, but not automatic.
3. **Self-hosted runner** — more control and capacity, but someone must operate
   and secure it.
4. **This cloud session** — would need its network policy widened to Arch hosts,
   and still has no KVM, so boot tests would be slow software emulation.

## Decision (proposed)

- **Automated:** option 1 is the system of record. Every pushed change runs
  lint → ISO build → QEMU boot tests (UEFI, and BIOS while BIOS is kept). The
  ISO, its SHA-256 checksum, the package manifest, and boot logs are uploaded as
  workflow artifacts.
- **Manual:** the owner runs the VMware Workstation procedure in the
  [test plan](../development/test-plan.md) and records results there. CI QEMU
  results are never presented as VMware results.
- **Local:** option 2 is recommended for contributors who want to build
  locally; the build script will be the same one CI runs.
- CI must not hold release-signing keys in Phase 0. Workflows triggered by pull
  requests from forks get no secrets.

## Consequences and trade-offs

- The agent cannot see a build result until it is pushed and CI runs. Agent
  reports will cite CI run links, not local claims.
- GitHub-hosted runners have limited disk and time. A full desktop ISO (Phase 1
  and later) may need cleanup steps or a larger runner.
- Bugs that appear only on real hardware or only under VMware will not be caught
  by CI. That is why the manual procedure exists.

## Revisit if

- CI disk or time limits block the Phase 1 graphical ISO.
- The project needs a signing service (Phase 4 and later), which should not run
  on shared hosted runners.

## Approval

- Approved by: pending
