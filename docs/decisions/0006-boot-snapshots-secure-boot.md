# ADR-0006: Bootloader, Btrfs snapshots, and Secure Boot

- Status: **Deferred to Phase 2** (options and prototype plan recorded now)
- Date: 2026-10-19
- Deciders: pending owner approval of the deferral

## Context

The installed system needs a boot loader that works with UEFI, dual boot,
full-disk encryption, Btrfs snapshots, recovery, and possibly Secure Boot. These
interact, so choosing one too early can make another impossible. The live ISO's
boot setup is separate and comes from archiso (ADR-0001).

## Hard constraints discovered so far

1. **Kernel versus snapshot mismatch.** If kernels and initramfs images live on
   the EFI system partition (FAT, never snapshotted) and the root filesystem is
   rolled back, the running kernel may not match the kernel modules inside the
   snapshot. Any snapshot-boot design must solve this, either by keeping kernels
   inside the snapshotted filesystem or by keeping per-snapshot copies of the
   kernels.
2. **Encryption versus boot loader.** Keeping kernels inside an encrypted Btrfs
   root means the boot loader must unlock LUKS. Upstream GRUB has historically
   supported only part of LUKS2 (not Argon2 key derivation) *(verify against the
   baseline GRUB package)*. That means weaker key derivation or a second
   passphrase prompt.
3. **ESP capacity.** Designs that copy kernels per snapshot onto the ESP need a
   much larger ESP. Users of one such tool report snapshot entries silently
   stopping when the ESP fills up. Retention limits must be enforced and
   visible.
4. **Secure Boot.** Arch Linux's official media does not boot with Secure Boot
   enabled. Booting **out of the box** with Secure Boot on requires a shim
   signed by Microsoft, obtained through the public shim review process. That
   is a long-term organizational commitment. The alternative is users enrolling
   their own keys (for example, with `sbctl`), which is an advanced workflow
   and risky for beginners if done wrong.

## Candidates to prototype

| Candidate | Snapshot boot from menu | LUKS interaction | Secure Boot path | Notes |
| --- | --- | --- | --- | --- |
| GRUB + grub-btrfs + Snapper | Yes (generated entries) | Constraint 2 if /boot is encrypted | shim + signed GRUB; complex | BIOS + UEFI; widely used by Arch derivatives |
| Limine + limine-snapper-sync + Snapper | Yes (kernels copied per snapshot) | Kernels on unencrypted ESP | Signing with own keys | Constraint 3 reported in practice |
| systemd-boot + UKIs + Snapper | No direct snapshot boot; rollback from a Star OS recovery entry | Kernels on unencrypted ESP | Signed UKIs (own keys or shim) | UEFI only; simplest chain |

## Proposed Btrfs layout to prototype

| Subvolume | Mount | Snapshotted with root | Reason |
| --- | --- | --- | --- |
| `@` | `/` | — | System |
| `@home` | `/home` | No | User data is not rolled back with the system |
| `@log` | `/var/log` | No | Keep logs that explain a failure |
| `@pkg` | `/var/cache/pacman/pkg` | No | Avoid snapshot bloat |
| `@snapshots` | `/.snapshots` | No | Snapper |

Mount options to benchmark: `compress=zstd` (level to be measured), `noatime`.
Snapshots use Snapper with pacman pre/post hooks (`snap-pac` or equivalent) and
number and space limits. **Snapshots are not backups**: they live on the same
disk. Personal-file backup is a separate feature (Backup & Recovery app).

## Rollback test plan (Phase 2 exit criteria)

On disposable QEMU disks, for each candidate:

1. Install with and without LUKS2.
2. Take a pre-update snapshot, install a kernel update, roll back, and boot.
   Kernel and modules must match.
3. Simulate a broken update (remove a library a boot service needs), roll back,
   and boot.
4. Kill pacman mid-transaction, then recover.
5. Fill the disk or ESP to the configured limits and check that snapshot
   creation fails **loudly** and the update is blocked by policy.
6. Dual-boot with a disposable Windows-layout disk: the Windows boot entry
   still works after Star OS installs and updates.
7. Every step works with keyboard-only input.

## Decision (proposed)

Defer the choice to Phase 2. Run the three candidates through the plan above
and decide from the results. For the **first release**, document that Secure
Boot must be disabled unless a supported signing path has been implemented
**and tested**. Treat Microsoft-signed shim as a long-term goal that needs its
own approval.

## Approval

- Deferral approved by: pending
