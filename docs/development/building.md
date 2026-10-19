# Building and testing the live ISO (milestone M0.1)

## What gets built

`scripts/build-iso.sh` assembles an archiso profile and runs `mkarchiso`.
The profile is made from:

1. the `releng` profile of the archiso version in
   `distro/archiso/ARCHISO_VERSION`;
2. the Star OS overlay in `distro/archiso/staros/` (files, plus `profiledef.sh`
   settings appended so they override releng's);
3. repositories pinned to the Arch Linux Archive snapshot in
   `distro/baseline/ARCH_SNAPSHOT_DATE`, and Star OS boot menu titles.

It writes these files to `out/`:

| File | Content |
| --- | --- |
| `staros-<date>-x86_64.iso` | The live ISO (unsigned test artifact) |
| `SHA256SUMS` | Checksum of the ISO |
| `packages.x86_64.txt` | Every package in the live system, with versions |
| `build-info.txt` | Commit, baseline date, archiso version, boot modes, timestamps |
| `boot-entries.txt` | Boot menu entries after renaming |
| `profile.tar.gz` | The assembled profile, for review |

## In CI (the system of record)

`.github/workflows/iso.yml` runs on every push and pull request:

1. **lint** — shellcheck and the boot-harness unit tests.
2. **build** — in an `archlinux` container, `scripts/ci/prepare-arch-build-host.sh`
   pins the container to the baseline snapshot and installs archiso, then
   `scripts/build-iso.sh` builds. The ISO and build records are uploaded as
   artifacts.
3. **package-manifest** — compares `packages.x86_64.txt` with
   `distro/baseline/packages.x86_64.txt`.
4. **boot-test** (UEFI and BIOS) — boots the ISO in QEMU with KVM and waits for
   the live system's boot report. Logs are uploaded even when it fails.

Download the ISO from the run's **Artifacts** section (`staros-iso`).

## Building locally

Requirements: an x86-64 Linux machine with Docker or Podman, about 15 GB free
disk, and network access to `archive.archlinux.org`. **This path has not been
tested outside GitHub Actions yet.**

```sh
docker run --rm -it --privileged -v "$PWD":/src -w /src archlinux:latest bash
# inside the container:
STAROS_DISPOSABLE_HOST=1 scripts/ci/prepare-arch-build-host.sh
scripts/build-iso.sh
```

Never run `prepare-arch-build-host.sh` on a real Arch installation: it rewrites
pacman's configuration and downgrades every package to the baseline snapshot.
That is why it requires `STAROS_DISPOSABLE_HOST=1`.

`build/` holds several GB of scratch files and can be deleted after a build.

## Boot-testing locally

On a Linux host with QEMU, OVMF (for UEFI), and access to `/dev/kvm`:

```sh
python3 tests/iso/boot_test.py --iso out/staros-*.iso --firmware uefi
python3 tests/iso/boot_test.py --iso out/staros-*.iso --firmware bios
```

The test attaches only the ISO, as a read-only CD-ROM, and gives the guest
network access that cannot reach the outside. It cannot modify any disk.

## Changing the package baseline

1. Edit `distro/baseline/ARCH_SNAPSHOT_DATE`.
2. Push. The **package-manifest** job fails and prints the new package list.
3. Review the differences, then commit the new list as
   `distro/baseline/packages.x86_64.txt` in the same pull request.
4. If archiso changed version, update `distro/archiso/ARCHISO_VERSION` after
   reviewing the new releng profile in the uploaded `profile.tar.gz`.
