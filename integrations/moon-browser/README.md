# Moon Browser integration

Moon Browser is the intended default browser for Star OS. It will **not** be
replaced with Firefox, Chromium, or any other browser without explicit owner
approval.

## Status: blocked — source not yet supplied

On 2026-10-19 no Moon Browser repository was in this repository or among the
repositories visible to the owner's GitHub account. Integration work is paused
until the owner provides the source location. The rest of Star OS continues
without it.

## Questions for the owner

1. Where is the Moon Browser source? (Repository URL, branch or tag.)
2. Who owns its copyright, and under what license is it released?
3. Is it based on an existing browser engine (Chromium/Blink, Gecko,
   QtWebEngine, WebKitGTK, or another), and which version?

## Review checklist (to be completed against the real source)

Each item gets an answer **and** the evidence (file path, command output, or
link). "Unknown" is a valid answer; a guess is not.

| # | Item | Answer | Evidence |
| --- | --- | --- | --- |
| 1 | Source language and UI framework | | |
| 2 | Repository layout | | |
| 3 | License, and redistribution requirements of it and its dependencies | | |
| 4 | Build system and build instructions | | |
| 5 | Runtime dependencies (and which are in the Arch baseline) | | |
| 6 | Browser engine and exact version | | |
| 7 | How engine security updates reach users, and how fast | | |
| 8 | Sandboxing model (process isolation, seccomp, namespaces) | | |
| 9 | Download and file-handling behaviour | | |
| 10 | Default-browser integration (`.desktop` file, `xdg-settings`) | | |
| 11 | URL scheme / protocol handlers (`http`, `https`, others) | | |
| 12 | Permissions it requires (camera, microphone, location, filesystem) | | |
| 13 | Packaging and install process today | | |
| 14 | Accessibility (screen reader, keyboard navigation, zoom) | | |
| 15 | Desktop integration (Wayland-native, portals, notifications) | | |
| 16 | Reproducible build feasibility | | |
| 17 | Telemetry or network connections made by default | | |

## Integration plan outline (after review)

1. Build Moon Browser from source in a Star OS PKGBUILD at a pinned revision.
2. Keep its identity and features. Adapt only packaging, the desktop entry,
   file and URL associations, and theme/settings integration.
3. Register it as the default handler for `http`/`https` and `text/html` in
   Star OS defaults.
4. Tests: launches on the live ISO, opens links from other apps, default-browser
   query returns Moon Browser, downloads land in the expected folder.
5. Security gate: if the engine cannot receive timely security updates, raise
   it with the owner before shipping. A browser that cannot be patched is a
   release-blocking risk.
