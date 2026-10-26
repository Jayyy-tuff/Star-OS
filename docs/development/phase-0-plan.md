# Phase 0 plan: feasibility and architecture

Phase 0 goal (from the specification): prove a repeatable build and boot
process, document the major technology choices, identify licensing and
security uncertainties, and record human approval of the architecture.

## Phase 0 deliverables and status

| Deliverable | Where | Status |
| --- | --- | --- |
| Repository initialized | this repo | Done (documentation only) |
| License and contribution policy | ADR-0007, LICENSES.md, CONTRIBUTING.md | License accepted (GPL-3.0-or-later; docs CC-BY-SA-4.0). Contribution policy: draft |
| Initial threat model | docs/security/threat-model.md | Draft |
| Architecture decision records | docs/decisions/ | 0001–0005, 0007–0017 accepted (owner review pending: 0011's live polkit rule, 0014's backends, 0015's weather provider); 0006 deferred |
| Supported hardware assumptions | below | Draft |
| Package baseline policy | ADR-0002 | Accepted |
| Wayland/compositor evaluation | ADR-0004 | KWin accepted; shell hosting decided by M0.2 |
| Installer framework evaluation | ADR-0005 | Calamares accepted |
| Btrfs snapshot and recovery prototype plan | ADR-0006 | Deferred to Phase 2 with plan |
| Build environment setup | ADR-0003 + milestone M0.1 | **M0.1 complete** (CI build, QEMU boots, VMware boot) |
| Qt/QML shell prototype | milestone M0.2 | CI green (run 12); owner's VMware run pending |
| Glass theme, Files, Sun Store | milestone M0.3 | CI green (run 18); owner's VMware run pending |
| Apps, Star Lens, Star Storage, desktop features | milestone M0.4 | CI green (runs 24 and 25); owner's VMware run and review of the live storage rule pending |
| Deep Space desktop: taskbar, start menu, installed apps, quick settings, notifications, clipboard, widgets, Game Center, Welcome, lock and logout screens | milestone M0.5 | CI green (run 49); owner's VMware run pending |
| Moon Browser integration checklist | — | Removed from the current scope at the owner's request (2026-10-19); the owner will add Moon Browser later. No other browser will be substituted without approval |

## Smallest useful deliverable: M0.1 — console ISO prototype

The smallest deliverable that proves something real: **a Star OS–identified
Arch live ISO, built by CI from this repository with pinned package inputs,
that boots to a shell in QEMU (UEFI and BIOS) and in VMware Workstation.**

It has no desktop, installer, or branding artwork. Those depend on decisions
still awaiting approval. Every later milestone builds on this pipeline.

### Contents (implemented 2026-10-19)

```
distro/archiso/
  ARCHISO_VERSION                  # archiso version the overlay is validated against
  staros/                          # Star OS overlay on top of releng (ADR-0001)
    profiledef.append.sh           #   iso_name=staros, label, publisher, application
    airootfs/etc/staros-release    #   Star OS identity (os-release format, ID=staros)
    airootfs/etc/motd              #   prototype warning
    airootfs/etc/systemd/system/staros-boot-check.service
    airootfs/usr/local/libexec/staros-boot-check   # boot report + marker on serial
distro/baseline/ARCH_SNAPSHOT_DATE  # package baseline date (ADR-0002)
distro/baseline/packages.x86_64.txt # recorded package list (added after the first CI build)
scripts/build-iso.sh                # host and version checks, profile assembly, mkarchiso, records
scripts/ci/prepare-arch-build-host.sh   # pins a throwaway Arch container to the baseline
scripts/ci/check-package-manifest.sh    # T0-05
tests/iso/boot_test.py              # QEMU boot test (OVMF / SeaBIOS), read-only ISO, no disks
tests/iso/test_boot_test.py         # unit tests for the boot test
.github/workflows/iso.yml           # lint → build → package check + boot tests
docs/development/building.md
```

The profile is assembled at build time rather than committed as a full copy.
ADR-0001's implementation note explains why.

**Change to acceptance criterion 4:** the live system's `/etc/os-release` stays
Arch's. That file belongs to Arch's `filesystem` package. Overwriting it from
the archiso overlay would make package installation fail on a file conflict,
and replacing it properly needs a Star OS package, which needs the Star OS
repository (Phase 1). Until then, Star OS identity is carried by the boot menu
titles and `/etc/staros-release`.

### Acceptance criteria

1. A clean checkout builds the ISO with one documented command in CI. The ISO,
   `SHA256SUMS`, the package manifest, and the build log are uploaded as
   artifacts.
2. Two CI builds with the same baseline date produce identical package
   manifests. (Package inputs are pinned. Byte-identical ISOs are **not**
   claimed.)
3. The CI-built ISO boots in QEMU with OVMF (UEFI) and with SeaBIOS (BIOS) and
   prints the boot marker on the serial console within the timeout. Logs are
   uploaded whether the boot passes or fails.
4. The live environment identifies itself as Star OS (boot menu titles in the
   assembled profile, `ID=staros` in `/etc/staros-release`, reported at boot).
5. All shell scripts pass `shellcheck`.
6. **Owner-run:** the same CI-built ISO boots to a shell in VMware Workstation
   (UEFI, Secure Boot off), recorded in the
   [test plan](test-plan.md#manual-test-log) with the VMware version and VM
   settings.

M0.1 is done when 1–5 pass in CI and 6 is recorded. Until 6 is recorded, the
README says "boots in QEMU (CI)" and nothing about VMware.

### Status (2026-10-19)

Evidence: [ISO run #1](https://github.com/Jayyy-tuff/Star-OS/actions/runs/39315730622)
(commit `27a290a`) and [ISO run #2](https://github.com/Jayyy-tuff/Star-OS/actions/runs/39317741583)
(commit `9a0f391`, all jobs green).

| Criterion | Result |
| --- | --- |
| 1. CI builds the ISO and uploads records | **Pass** (runs #1 and #2). archiso 91-1, boot modes `bios.syslinux uefi.systemd-boot`, snapshot 2026-10-15, 455 packages, 1.6 GB ISO. Build step about 9–11 minutes |
| 2. Pinned package inputs | **Pass.** Run #2's package list is identical to run #1's, which is recorded in `distro/baseline/packages.x86_64.txt` (T0-05). ISO checksums differ between runs because the build timestamp differs; byte-identical ISOs are not claimed |
| 3. QEMU boot, UEFI and BIOS | **Pass** (both runs). UEFI: `id=staros firmware=uefi kernel=7.2.9-arch1-1`, marker 43 s / 38 s after QEMU start. BIOS: `firmware=bios`, 32 s / 32 s. KVM on GitHub-hosted runners. The harness correctly failed a non-bootable image in every run (T0-09) |
| 4. Star OS identity | **Pass.** `id=staros` reported at boot. Run #2 build records list the renamed entries: systemd-boot (normal and speech), GRUB (`grub.cfg`, `loopback.cfg`), and syslinux (BIOS, speech, PXE) |
| 5. shellcheck | **Pass** |
| 6. VMware Workstation boot | **Pass**, reported by the owner on 2026-10-19 (T0-10, see the [manual test log](test-plan.md#manual-test-log)) |

The boot times are measured in CI QEMU from QEMU start to the marker. They are
not performance claims for any real machine.

Known follow-ups (not blocking):

- `actions/upload-artifact` and `actions/download-artifact` v5.0.0 still target
  Node.js 20. GitHub currently forces them onto Node.js 24 with a warning. Bump
  them to releases that target Node.js 24, pinned to verified commit SHAs.
- The package-list query prints a harmless "database file … does not exist"
  warning, because the live root has no sync databases.

### Explicitly out of scope for M0.1

Graphical session, installer, accounts, Secure Boot, ISO signing, a Star OS
package repository, branding artwork, and hardware support claims.

## M0.2 — shell prototype on the live ISO (in progress)

ADR-0008 (accepted 2026-10-20) fixes the approach: an unmodified plasmashell
loads the Star OS shell package, whose visible UI is the Plasma-free
`StarOS.Shell` QML module; the live medium logs an unprivileged `liveuser`
into a Wayland session on KWin. The engineering spec is
`docs/architecture/m02-shell-prototype-design.md`; the tests are T0-20..T0-26
in `test-plan.md`.

### Status (2026-10-20, CI run 9 on commit 64fb1ab)

Measured in CI (QEMU/KVM on GitHub's Ubuntu runners; not VMware or hardware
results):

- **Build and image policy:** the ISO builds (2,170,028,032 bytes, 847
  packages: the 392 additions iteration 0 predicted, no other change) and
  every image policy check passes (T0-26).
- **Session starts (T0-20), UEFI and BIOS:** `staros-session-report` reports a
  `wayland` logind session for `liveuser` on seat0/VT 1, plasmashell running
  `org.staros.shell` with the expected layout (one bottom, non-floating
  `org.staros.taskbar` panel, 45 px; `org.staros.desktop` with the colour
  wallpaper), renderer llvmpipe, the window-management grant present, and no
  forbidden variable in KWin's or plasmashell's environment. The session was
  ready about 33 s after boot. The screen dump shows 45 rows of taskbar colour
  and desktop colour everywhere else (informational check).
- **Stays up and idle cost (T0-20b, T0-25):** three UEFI boots, each stable 330
  s after ready (same plasmashell and KWin processes, no restarts). Median
  (min–max) after 240 s idle, 60 s window: session PSS 714.8 MiB (713.7–719.7)
  over 30 processes, plasmashell 344 MiB, kwin_wayland 188.9 MiB, system memory
  in use 1003 MiB of 3.9 GiB, session CPU 0.05 % of one CPU (0.03–0.08). These
  describe a CI VM with software rendering and are not performance claims.
- **QML unit tests (T0-20..T0-23 unit level):** 182 of 183 test functions pass
  across 100/150/200 %; the remaining failure was a test-side grab-crop issue
  at 200 %, fixed in the following commit.

### Status (2026-10-21, CI run 12 on commit 531912f: every job green)

- **Unit tests:** all 183 QML test functions pass at 100, 150 and 200 %.
- **Keyboard-only use on the real ISO (T0-21, T0-22 in QEMU):** with key
  presses sent through QMP, Meta opens the launcher with focus in "Search
  applications"; typing `kon` and Return launches Konsole, `sys` and Return
  launches System Settings, and KWin's own view reports each as the active
  window; the taskbar lists both windows with exactly one described as
  "Active window"; Meta+Alt+P focuses "Applications", Right and Return
  activate Konsole; Escape closes the launcher and KWin returns focus to
  Konsole. AT-SPI shows the taskbar as a tool bar with Applications, the
  Open windows list and Leave.
- **Scaling under KWin (T0-23, informational):** with `kscreen-doctor` at 150,
  200 and 100 %, the launcher's tiles stay inside its window and do not
  overlap; the taskbar band measures 67, 90 and 45 rows.
- **Screen reader (T0-24, informational):** Meta+Alt+S starts Orca; a debug
  Orca logs what it would speak while the launcher is used: "Star OS
  applications", "Application launcher panel", "Search applications text",
  "Applications list", "Konsole button", "Terminal", "Menu Editor button".
  Audible speech is an owner check.
- **Idle (T0-25):** a second set of three boots gives a session PSS median of
  713.6 MiB (660.4–716.3), plasmashell 343.6 MiB, kwin_wayland 190.6 MiB,
  1004 MiB in use, session CPU 0.05 % of one CPU; all stable.

Still to do: keep S10 and S11 informational until they have three consecutive
green runs; the owner's VMware run (procedure in `test-plan.md`, 3D on and
off); then the ADR-0004 A/B decision with the CI and VMware numbers.

## M0.3 — frosted glass, Files and Sun Store (CI green; VMware run pending)

Requested by the owner on 2026-10-22: a frosted glass theme, original icons
for the terminal, settings and Moon Browser (icon only; no browser is added),
a file manager, and a Flatpak app store named Sun Store. Owner decisions the
same day: C++/Qt Quick applications built as pacman packages (ADR-0009),
per-user Flatpak with Flathub added after consent (ADR-0010), original SVG
artwork drawn for Star OS, artwork under CC-BY-SA-4.0 (ADR-0007 amendment).
The design contract is `docs/architecture/m03-glass-files-store-design.md`;
the tests are T0-30..T0-34 in `test-plan.md`.

What exists in the repository:

- `StarOS.Shell`: frosted glass surfaces (the Star OS wallpaper, blurred and
  tinted; opaque without a GPU or with reduced transparency), five original
  icons (terminal, settings, files, Sun Store, Moon Browser) and the
  wallpaper, all SVG and under 8 KB (icons) / 64 KB (wallpaper).
- `apps/files/` and `apps/sunstore/` with C++ and QML tests, packaged from
  `distro/packages/`; `scripts/build-packages.sh`; the ISO build's local
  repository and the `cow_spacesize=50%` boot parameter; image policy and
  session test additions (S12, S13).

### Status (2026-10-22, CI run 18 on commit a3ce231: every job green)

Measured in CI (QEMU/KVM on GitHub's runners, software rendering with
llvmpipe; not VMware or hardware results):

- **Packages (T0-30, T0-31):** `staros-files` and `staros-sunstore` build in
  the pinned container and pass all their tests: Files 6 of 6 (folder model,
  file operations on temporary folders, places, the view with fakes, the
  real window, desktop file), Sun Store 7 of 7 (flatpak output parsers,
  AppStream reader, the store against a fake `flatpak`, the view with a fake
  store, the real window, desktop file, and ECM's automatic AppStream metadata
  check, which has no metadata file to validate yet). Three CI
  runs on the way fixed a test timing issue (clicking a button before its row
  was laid out) and pinned Flathub's remote file (checksum `3371dd25…`,
  signing key fingerprint `6E5C05D979C76DAF93C081354184DD4D907A7CAE`).
- **Image (T0-32):** 854 packages: the 847 of M0.2 plus `composefs`,
  `flatpak`, `libmalcontent`, `ostree`, `xdg-dbus-proxy`, `staros-files` and
  `staros-sunstore`. The ISO grows to about 2.18 GB (1,062,288 sectors in
  run 17). Every image policy check passes. The first M0.3 build (run 16)
  found that Arch's `flatpak` package ships Flathub as a static system-wide
  remote; the build no longer extracts that file (ADR-0010).
  `cow_spacesize=50%` is on all 11 generated boot entries and on the booted
  kernel command line (2.0 GB of copy-on-write space with 4 GB RAM).
- **Session (T0-33, T0-34; QEMU):** UEFI and BIOS boots reach the session;
  S0–S9 pass as in M0.2. S12: typing `fil` and Return opens Files; KWin
  reports `org.staros.files` active with the title "Files — Home"; AT-SPI
  shows the "Files toolbar", the "Places" list (Home, Desktop, Documents,
  Downloads, Music, Pictures, Videos, Trash, Computer) and the "Folder
  contents" list. S13: `sun` and Return opens Sun Store (`org.staros.sunstore`
  active); AT-SPI shows the "Store sections" page tabs and the consent dialog
  with "Enable Flathub" and "Not now"; `flatpak remotes --user` is empty
  afterwards. Scaling (S11, informational): four tiles inside the launcher
  with no overlap at 150, 200 and 100 %. Orca (S10, informational) speaks
  "Files button", "File Manager", "Konsole button" and, for Sun Store, "Enable
  Flathub? dialog Sun Store installs apps from Flathub, a community app store.
  Star OS does not review these apps." and "Enable Flathub button".
- **Glass on screen (informational):** the screen analysis finds the
  taskbar's top edge 45 rows above the bottom (65 and 90 at 150 and 200 %).
  The band's mean colour, #11152e, matches the glass tint over the wallpaper
  (about #10132e by calculation) rather than the opaque fallback #151c33,
  which suggests the blurred glass path is drawn in the live session. Whether
  it looks right is the owner's check.
- **Idle (T0-25):** three boots, all stable. Median (min–max): session PSS
  775.5 MiB (775.0–780.9), plasmashell 406.4 MiB, kwin_wayland 188.3 MiB,
  1065 MiB in use, session CPU 0.07 % of one CPU. Compared with M0.2
  (713.6 MiB, plasmashell 343.6 MiB), plasmashell uses about 62 MiB more,
  most likely the glass layers and the full-screen wallpaper textures. Not a
  performance claim.

Still to do: the owner's VMware run (procedure in `test-plan.md`, with
network for installing an app from Flathub, 3D on and off).

## M0.4 — apps, Star Lens, Star Storage and desktop features (CI green; VMware run pending)

Requested by the owner on 2026-10-23: better apps, Firefox, VLC and similar
apps, features unique to Star OS including one "like Google Lens", and "a
disk storage to install things & make it visible in the os". Owner decisions
the same day: preinstall a core set; offline recognition plus Google Lens on
request (ADR-0012); a persistent live disk (ADR-0011); storage and system
meter, quick answers in the launcher, desktop sticky notes. The design
contract is `docs/architecture/m04-apps-lens-storage-design.md`; the tests
are T0-35..T0-40 in `test-plan.md`.

What exists in the repository:

- Preinstalled from Arch: Firefox, VLC, Okular, Gwenview, Ark, KWrite, KCalc,
  Tesseract with English data; all in the launcher's catalogue.
- `apps/system/` (`staros-system`): the `StarOS.System` QML module with
  `SystemStatus` (storage and memory, where changes are kept) and
  `NotesStore` (`~/.local/share/staros/notes.json`).
- `StarOS.Shell`: quick answers in the launcher (sums, percentages, units),
  the sticky notes board on the desktop (`note: …` in the launcher or "New
  note"), and the System status button in the taskbar, which opens Star
  Storage.
- `apps/lens/` (`staros-lens`, Meta+Shift+L): screenshot through KWin's
  grant for its desktop file, area selection by mouse or keyboard, offline
  text (Tesseract) and QR/barcode (Prison) recognition, copy, save, open
  found links, web search, and Google Lens only after a warning each time.
- `apps/storage/` (`staros-storage`): Star Storage with its root helper,
  polkit action and live rule, and the "with Star Storage" boot entries.
- Files: sort by name, size or time, free space, type icons and image
  thumbnails, Open Terminal, a Storage panel. Sun Store: "Star picks" (14
  free apps on Flathub) first, and a banner that explains where installed
  apps are kept.

### Status (2026-10-23, CI run 24 on commit be49e21: every job green)

Measured in CI (QEMU/KVM on GitHub's runners, software rendering with
llvmpipe; not VMware or hardware results). The first attempt of run 24
stopped while downloading packages from the Arch Linux Archive (the ISO
build, before any test); the re-run of the failed jobs passed. Runs 19–23
fixed: the QML plugin's file name, the notes folder watch, a test double
that hid QML's own functions, a missing Qt Quick link, a Star Lens hang
without a session bus, keyboard focus and a live rectangle in the Lens view,
and two Star Storage test-harness problems (a pipe left open for the
helper, rows read before they existed).

- **Packages (T0-35..T0-40 unit parts):** five packages build in the pinned
  container and pass all their suites: StarOS.System 3 of 3, Files 6 of 6,
  Star Lens 5 of 5 (recognition of rendered text, a QR code and an EAN-13
  barcode; the backend at scale 2; the view; the real window), Star
  Storage 5 of 5, Sun Store 8 of 8. The helper's own 18 tests run in lint;
  the shell's QML tests (quick answers, notes, system meter, launcher) in
  `shell-checks`.
- **Image:** 946 packages, matching the updated baseline (T0-05). Every image
  policy check passes, including the new ones: the seven apps and their
  desktop files, Star Lens's screenshot grant and shortcut, the English OCR
  data, the helper (root:root 755), the polkit action (administrator, exec
  path) and the live rule (one action, `liveuser` only). The build checks
  that exactly one UEFI and one BIOS "with Star Storage" entry exist, with a
  per-build folder and no placeholder left. The ISO artifact is about
  2.48 GB.
- **Session (QEMU):** UEFI and BIOS boots reach the session; S0–S9, S12 and
  S13 pass. Files shows "Sort: Name", "Open Terminal", the Storage panel with
  "Set up Star Storage" and "9 items · 1.9 GiB free". Sun Store lists "Star
  picks" first and says "Live session: apps you install are removed at
  shutdown." S14: "12*3" shows "Answer: 36"; Return copies it. S15: "note:
  hello star" is saved in `notes.json` and shown as a "Sticky note" on the
  desktop. S16: System status says "Live session: changes are lost at
  shutdown. 2 GB free of 2 GB. Memory: 1.6 GB of 4.1 GB in use." S17:
  Meta+Shift+L starts Star Lens and KWin grants its screenshot ("Select an
  area"). S11 (informational): 13 tiles inside the launcher with no problems
  at 150, 200 and 100 %. S10 (informational): Orca speaks "Search
  applications", "Ark button", "Archiving Tool", "Files button".
- **Star Storage over three boots (T0-40, QEMU, 10 GiB scratch image):**
  B1: the helper lists the scratch disk as usable; Star Storage opens from
  the launcher; Tab reaches "Disk name to confirm"; typing `vda` and Return
  ends with "Star Storage is ready on /dev/vda1."; `blkid` reports an ext4
  file system labelled `STAROS_DATA` on a GPT partition of that name;
  "Restart into Star Storage" has the focus and Return restarts. B2: the
  one-shot entry booted (`cow_label=STAROS_DATA
  cow_directory=persistent_2026-10-23-12-35-27-00/x86_64`), the
  copy-on-write space is `/dev/vda1` (ext4), System status says "Star
  Storage: 10.4 GB free of 10.5 GB. …", the app refuses the disk in use
  ("Star OS is using this Star Storage now."), Shift+Tab and Space turn on
  "Always start with Star Storage" ("Star OS now starts with Star Storage
  every time."). B3: the default entry is now Star Storage and the marker
  file written in B2 is still there.
- **Idle (T0-25):** three boots, all stable. Median (min–max): session PSS
  817.3 MiB (807.1–823.5), plasmashell 442.0 MiB, kwin_wayland 192.3 MiB,
  1093 MiB in use, session CPU 0.18 % of one CPU, 30 processes. Compared with
  M0.3, plasmashell uses about 36 MiB more (notes board, system meter, quick
  answers) and idle CPU rose from 0.07 % to 0.18 %, probably the system
  meter's 5-second refresh. Not a performance claim.

S17 correction: run 24 also reported "Results" after Ctrl+A and Return, but
that check counted hidden objects too, so it did not prove that recognition
had finished. Commit 3ada26a counts only objects on screen (S12, S13, S17 and
the Star Storage checks). **CI run 25 on 3ada26a: every job green** with the
stricter checks. S17 there: "Select an area" on screen, then the "Results"
panel with Copy text, Search the web, Copy image, Save image, Search with
Google Lens; the text read from the whole 1920×1080 screen (informational)
begins "hello star / Applications / Delete / ~:bash — Konsole … Files — Home
/ Sun Store / Enable Flathub? / Sun Store installs apps from Flathub, a
community app store. Star OS does not review these apps. …": window titles,
the sticky note and the dialog were read correctly; small labels on the
glass taskbar came out as fragments ("D¢", "stoy", "Live|"). The Star
Storage test passed B1–B3 again.

Not tested in CI: recognition quality on real screens, Google Lens and web
search (no network), Firefox and VLC beyond their packages and desktop files,
Star Storage on USB sticks or internal disks, and BIOS boots with Star
Storage (the storage test uses UEFI).

Still to do: the owner's VMware run (`test-plan.md`, M0.4 procedure) and
the owner's review of the live polkit rule (ADR-0011).

## M0.5 — Deep Space desktop (CI green; VMware run pending)

Requested by the owner on 2026-10-25: "make the UI look realistic … modern,
aesthetic, and admirable", installed apps must appear in Applications, and
"ask me what else to add". Owner decisions the same day: a floating taskbar,
the deep space dark mood, quick settings and tray, clock, calendar and
notifications, clipboard history, desktop widgets, Game Center, a Welcome
tour and a matching lock screen. The design contract is
`docs/architecture/m05-deep-space-design.md` (with ADR-0013..ADR-0017); the
tests are T0-41..T0-48 in `test-plan.md`.

What exists in the repository:

- `StarOS.Shell`: deep space tokens (Inter, glass, accent gradient), a
  floating glass taskbar with the start button, apps and windows, tray,
  clock and bell; a start menu (pinned, all apps, recently installed,
  search with quick answers and notes, power menu); quick settings (network
  and Wi-Fi, volume, brightness, night light, Do not disturb, game mode,
  clipboard, Star Lens); toasts and a notification centre over a month
  calendar; the clipboard history panel (Meta+V); desktop widgets (Clock,
  Weather, System, Calendar).
- `StarOS.System` (`staros-system` 0.5.0): `ApplicationsModel` (every
  installed app, followed live), `AudioControl`, `DisplayControl`,
  `NetworkStatus` (networkd, iwd), `ClipboardHistory`, `WidgetStore`,
  `GameModeSetting`, and processor use in `SystemStatus`.
- The taskbar adapter is the notification server (libnotificationmanager)
  and hosts every panel in one layer-shell overlay.
- `apps/games` (`staros-games`, Game Center) and `apps/welcome`
  (`staros-welcome`, Welcome to Star OS); `gamemode`, `wl-clipboard` and
  `inter-font` in the image.
- `org.staros.lookandfeel` with the Star OS logout screen, the `StarOS`
  colour scheme and dark icons for KDE apps; the Star OS lock screen in the
  shell package `org.staros.shell` (kscreenlocker 6.7 reads it there);
  manual locking on the live medium.

### Status (2026-10-26, CI run 49 on commit 7a824ff: every job green)

Measured in CI (QEMU/KVM on GitHub's runners, software rendering with
llvmpipe; not VMware or hardware results). Runs 32–48 found and fixed, in
order: the Welcome step read the screen before accessibility was on; the
toast window waited for a list count that a hidden window never updates;
the notification centre follows KDE's history settings, which keep
notifications from unnamed senders out (S20 now sends as Files, which
names its desktop entry; ADR-0014); the clipboard history read the shell's
own old copy while another app's copy was arriving (it now reads each
change again once settled and never lets such a read move a copy up;
ADR-0014); S21 read the copies in creation order, not screen order;
kscreenlocker 6.7 loads the lock screen from the shell package, not the
look-and-feel package (ADR-0016, second amendment); and the session test's
checks for the greeters. Four runs stopped while downloading from the Arch
Linux Archive before any test; pacman now retries, and the ISO build fills
its package cache first. Facts about KDE's behaviour came from
`scripts/ci/inspect-kde.sh`, which prints the relevant KDE sources and
runs libnotificationmanager against the taskbar's settings.

- **Packages:** every Star OS package builds in the pinned container and
  passes its tests, including StarOS.System's clipboard, widget store and
  game mode tests, Game Center (Steam library files, desktop entries,
  filters, launches with a recorder, the view) and Welcome (state and
  pages). The shell's QML tests pass at 100, 150 and 200 %, including the
  new test that counts toasts in a hidden window.
- **Image:** the image policy checks pass (the Welcome autostart, GameMode,
  the lock and logout screens and the colour scheme among them) and the
  package list matches the baseline.
- **Boot, idle and Star Storage:** UEFI and BIOS boots reach the session.
  The three-boot Star Storage test passes, with the Welcome tour skipped on
  the first boot and staying shut on the third.
- **Session (QEMU), every scenario S0–S26 passes:**
  - S23: the Welcome tour opens at login as the active window ("Welcome to
    Star OS", "Take the tour"); Return turns to "Everything starts with the
    Star key"; Escape closes it and `staros-welcomerc` records it as seen.
  - S3–S9, S12–S17: the floating taskbar (Applications, Apps, Quick
    settings, Clock, Notifications), the start menu, windows by keyboard,
    Files, Sun Store, quick answers, notes, the system summary and Star Lens,
    as in M0.4 but through the new shell.
  - S18: an app exported into the live user's Flatpak folder appears at once
    under "Recently installed", marked "New. Installed just now · Flatpak",
    and searching "star test" and Return starts it.
  - S19: quick settings say "Wired, connected"; Tab reaches "Volume"; Right
    twice moves PipeWire's sink from 0.50 to 0.60.
  - S20: a D-Bus notification shows a toast "Files: Hello from the test";
    the clock's panel lists it and marks "Monday 26 October 2026, today";
    "Clear all" empties it ("No new notifications.").
  - S21: a copy survives `wl-copy` exiting; Meta+V lists "Second copy",
    "Star clipboard test", "36" in that order; Down and Return put "Star
    clipboard test" back and close the panel.
  - S22: Clock, Weather, System and Calendar are on the desktop; the weather
    asks for a city first ("Choose a city"); the System widget shows
    "Processor: N %"; hiding the calendar in `widgets.json` hides it at once.
  - S24: Game Center opens from the start menu with "Search games", the
    filters, "Game mode" and "No games yet".
  - S26: Power shows the Star OS logout screen ("What would you like to
    do?", Sleep, Restart, Shut down, Log out, Cancel); Escape cancels it.
  - S25: locking shows the Star OS lock screen (time, date, "Star OS live
    user", a focused password field, "Unlock"); Return unlocks the live
    user.
  - S11 and S10 (informational): the start menu fits at 100, 150 and 200 %;
    Orca speaks "Search applications" and "Files".
- **Idle (T0-25), three boots, all stable.** Median (min–max): session PSS
  1066.8 MiB (1063.6–1068.1), plasmashell 542.7 MiB, kwin_wayland 194.7 MiB,
  1347 MiB in use, session CPU 2.05 % of one CPU (1.87–2.30), 32 processes.
  Against M0.4 (817 MiB, 442 MiB, 0.18 %) memory grew by about 250 MiB and
  idle CPU about elevenfold. Not measured yet, but likely: the System
  widget's figures change every 5 seconds and repaint the full-screen glass
  desktop with software rendering. Not a performance claim.

Known gaps: the lock screen's password field reports "Password" as its
accessible description rather than its name (Orca may still read it; to be
checked); notifications from senders that name no app are not listed in
the notification centre (KDE's default setting, ADR-0014).

Not tested in CI: Wi-Fi, brightness and battery (no such hardware), the
weather with network, Steam and real games, GameMode's effect, sound
output, and anything in VMware or on hardware.

Still to do: the owner's VMware run (`test-plan.md`, M0.5 procedure); the
owner's review of ADR-0014's backends (iwd for Wi-Fi, PowerDevil for
brightness, a networkd summary) and ADR-0015's weather provider
(Open-Meteo); the idle CPU follow-up above; and the earlier owner items
(M0.2–M0.4 VMware runs, ADR-0011's live polkit rule).

## Supported hardware assumptions (Phase 0)

These are **assumptions to test**, not support claims.

- x86-64 CPUs from AMD and Intel that Arch Linux's kernel supports.
- UEFI firmware is the primary target. BIOS boot of the live ISO is kept while
  archiso provides it and CI tests it. BIOS **installation** is undecided
  (ADR-0006).
- Secure Boot must be disabled for now (ADR-0006).
- Virtual machines: VMware Workstation (priority, manual), QEMU/KVM (CI),
  VirtualBox (later, best effort).
- Phase 1 graphics in VMware are expected to use the `vmwgfx` kernel driver
  with Mesa. 3D acceleration may need to be enabled in the VM settings. This is
  to be verified in M0.2.
- Minimum RAM and disk for the live and installed systems will be set from
  measurements in M0.2 and Phase 1, not guessed.
