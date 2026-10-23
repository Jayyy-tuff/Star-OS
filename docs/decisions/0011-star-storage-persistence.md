# ADR-0011: Star Storage keeps the live system's changes on a disk the person erases for it

- Status: Accepted (the option); the live polkit rule awaits owner review
- Date: 2026-10-23
- Deciders: project owner

## Context

The owner asked for "a disk storage to install things & make it visible in
the os". The live medium keeps every change in a RAM disk (ADR-0010 raised it
to half the memory), so files, settings and Flatpak apps from Sun Store are
gone at shutdown. archiso already supports keeping its copy-on-write layer
on a block device (`cow_label=` / `cow_device=`, `cow_directory=`;
mkinitcpio-archiso 73). Making that usable means erasing a disk, which is
destructive and needs root.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Persistent live disk: a tool erases a chosen disk, a boot entry uses it** | Everything is kept (files, settings, Flatpak apps) with archiso's own mechanism; works from USB sticks and internal disks | Destroys the chosen disk's data; persistence is tied to one ISO build; the entry fails if the disk is missing |
| Mount a data disk at ~/Storage only | Not destructive if the disk has a file system | Settings and apps are not kept; Flatpak apps would need a second installation |
| Install Star OS (Phase 2 installer) | A normal system | Not in Phase 0; much larger change |

The owner chose the persistent live disk on 2026-10-23 ("Persistent live disk
(Recommended)").

## Decision

- **App** `staros-storage` ("Star Storage"): shows where this session keeps
  its changes (StarOS.System's `SystemStatus`), any disk that already has Star
  Storage, and the disks with their model, size and connection. Disks that
  cannot be used are listed with the reason. Erasing needs the disk's name
  typed exactly; the warning lists the partitions that will be lost and says
  the current session is not copied.
- **Helper** `/usr/lib/staros/staros-storage-helper` (Python, standard
  library only). `list` runs as the person. `format NAME CONFIRM` and `boot
  next|always|never` run as root through `pkexec`. The helper reads `lsblk`
  itself and refuses: names other than `sd*`, `vd*`, `xvd*`, `nvme*n*`,
  `mmcblk*`; a confirmation that is not the name; the Star OS medium (an
  `iso9660` file system or the ISO's UUID from `archisosearchuuid=`); disks
  with a mounted partition (this includes Star Storage in use); read-only
  disks; disks under 8 GiB; and a second disk with `STAROS_DATA`. It then
  runs, from `/usr/bin` and without a shell: `wipefs --all` on each partition
  and the disk, `sfdisk` (GPT, one Linux partition named `STAROS_DATA`),
  `udevadm settle`, `mkfs.ext4 -L STAROS_DATA`, and `blkid -p` to check the
  label. Progress is printed as JSON lines.
- **Polkit** action `org.staros.storage.manage`, `allow_active =
  auth_admin_keep`, with `org.freedesktop.policykit.exec.path` naming the
  helper, so pkexec runs nothing else under it. On the live medium only,
  `/etc/polkit-1/rules.d/49-staros-live-storage.rules` returns YES for that
  action for `liveuser` in an active local session. `liveuser` already has
  passwordless sudo on the live medium (ADR-0008), so the rule adds no new
  power; it avoids a password prompt Star OS has no answer for (root is
  locked). The Phase 2 installer must not copy the rule.
- **Boot entries** added by `scripts/build-iso.sh`: systemd-boot
  `01-staros-storage-linux.conf` and syslinux label `starstorage`, "Star OS
  live (prototype) with Star Storage", with `cow_label=STAROS_DATA
  cow_directory=persistent_%ARCHISO_UUID%/%ARCH%`. releng's entry stays the
  default; the build checks both entries and that no placeholder is left.
  GRUB is not one of the ISO's boot modes (releng v91: `bios.syslinux`,
  `uefi.systemd-boot`), so it gets no entry.
- **Choosing the start** (UEFI with Star OS's own systemd-boot only):
  `bootctl set-oneshot` (Restart into Star Storage), `set-default`
  (Always start with Star Storage) and `set-default ""` (stop). With BIOS the
  app tells the person which menu entry to choose.
- **Visible in the OS**: the taskbar's System status (storage and memory
  bars, "Live · 3.2 GB free"; its description says "Star Storage: …" or "Live
  session: changes are lost at shutdown.") opens Star Storage.

## Consequences and trade-offs

- Erasing destroys data. The typed name, the partition list, the refusals
  and the helper's own checks reduce mistakes; they cannot stop a person from
  erasing the wrong usable disk on purpose.
- Persistence belongs to one ISO build (the folder carries the ISO's UUID):
  a new ISO starts empty and the old folder stays on the disk until the disk
  is erased again. Carrying changes across builds would mix system files of
  different versions.
- If the disk is missing, the Star Storage entry waits 30 s and opens an
  emergency shell (archiso's behaviour); that is why it is never the default
  unless the person chose "Always".
- Everything in the overlay is kept, including caches and logs in `/var`;
  the ext4 file system is not encrypted. Anyone with the disk can read it.
- Polkit decides from the caller's session. Apps started by Plasma run in
  systemd scopes; polkit maps them to the user's active display session.
  The CI storage test exercises exactly that path through the app.
- CI tests the helper's checks and commands without running them, the app
  with test doubles, and the whole flow in QEMU on a 10 GiB scratch image
  over three boots. Real USB sticks and internal disks are owner tests.

## Revisit if

- An encrypted Star Storage is wanted (LUKS, passphrase at boot).
- Persistence should survive ISO updates.
- Star OS is installed (Phase 2): the live rule and boot entries do not apply.

## Approval

- Option chosen in the AI agent session on 2026-10-23: "Persistent live disk
  (Recommended)" ("Star Storage tool formats a chosen disk with model/size
  shown, never the boot medium, typed disk-name confirmation; new boot entry
  keeps everything; shown in Files and taskbar meter").
- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-23, for the option.
- Pending: the owner's review of the live polkit rule (no password for
  `liveuser`, matching its sudo rule), requested in the M0.4 report.
