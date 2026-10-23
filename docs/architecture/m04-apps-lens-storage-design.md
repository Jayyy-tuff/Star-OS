# M0.4 apps, Star Lens and Star Storage — design contract

Status: accepted by the owner's choices of 2026-10-23 (see "Decisions"). This
contract fixes the names, files and behaviour that the code, the packages and
the tests rely on. Results are recorded in `docs/development/phase-0-plan.md`
only from CI runs and the owner's VMware run.

## Decisions (owner, 2026-10-23)

| Question | Choice |
| --- | --- |
| Third-party apps | Preinstall a core set from the pinned Arch snapshot: Firefox, VLC, Okular, Gwenview, Ark, KWrite, KCalc. Sun Store adds a "Star picks" list of Flathub apps. Moon Browser stays reserved; Firefox is the browser until the owner adds Moon. |
| Lens-like feature | "Star Lens": text recognition and QR/barcode reading run offline; an extra action sends the selected image to Google Lens, with a warning every time. |
| Storage | "Star Storage": a persistent live disk. A tool erases a disk the person picks (typed confirmation, never the boot medium) and a boot entry keeps every change on it. Visible in Files, the taskbar and the tool. |
| Other features | Quick answers in the launcher, desktop sticky notes, a storage and system meter in the taskbar. |

## 1. Preinstalled applications

- `packages.x86_64.append` adds `firefox vlc okular gwenview ark kwrite kcalc`
  and, for Star Lens, `tesseract tesseract-data-eng`. Package names are
  checked by the build; the package manifest records the closure.
- The launcher catalogue (`AppCatalogue.qml`) lists, by desktop id:
  `org.staros.files`, `org.staros.sunstore`, `org.staros.lens`,
  `org.staros.storage`, `org.kde.konsole`, `systemsettings`, `firefox`,
  `vlc`, `org.kde.okular`, `org.kde.gwenview`, `org.kde.ark`,
  `org.kde.kwrite`, `org.kde.kcalc` (each with `.desktop`). A desktop id the
  image lacks is simply not shown. The image policy check fails if one of them
  is missing, so a renamed desktop file is noticed.
- Icons: Star OS artwork where it exists (Files, Sun Store, Star Lens, Star
  Storage, terminal, settings, Moon Browser), otherwise the app's own theme
  icon. `AppIcon` gains `fallback` (a Component) and `iconData`; the Plasma
  adapters pass a `Kirigami.Icon` component and libtaskmanager's `decoration`
  role. Without a fallback (unit tests) the monogram is shown. Third-party
  logos are never redrawn.

## 2. StarOS.Shell additions (Plasma-free, unit-tested)

- `quickanswers.js` (`.pragma library`): `evaluate(text)` returns
  `{kind, value, text}` or `null`. A tokenizer and recursive-descent parser
  (never `eval`) for numbers, `+ - * / ^ ( )`, unary minus, `%` as a
  percentage (`15% of 80`, `80 + 15%`, `80 - 15%`), and unit conversions
  `<number> <unit> (in|to) <unit>` for length, mass, temperature, volume,
  speed, data size and time. Results keep at most 10 significant digits.
  Division by zero and unknown units give `null`.
