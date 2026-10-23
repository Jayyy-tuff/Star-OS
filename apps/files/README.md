# Files

The Star OS file manager (milestone M0.3,
`docs/architecture/m03-glass-files-store-design.md` section 2): a Qt Quick
interface over KIO. Folders are listed and watched by `KCoreDirLister`; copy,
move, rename, new folder, Trash, restore, empty Trash and delete are KIO jobs.
Files never starts programs: executables are refused, and scripts and desktop
entries open as text. Permanent deletion and emptying the Trash ask first.

Since M0.4 (`docs/architecture/m04-apps-lens-storage-design.md` section 4):
sort by name, size (largest first) or time modified (newest first) with the
"Sort" button or Ctrl+1/2/3, folders always first; type icons for images,
audio, video, text, documents and archives, and thumbnails for local PNG,
JPEG, GIF, WebP and BMP images under 20 MB; the free space of the folder's
disk in the status line; a Storage panel in the sidebar (where this session
keeps its changes, from StarOS.System, with a way to Star Storage); and
"Open Terminal" (Shift+F4), which starts Konsole in the current folder.

The QML module `StarOS.Files` is compiled into the binary. The frosted glass
look, icons and focus ring come from `StarOS.Shell`, which the Star OS ISO
installs in Qt's QML directory; builds and tests use the copy in `shell/qml`.

## Build and test

Needs Qt 6.12, KDE Frameworks 6.31 (KIO, KCoreAddons, KService), ECM and,
at run time and for the window test, StarOS.System (`staros-system`).

```sh
cmake -B build -S apps/files -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

The tests run headless (offscreen platform, software scene graph). In CI the
`packages` job builds the `staros-files` package from
`distro/packages/staros-files/PKGBUILD`, whose `check()` runs the same tests.
