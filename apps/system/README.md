# StarOS.System

A QML module (M0.4, `docs/architecture/m04-apps-lens-storage-design.md`
section 3) used by the Star OS shell and apps:

- `SystemStatus`: where the live session keeps changes ("star-storage",
  "live" or "installed"), free and total storage, memory in use and battery
  level, refreshed every 5 seconds.
- `NotesStore` (singleton): the desktop's sticky notes, saved in
  `~/.local/share/staros/notes.json` and reloaded when the file changes.

It is installed as a plugin in Qt's QML directory
(`/usr/lib/qt6/qml/StarOS/System`).

```sh
cmake -B build -S apps/system -G Ninja -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
```
