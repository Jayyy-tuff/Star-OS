# Star Storage

Keeps what you do in the Star OS live session (milestone M0.4,
`docs/architecture/m04-apps-lens-storage-design.md` section 6, ADR-0011).
Without it the live medium keeps changes in memory, and they are gone when
the computer is turned off. With it, your files, settings and the apps you
install from Sun Store are kept on a disk you choose.

1. Open Star Storage (launcher, or the taskbar's System status).
2. Choose a disk. Star Storage offers only disks that are at least 8 GiB, not
   read-only, not in use and not the Star OS medium; for the others it says
   why not.
3. Type the disk's name (for example `sdb`) and choose "Erase and set up".
   Everything on that disk is erased. The current session is not copied.
4. On UEFI computers, "Restart into Star Storage" starts it once; inside it,
   "Always start with Star Storage" makes it the default. Elsewhere choose
   "Star OS live (prototype) with Star Storage" in the boot menu.

## How it works

- The disk gets one GPT partition with an ext4 file system labelled
  `STAROS_DATA`. The boot entry "with Star Storage" adds
  `cow_label=STAROS_DATA cow_directory=persistent_<ISO build>/x86_64` to the
  kernel command line, so archiso keeps the copy-on-write layer on that disk,
  in a folder of this ISO build. A newer ISO starts with an empty folder; the
  old one stays on the disk.
- The entry is never the default by itself: when the disk is missing, archiso
  waits 30 seconds and then opens an emergency shell.
- The app runs `staros-storage-helper list` as you to show the disks. Erasing
  and choosing the next start run the same helper as root through `pkexec`
  under the polkit action `org.staros.storage.manage` (an administrator must
  agree; on the live medium a rule lets `liveuser`, who already has sudo
  without a password, do it without one). The helper reads the disks itself
  and refuses anything the app would not offer, a typed name that does not
  match, and a second Star Storage disk. It is Python with the standard
  library only and runs `wipefs`, `sfdisk`, `mkfs.ext4`, `udevadm`, `blkid`
  and `bootctl` from `/usr/bin`, without a shell.

## Build and test

Needs Qt 6.12, ECM, Python 3 and, at run time, StarOS.System
(`staros-system`).

```sh
cmake -B build -S apps/storage -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

The helper's tests (`tests/test_helper.py`) never run a command: they give it
`lsblk` output and record the commands it would run. The backend's tests use
shell scripts in place of the helper and pkexec, and the view's tests use test
doubles. In CI the `lint` job runs the helper's tests, the `packages` job
builds `distro/packages/staros-storage/PKGBUILD` with all of them, and the
`storage-test` job (`tests/storage/storage_test.py`) sets up Star Storage on a
10 GiB scratch image in QEMU, restarts into it and checks that a file is kept.
