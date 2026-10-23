# ADR-0012: Star Lens reads the screen offline and sends images to Google Lens only when asked, every time

- Status: Accepted
- Date: 2026-10-23
- Deciders: project owner

## Context

The owner asked for features "like google lens". A Lens-like tool needs a
screenshot of what the person points at, text and code recognition, and a
way to search. On Wayland a program cannot read the screen by itself; KWin
offers `org.kde.KWin.ScreenShot2` only to programs it trusts. Sending images
to an online service is a privacy decision the person must make each time.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Offline OCR and codes, plus Google Lens in the browser after a warning** | Works without network; nothing leaves the computer unless the person asks; uses Google's own site, no API key | Two tools in one; Google Lens needs a paste or upload in the browser |
| Offline only | Simplest privacy story | No image search, which is what "like Google Lens" means |
| Send images to an online API directly | One click | Needs an API key and a service contract; uploads from Star OS itself |

The owner chose "Offline + cloud image search" on 2026-10-23.

## Decision

- **Screenshot**: Star Lens calls KWin's `CaptureActiveScreen` (raw image
  through a pipe, `native-resolution`, no cursor) before it shows a window.
  KWin allows it because `org.staros.lens.desktop` lists
  `X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2` and its
  `Exec=/usr/bin/staros-lens` matches the running executable. This is KWin's
  packaged-application grant, not a permission bypass; the image policy check
  verifies the entry.
- **Recognition, offline**: text with the Tesseract command line
  (`tesseract stdin stdout -l eng --psm 3`, English data from
  `tesseract-data-eng`), one QR code or barcode with KDE's Prison scanner
  (ZXing). Links (http, https, `www.`) are taken from both.
- **Actions**: Copy text, Copy code, Copy image, Save image (to
  `~/Pictures/Star Lens/`), Open link (only links that were recognised, only
  http and https), Search the web (opens a Google search for the recognised
  text in the browser), Search with Google Lens.
- **Google Lens**: always asks first, with Cancel focused: "This sends the
  selected image to Google. …". When confirmed, Star Lens copies the image,
  saves it, and opens `https://lens.google.com/` in the browser, where the
  person pastes or uploads it. Star Lens itself never uploads anything.
- **Shortcut**: `X-KDE-Shortcuts=Meta+Shift+L` (kglobalacceld registers it
  from the desktop file); also in the launcher.
- **Clipboard**: copies go through KDE's `KSystemClipboard`
  (`ext_data_control`, which KWin 6.7.5 offers to all clients). On Wayland a
  copy is served by the program that made it and the Star OS session has no
  clipboard manager, so after a copy Star Lens hides its window and keeps
  running until something else is copied.

## Consequences and trade-offs

- Any program that the person can make run as `/usr/bin/staros-lens` gets
  screenshots; that is the same trust KWin gives Spectacle.
- "Search the web" sends the recognised text to Google when the person
  presses it. It is labelled as a web search and needs no extra warning; the
  owner may ask for one.
- Tesseract is English only for now; other languages need their data
  packages.
- After a copy, an invisible Star Lens process stays until the clipboard
  changes. Other apps (Firefox, KWrite) lose copies when they quit, because
  there is no clipboard manager; that is a session gap beyond Star Lens.
- CI tests recognition on rendered text and generated codes, the backend on
  a given capture at scale 2, the view with a test double, and in QEMU that
  KWin grants the screenshot and Ctrl+A, Return show results. Recognition
  quality on real screens and the Google Lens flow (network) are owner tests.

## Revisit if

- A clipboard manager is added to the session.
- More OCR languages or on-device image search are wanted.

## Approval

- Chosen in the AI agent session on 2026-10-23: "Offline + cloud image
  search" ("Tesseract OCR + QR/barcodes offline; Google Lens action with a
  clear warning each time").
- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-23.
