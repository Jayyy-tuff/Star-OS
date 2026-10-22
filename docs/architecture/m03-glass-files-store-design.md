# M0.3 frosted glass, Files and Sun Store — design contract

Status: in progress (2026-10-22). Owner decisions of 2026-10-22: Star OS apps
are C++/QML programs built in CI into Star OS pacman packages; Sun Store
installs Flatpak apps per user from Flathub, only after the user confirms;
the icons are original SVG artwork in a frosted ("liquid glass") style; Star
OS artwork is licensed CC-BY-SA-4.0. Moon Browser stays out of scope: only
its icon is prepared, and no browser is added or substituted.

This file is the shared contract for the implementation. Names, paths and
interfaces below are fixed; anything not fixed here is the implementer's
choice. The repository files are authoritative once they exist.

## 1. Frosted glass theme (StarOS.Shell)

Approach: Star OS draws its own wallpaper (an original SVG) on the desktop,
and every glass surface renders the same wallpaper, in screen coordinates,
blurred and tinted. The taskbar has an exclusive zone, so only the wallpaper
is ever behind it, which makes this exact for the taskbar. The full-screen
launcher shows the frosted wallpaper over everything. No compositor blur
protocol and no Plasma theme are involved; KWin's blur effect is not used.

Files (all in `shell/qml/StarOS/Shell/`, installed to
`/usr/lib/qt6/qml/StarOS/Shell/`):

- `Theme.qml` (singleton) gains:
  - `wallpaper: url` = `Qt.resolvedUrl("wallpaper/star-os-glass.svg")`;
  - `reduceTransparency: bool` (default false; when true every glass surface
    is drawn opaque with `glassFallback`);
  - `glassTint: color`, `glassTintOpacity: real`, `glassBorder: color`
    (1 px edge highlight, may be translucent), `glassBlur: real` (0..1, for
    MultiEffect.blur), `glassBlurMax: int`, `glassRadius: int`,
    `glassFallback: color` (opaque equivalent), `tileGlass: color`
    (translucent tile fill);
  - `wallpaperDarkest: color`, `wallpaperLightest: color`: the darkest and
    lightest colours used anywhere in the wallpaper SVG, for contrast tests.
  - Existing tokens stay; `desktop` remains the colour shown before the
    wallpaper loads.
- `GlassSurface.qml` (new): an `Item` that draws frosted glass.
  - `property point wallpaperOrigin`: this item's top-left in screen
    coordinates (the host provides it; Wayland clients cannot query it).
  - `property size screenSize`: the screen size in logical px.
  - `property real radius` (default `Theme.glassRadius`).
  - `readonly property bool blurAvailable`: false under the software scene
    graph (`GraphicsInfo.api === GraphicsInfo.Software`) or when
    `Theme.reduceTransparency`; then it draws `Theme.glassFallback` only.
  - Otherwise: wallpaper `Image` sized to `screenSize`
    (`fillMode: Image.PreserveAspectCrop`, positioned at `-wallpaperOrigin`),
    clipped, blurred with `QtQuick.Effects` `MultiEffect`, then the tint at
    `glassTintOpacity`, then the `glassBorder` edge.
  - Purely decorative: `Accessible.ignored: true`.