- `Launcher`: when the search text is a quick answer, an answer card above the
  grid shows `= <answer>` (accessible name "Answer: <answer>", also the search
  field's description); Return copies the answer to the clipboard and closes
  the launcher (`answerCopied(text)` signal). Text starting with `note:`
  shows "New sticky note: <text>"; Return emits `noteRequested(text)` and
  closes. Otherwise Return launches the first app as before. Down still moves
  to the grid.
- `NotesBoard` and `StickyNote`: notes on the desktop from a model with the
  roles `noteId, noteText, posX, posY` and the functions `addNote(text)`,
  `updateNote(id, text)`, `moveNote(id, x, y)`, `removeNote(id)` (not `add`,
  `move` or `remove`, which a `ListModel` already has). Each note is glass,
  keyboard-editable (Tab between notes, Delete button "Delete note"),
  accessible name "Sticky note", description the text. A "New note" button
  (top right) calls `addNote("")`.
- `SystemMeter`: a taskbar button named "System status" with two small bars
  (storage and memory in use) and the free storage ("Live · 3.2 GB free" in
  the live session). Its description reads e.g. "Star Storage: 9.8 GB free of
  16 GB. Memory: 1.2 GB of 3.9 GB in use. Battery: 80 %." or, live, "Live
  session: changes are lost at shutdown. …". Activating it opens Star Storage,
  which has the details and "Set up Star Storage". It takes a `status` object
  (fakes in tests).

## 3. StarOS.System (C++ QML module, package `staros-system`)

Installed to `/usr/lib/qt6/qml/StarOS/System` (the image policy and shell hash
now cover `StarOS/Shell` only).

- `SystemStatus` (QML_ELEMENT): `storageMode` ("star-storage", "live" or
  "installed"), `storageTotal`, `storageFree` (bytes), `storageDevice`,
  `memoryTotal`, `memoryAvailable` (bytes, `/proc/meminfo`),
  `batteryPresent`, `batteryPercent`, `charging` (`/sys/class/power_supply`);
  refreshes every 5 s and on `refresh()`. Star Storage mode: the kernel
  command line has `cow_label=STAROS_DATA` and `/run/archiso/cowspace` is not
  tmpfs. Live mode: `/run/archiso/cowspace` is tmpfs. Paths are constructor
  parameters for tests.
- `NotesStore` (QML_SINGLETON): a list model of notes saved as JSON in
  `$XDG_DATA_HOME/staros/notes.json` (atomic save with `QSaveFile`, reloaded
  when another process changes the file). `addNote(text)` returns the id.
  The plugin library is `libstaros_system.so` (KDECMakeSettings drops the
  prefix of MODULE libraries, so the build sets it).
- `StorageSetup`: none here; see section 6.

## 4. Files and Sun Store improvements

- Files: sort by name, size or modified time (toolbar button "Sort: Name",
  Ctrl+1/2/3); folders stay first. Type icons drawn in QML for folder, image,
  audio, video, text, document, archive and other; local images smaller than
  20 MB show a thumbnail. The sidebar ends with a storage panel (accessible
  name "Storage", from `SystemStatus`) and the status line shows the free
  space of the current folder. "Open Terminal" (Shift+F4) starts Konsole in
  the current folder.
- Sun Store: a "Star picks" category (first in Discover, default) with a
  curated list of Flathub ids (`apps/sunstore/src/starpicks.h`); a banner that
  says where apps are kept: "Apps are kept on Star Storage" or "Live session:
  apps you install are removed at shutdown." with "Set up Star Storage".

## 5. Star Lens (`apps/lens`, package `staros-lens`, ADR-0012)

- Binary `/usr/bin/staros-lens`; desktop file `org.staros.lens.desktop` with
  `Exec=/usr/bin/staros-lens` (absolute: KWin matches the caller's executable
  against it) and `X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2`,
  KWin's packaged grant for screenshots (no permission bypass). Global
  shortcut `X-KDE-Shortcuts=Meta+Shift+L`; also in the launcher.
- Flow: capture the active screen with `CaptureActiveScreen` (raw image over a
  pipe) before any window is shown; show it full screen, dimmed; the person
  drags an area (or Ctrl+A for all, arrows move, Shift+arrows resize, Return
  confirms, Escape quits). Accessible names: window "Star Lens", the
  selection "Selected area", hint "Select an area".
- Results (glass panel, list "Results"): recognised text (Tesseract CLI,
  `tesseract stdin stdout -l eng`, offline), one QR or barcode
  (`Prison::ImageScanner`, offline), links found in either. Buttons: "Copy
  text", "Search the web" (opens Google search for the text in the browser),
  "Open link", "Copy image", "Save image" (to `~/Pictures/Star Lens/`),
  "Search with Google Lens".
- "Search with Google Lens" always asks first: "This sends the selected image
  to Google." It then copies the image, saves it, and opens
  `https://lens.google.com/` in the browser, where the person pastes or
  uploads it. Star Lens itself never uploads anything.

## 6. Star Storage (`apps/storage`, package `staros-storage`, ADR-0011)

- App `/usr/bin/staros-storage`, desktop file `org.staros.storage.desktop`
  ("Star Storage", "Storage Setup"). Shows the mode and usage
  (`SystemStatus`), any existing Star Storage disk, and the disks from the
  helper's `list` (run as the person): `lsblk --json --bytes`, whole disks
  with accepted names, each marked usable (writable, at least 8 GiB, not the
  boot medium, no mounted partition) or with the reason it is not. Choosing a
  disk shows model, size, connection and its partitions; the person must type
  the disk's name (for example `sdb`) before "Erase and set up" is
  enabled.
- Privileged helper `/usr/lib/staros/staros-storage-helper` (Python, stdlib
  only), started with `pkexec`. Polkit action `org.staros.storage.manage`
  (`auth_admin_keep`); on the live medium a rule in the overlay allows
  `liveuser` without a password, matching the live sudoers rule. The helper
  re-reads `lsblk` itself and refuses anything the app would not offer, plus a
  confirmation that differs from the name, a second `STAROS_DATA` disk, and
  names outside `sd*`, `vd*`, `nvme*n*`, `mmcblk*`, `xvd*`.
  - `format NAME CONFIRM`: `wipefs -a`, one GPT partition (`sfdisk`),
    `mkfs.ext4 -L STAROS_DATA`; JSON progress lines on standard output.
  - `boot next|always|never` (UEFI only): `bootctl set-oneshot` /
    `set-default` the Star Storage entry, or clear the default.
- Boot entries (added by `build-iso.sh` from `distro/archiso/staros/boot/`):
  systemd-boot `01-staros-storage-linux.conf` and the syslinux label
  `starstorage`, "Star OS live (prototype) with Star Storage", with
  `cow_label=STAROS_DATA cow_directory=persistent_%ARCHISO_UUID%/%ARCH%`.
  GRUB is not one of the ISO's boot modes (releng v91), so it has no entry.
  Never the default: archiso waits 30 s and opens an emergency shell when the
  disk is missing. Persistence belongs to one ISO build; a new ISO starts
  with an empty overlay (the old one stays on the disk).
- After formatting: UEFI offers "Restart into Star Storage" (`boot next`) and,
  once running from it, "Always start with Star Storage"; BIOS shows which
  menu entry to pick.

## 7. Tests

- Unit: `tests/shell/tst_quickanswers.qml`, `tst_notes.qml`, `tst_meter.qml`,
  launcher answer and note cases, icon fallback; `apps/system` C++ tests
  (status from fixture files, notes store); Files and Sun Store additions;
  Lens recogniser on rendered text and a generated QR code, Lens view with a
  fake backend; Storage disk list from `lsblk` fixtures, view with fakes;
  `tests/storage/test_helper.py` for the helper's validation and commands.
- Session (QEMU): S14 quick answer `12*3` shows "Answer: 36"; S15 `note:`
  creates a sticky note on the desktop and in `notes.json`; S16 the taskbar's
  "System status" says "Live session"; S17 Meta+Shift+L opens Star Lens with a
  capture (no permission error) and Ctrl+A, Return shows results (recognised
  text informational).
- Storage (job `storage-test`, `tests/storage/storage_test.py`, UEFI, a
  10 GiB scratch image as the only virtio disk `vda`, never a real disk):
  boot 1 opens Star Storage from the launcher, selects the disk, types `vda`,
  erases it (pkexec, the live rule, the helper) and uses "Restart into Star
  Storage"; boot 2 runs from Star Storage (`cow_label` on the command line,
  cowspace on `vda1`, the meter says "Star Storage"), writes a marker file
  and switches on "Always start with Star Storage"; boot 3 starts from the
  default entry and finds the marker.
