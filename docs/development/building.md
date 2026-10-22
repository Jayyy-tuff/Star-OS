# Building and testing the live ISO (milestones M0.1 to M0.3)

## What gets built

`scripts/build-iso.sh` assembles an archiso profile and runs `mkarchiso`.
The profile is made from:

1. the `releng` profile of the archiso version in
   `distro/archiso/ARCHISO_VERSION`, minus the paths listed in
   `distro/archiso/staros/releng-remove.txt` (root autologin and the sshd
   link; the build stops if releng no longer has one of them);
2. the Star OS overlay in `distro/archiso/staros/` (files, plus `profiledef.sh`
   settings appended so they override releng's), and the packages in
   `packages.x86_64.append` added to releng's list;
3. the Star OS shell from `shell/`: the `StarOS.Shell` QML module in
   `/usr/lib/qt6/qml/StarOS` and the three Plasma packages in
   `/usr/share/plasma/` (licence sidecars stay in git);
4. repositories pinned to the Arch Linux Archive snapshot in
   `distro/baseline/ARCH_SNAPSHOT_DATE`, and Star OS boot menu titles;
5. the Star OS packages (Files and Sun Store, ADR-0009) from the local
   repository `[staros]` that `scripts/build-packages.sh` writes, given as
   `STAROS_LOCAL_REPO=<dir>`. It is added to the profile's `pacman.conf`
   only; the image's own `/etc/pacman.conf` does not list it. Without it the
   build stops, because `packages.x86_64.append` lists `staros-*` packages;
6. the boot parameter `cow_spacesize=50%` on every boot entry (through
   `kernel_params_x86_64` in `profiledef.append.sh`), so per-user Flatpak apps
   fit in the live medium's RAM-backed writable layer. The build checks every
   generated boot entry for it.

After `mkarchiso`, `scripts/ci/check-image-policy.sh` checks the built root
file system (see test T0-26 in `test-plan.md`) and the build fails on any
violation.

It writes these files to `out/`:

| File | Content |
| --- | --- |
| `staros-<date>-x86_64.iso` | The live ISO (unsigned test artifact) |
| `SHA256SUMS` | Checksum of the ISO |
| `packages.x86_64.txt` | Every package in the live system, with versions |
| `build-info.txt` | Commit, ISO size, baseline date, archiso version, boot modes, shell tree hash, Star OS package versions, kernel parameters, timestamps |
| `image-policy.txt` | The `POLICY` lines of the image policy check |
| `boot-entries.txt` | Boot menu entries after renaming |
| `profile.tar.gz` | The assembled profile, for review |

## In CI (the system of record)

`.github/workflows/iso.yml` runs on every push and pull request:

1. **lint** — shellcheck, the harness unit tests (`tests/iso`), the
   forbidden-variable grep (`scripts/ci/check-forbidden-env.sh`), the shell
   source checks (`tests/shell/check_shell_sources.py`) and
   `desktop-file-validate` of the session entry.
2. **shell-checks** — in a pinned `archlinux` container with Qt and Plasma
   libraries: `qmllint`, `kpackagetool6` and the QML unit tests at scale
   factors 1, 1.5 and 2 (`tests/shell/run-qml-tests.sh`). JUnit XML is uploaded.
3. **packages** — in a pinned `archlinux` container with `base-devel`,
   `scripts/build-packages.sh` builds `staros-files` and `staros-sunstore`
   from `distro/packages/`; `makepkg` runs their C++ and QML tests (`ctest`,
   offscreen). The repository (`staros-packages`) and the logs are uploaded.
4. **build** — in an `archlinux` container, `scripts/ci/prepare-arch-build-host.sh`
   pins the container to the baseline snapshot and installs archiso, then
   `scripts/build-iso.sh` builds with the downloaded package repository and
   runs the image policy check. The ISO and build records are uploaded as
   artifacts.
5. **package-manifest** — compares `packages.x86_64.txt` with
   `distro/baseline/packages.x86_64.txt`.
6. **boot-test** (UEFI and BIOS) — boots the ISO in QEMU with KVM (4 vCPU,
   4 GiB, 1920×1080 standard VGA), waits for the boot report and the session
   report, checks the session facts and uploads a PNG screen dump. Logs are
   uploaded even when it fails.
7. **session-test** — drives the session with real key presses
   (`tests/session/session_test.py`): launcher, two KDE apps, window
   switching, then Files and Sun Store (scenarios S12 and S13).
8. **idle** (three UEFI boots) and **idle-summary** — wait for the idle report
   and the stability verdict, then print median, minimum and maximum. The
   figures describe CI virtual machines and are not performance claims.

Download the ISO from the run's **Artifacts** section (`staros-iso`).

## Building locally

Requirements: an x86-64 Linux machine with Docker or Podman, about 15 GB free
disk, and network access to `archive.archlinux.org`. **This path has not been
tested outside GitHub Actions yet.**

```sh
docker run --rm -it --privileged -v "$PWD":/src -w /src archlinux:latest bash
# inside the container:
export STAROS_DISPOSABLE_HOST=1
scripts/ci/prepare-arch-build-host.sh base-devel sudo desktop-file-utils
scripts/build-packages.sh staros-repo   # builds and tests Files and Sun Store
STAROS_LOCAL_REPO="$PWD/staros-repo" scripts/build-iso.sh
```

`build-packages.sh` adds a system user `builder` to the container (makepkg
does not run as root) and installs the packages' build dependencies, so it
also requires `STAROS_DISPOSABLE_HOST=1`. Sun Store's PKGBUILD downloads
Flathub's `flathub.flatpakrepo` and checks its pinned sha256; if Flathub
changes that file, the build stops and prints the new checksum and content
for review.

Never run `prepare-arch-build-host.sh` on a real Arch installation: it rewrites
pacman's configuration and downgrades every package to the baseline snapshot.
That is why it requires `STAROS_DISPOSABLE_HOST=1`.

`build/` holds several GB of scratch files and can be deleted after a build.

## Boot-testing locally

On a Linux host with QEMU, OVMF (for UEFI), and access to `/dev/kvm`:

```sh
python3 tests/iso/boot_test.py --iso out/staros-*.iso --firmware uefi
python3 tests/iso/boot_test.py --iso out/staros-*.iso --firmware bios
# M0.2 session checks, as in CI (add --wait-idle for the idle report):
python3 tests/iso/boot_test.py --iso out/staros-*.iso --firmware uefi \
    --profile graphical --session
```

The test attaches only the ISO, as a read-only CD-ROM, and gives the guest
network access that cannot reach the outside. It cannot modify any disk.

## Running the shell unit tests locally

On Arch Linux with `qt6-declarative`, `kpackage`, `libplasma` and a font
installed (no Plasma session is needed):

```sh
python3 tests/shell/check_shell_sources.py
tests/shell/run-qml-tests.sh
```

## Building one Star OS application

Each application can also be built with CMake directly; see
`apps/files/README.md` and `apps/sunstore/README.md`. The tests need no
display, network or real `flatpak`.

## Changing the package baseline

The same steps apply when `packages.x86_64.append` changes.

1. Edit `distro/baseline/ARCH_SNAPSHOT_DATE` (or the package list).
2. Push. The **package-manifest** job fails and prints the new package list.
3. Review the differences, then commit the new list as
   `distro/baseline/packages.x86_64.txt` in the same pull request.
4. If archiso changed version, update `distro/archiso/ARCHISO_VERSION` after
   reviewing the new releng profile in the uploaded `profile.tar.gz`.