- `Icons.qml` (singleton, new): `function source(appId): url` returns the
  icon for an app id (a trailing `.desktop` is ignored), or an empty url.
  Mapping: `org.kde.konsole` → `icons/terminal.svg`; `systemsettings` and
  `org.kde.systemsettings` → `icons/settings.svg`; `org.staros.files` →
  `icons/files.svg`; `org.staros.sunstore` → `icons/sun-store.svg`; `moon`,
  `moon-browser`, `org.staros.moon`, `org.staros.moonbrowser` →
  `icons/moon-browser.svg` (prepared for the owner's Moon Browser).
- `AppIcon.qml` (new): `property string appId`, `property string name`.
  Shows the mapped SVG (`sourceSize` set for crisp rendering) or, if there is
  none, the existing monogram style. `Accessible.ignored: true`.
- `icons/*.svg`: terminal, settings, files, sun-store, moon-browser. Original
  artwork, 256×256 viewBox, a rounded "squircle" glass tile with translucent
  gradient, inner highlight and a simple glyph (prompt `>_`, gear, folder,
  sun with shopping bag, crescent moon). Each file starts with an XML
  comment carrying `SPDX-License-Identifier: CC-BY-SA-4.0`. Under 8 KB each.
- `wallpaper/star-os-glass.svg`: original abstract wallpaper (deep night
  blues to violet with soft glows; no text), CC-BY-SA-4.0 SPDX comment,
  under 64 KB.
- `Taskbar.qml`: background becomes a `GlassSurface`. New properties
  `property point glassOrigin` and `property size glassScreenSize` passed to
  it (defaults: origin `(0, Screen.height - height)`, size of `Screen`).
- `Launcher.qml`: background becomes a full-size `GlassSurface` with origin
  `(0, 0)`; tiles show `AppIcon` and use `Theme.tileGlass`.
- `LauncherTile.qml`: new `property string appId`; shows `AppIcon`.
- `TaskButton.qml`: new `property string appId`; shows a small `AppIcon`
  before the title.
- `qmldir` lists the new types; the module may import `QtQuick`,
  `QtQuick.Templates`, `QtQuick.Effects` and `QtQuick.Window` only
  (`tests/shell/check_shell_sources.py` enforces this list).
- Text and focus contrast must hold over the glass in the worst case: the
  tint composited at `glassTintOpacity` over `wallpaperLightest` (and over
  `wallpaperDarkest`) must keep text ≥ 4.5:1 and the focus ring ≥ 3:1
  (`tst_theme.qml` checks it).

Plasma side (`shell/plasma/`):

- `org.staros.desktop/contents/ui/main.qml` draws `Theme.wallpaper` with
  `PreserveAspectCrop` over the colour wallpaper.
- `org.staros.taskbar/contents/ui/main.qml` passes `glassOrigin`
  `(0, Screen.height - height)` and the screen size to `Taskbar`; the model
  role `AppId` reaches `TaskButton.appId` and `LauncherTile.appId`.
- `AppCatalogue.qml` `desktopIds` becomes, in this order:
  `org.kde.konsole.desktop`, `systemsettings.desktop`,
  `org.staros.files.desktop`, `org.staros.sunstore.desktop`. KMenuEdit
  leaves the catalogue (the package stays installed).

## 2. Files (file manager)

- Source `apps/files/`; CMake project `staros-files`; C++17 or later,
  Qt 6 and KF6 (`KF6::KIOCore`, `KF6::KIOGui`, `KF6::CoreAddons`), ECM.
- Binary `/usr/bin/staros-files`; desktop file
  `/usr/share/applications/org.staros.files.desktop` (`Name=Files`,
  `GenericName=File Manager`, `Exec=staros-files %U`,
  `MimeType=inode/directory;`, `Categories=Qt;KDE;System;FileTools;FileManager;`).
  `QGuiApplication::setDesktopFileName("org.staros.files")`, so the Wayland
  app id is `org.staros.files`.
- QML UI compiled into the binary with `qt_add_qml_module` (URI
  `StarOS.Files`); it imports `StarOS.Shell` at run time for Theme, glass,
  icons and focus ring, and `QtQuick.Controls` (Basic style) where useful.
- Backend: a folder model over `KCoreDirLister`/`KFileItem` (name, url,
  isDir, size, modified time, MIME type and comment, hidden), sorting folders
  first then by name (case-insensitive), a name filter, hidden-file toggle;
  file operations over KIO jobs: open (`KIO::OpenUrlJob`), copy, move,
  rename, new folder, move to trash, restore from trash, empty trash,
  permanent delete (UI asks first), with progress and error signals.
- Places: Home, Desktop, Documents, Downloads, Music, Pictures, Videos
  (`QStandardPaths`; only those that exist), Trash (`trash:/`), Computer (`/`).
- Keyboard: arrows, Return opens, Backspace / Alt+Up parent, Alt+Left /
  Alt+Right back / forward, Ctrl+C / Ctrl+X / Ctrl+V, F2 rename, Delete to
  trash, Shift+Delete permanent delete (confirmation), Ctrl+Shift+N new
  folder, Ctrl+H hidden files, Ctrl+L location, Ctrl+F filter, Escape closes
  dialogs. Focus is always visible (StarOS.Shell `FocusFrame`).
- Accessibility (checked by the session test): window title
  `Files — <folder name>`; a list named "Places"; the item view (role List)
  named "Folder contents", items named with the file name and described with
  the type (and size for files); a tool bar named "Files toolbar".
- Tests: C++ Qt Test for the model and operations on a `QTemporaryDir`;
  Qt Quick Test for the QML with fake models. `ctest` runs them; the
  PKGBUILD `check()` runs `ctest` (offscreen platform).

## 3. Sun Store (Flatpak store)

- Source `apps/sunstore/`; binary `/usr/bin/staros-sunstore`; desktop file
  `/usr/share/applications/org.staros.sunstore.desktop` (`Name=Sun Store`,
  `GenericName=Software Store`, `Categories=Qt;System;PackageManager;`); app
  id `org.staros.sunstore`; QML module `StarOS.SunStore`; uses `StarOS.Shell`.
- Backend: the `flatpak` command line through `QProcess` (asynchronous,
  never through a shell), always with `--user`. The command path is a
  constructor argument so unit tests can use a fake `flatpak` script; the
  shipped app has no test switch and no environment hook.
  - remotes: `flatpak remotes --user --columns=name,url`
  - enable Flathub (after consent): `flatpak remote-add --user
    --if-not-exists flathub /usr/share/staros-sunstore/flathub.flatpakrepo`
  - refresh catalogue: `flatpak update --user --appstream flathub`
  - installed: `flatpak list --user --app --columns=application,name,version,origin`
  - updates: `flatpak remote-ls --user --updates --app --columns=application,version`
  - permissions before install: `flatpak remote-info --user --show-metadata
    flathub <app id>` (parse `[Context]`: shared, sockets, devices,
    filesystems; and `[Session Bus Policy]` / `[System Bus Policy]` names)
  - install: `flatpak install --user --noninteractive -y flathub <app id>`
  - remove: `flatpak uninstall --user --noninteractive -y <app id>`
  - update all: `flatpak update --user --noninteractive -y`
  - open: `flatpak run <app id>` (detached)
- Catalogue: parse the AppStream catalogue of the user installation
  (`~/.local/share/flatpak/appstream/flathub/x86_64/active/appstream.xml.gz`,
  or `appstream.xml`) with `KCompressionDevice` (KF6::Archive) and
  `QXmlStreamReader`; desktop applications only; untranslated name, summary,
  description paragraphs, cached 128×128 icon, categories, developer name,
  project licence, Flathub verification flag, latest release version.
- `flathub.flatpakrepo` ships in the package at
  `/usr/share/staros-sunstore/flathub.flatpakrepo`. The PKGBUILD downloads it
  from `https://dl.flathub.org/repo/flathub.flatpakrepo` with a pinned
  sha256 (recorded after review of the first CI run, like the package
  manifest). Nothing is added to `/etc/flatpak`; there is no system remote.
  Arch's `flatpak` package ships one in
  `/usr/share/flatpak/remotes.d/flathub.flatpakrepo`; the ISO build does not
  extract it (`NoExtract` in the build-time `pacman.conf`).
- UI: search field; Discover (catalogue, by category), Installed, Updates;
  app page with icon, name, developer, verified badge, licence, summary,
  description, permissions, Install / Remove / Open, progress and errors.
  First run shows: "Sun Store installs apps from Flathub, a community app
  store. Star OS does not review these apps." with buttons "Enable Flathub"
  and "Not now" ("Not now" closes Sun Store and changes nothing; it asks
  again on the next start). Offline: "Can't reach Flathub. Check your network
  connection." Accessibility: a page tab list "Store sections", a list
  "Apps", buttons named "Enable Flathub", "Install", "Remove", "Open".
- Tests: C++ Qt Test with a fake `flatpak` script and AppStream fixtures;
  Qt Quick Test for the QML with a fake backend.

## 4. Build and packaging (ADR-0009)

- `distro/packages/<pkgname>/PKGBUILD` for `staros-files` and
  `staros-sunstore`; fixed `pkgver=0.3.0`, `pkgrel=1` (bumped in reviewed
  changes, so the package manifest stays stable between commits); licence
  `GPL-3.0-or-later` (Sun Store package also carries the artwork licence if
  it ships artwork). Sources: a tarball of the checked-out tree (without
  `.git`, `build/` and `out/`; the CI container's checkout has no `.git`) named
  `star-os-src.tar.gz` (sha256 `SKIP`: generated from the checked-out tree),
  plus the Flathub file for Sun Store. `check()` runs `ctest` with
  `QT_QPA_PLATFORM=offscreen`.
- `scripts/build-packages.sh OUTDIR`: in a disposable pinned Arch container,
  installs `base-devel` and each PKGBUILD's `depends`/`makedepends` with
  pacman as root, builds each package as an unprivileged `builder` user
  (`makepkg --nodeps` after the explicit install), and creates the repository
  `OUTDIR/staros.db.tar.gz` with `repo-add`.
- `scripts/build-iso.sh` gains `STAROS_LOCAL_REPO` (a directory): it adds
  `[staros]` with `SigLevel = Optional TrustAll` and
  `Server = file://<dir>` to the profile's `pacman.conf` (build time only;
  the image's own `/etc/pacman.conf` comes from the pacman package and has
  no such repository). Without it, the build fails if the package list asks
  for `staros-*` packages.
- `packages.x86_64.append` adds `staros-files`, `staros-sunstore` (which
  pulls `flatpak`).
- Live medium: the boot entries gain `cow_spacesize=50%` (archiso's
  `kernel_params_x86_64` in `profiledef.append.sh`; the build checks every
  generated entry) so Flatpak apps fit
  in the RAM-backed writable layer (tmpfs pages are only used when written).
- CI: new job `packages` (archlinux container; needs lint) builds and tests
  the packages and uploads `staros-packages`; `build` needs `packages` and
  passes the downloaded repository to `build-iso.sh`.
- Image policy adds: `staros-files` and `staros-sunstore` installed; no
  `/etc/flatpak/remotes.d` entries and no system Flatpak remote; the shipped
  `flathub.flatpakrepo` present.

## 5. Session test additions

- S12 Files: Meta, type `fil`, Return; KWin's active window app id contains
  `org.staros.files`; AT-SPI shows the "Places" list and "Folder contents".
- S13 Sun Store: Meta, type `sun`, Return; active app id contains
  `org.staros.sunstore`; AT-SPI shows a button named "Enable Flathub" (CI
  has no network, so nothing is downloaded).
- Launch steps are gating; screen dumps stay informational. The screen
  analysis no longer looks for flat reserved taskbar colours; it reports the
  strongest horizontal edge near the bottom (the glass taskbar's top edge).
