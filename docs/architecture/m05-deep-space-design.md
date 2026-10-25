# M0.5 deep space desktop — design contract

Status: accepted by the owner's choices of 2026-10-25 (see "Decisions"). This
contract fixes the names, files and behaviour that the code, the packages and
the tests rely on. The visual target is the mockup page published for the
owner on 2026-10-25 (screens drawn in a browser from the shell's wallpaper,
icons and measurements); the QML follows it. Results are recorded in
`docs/development/phase-0-plan.md` only from CI runs and the owner's VMware
run.

## Decisions (owner, 2026-10-25)

| Question | Choice |
| --- | --- |
| Request | "make the UI look realistic … modern, aesthetic, and admirable. When you install an app it should show up in Applications section." |
| Layout | Floating taskbar: a centred, rounded glass taskbar above the screen edge with the Star button, app icons with running dots, tray and clock; a start menu above it with search, pinned apps, all apps and "Recently installed". |
| Colour mood | Deep space dark: today's star wallpaper, dark frosted glass, a violet-to-blue accent; apps get a matching dark colour scheme. |
| Desktop essentials | Quick settings and tray; clock, calendar and notifications; clipboard history; desktop widgets. |
| Extras | Game Center; Welcome tour; matching lock screen. Not chosen: a Star Settings app. |

## 1. Visual language (StarOS.Shell `Theme`)

- Font: Inter (`inter-font`, OFL-1.1) is the system UI font
  (`/etc/xdg/kdeglobals` `[General] font`, fontconfig prefers it for
  `sans-serif`). Sizes stay derived from the font: `gridUnit` as in M0.2.
- Colours (dark only): text `#f4f3ff`, secondary text 72 %, tertiary 50 %;
  accent gradient `#a594ff` → `#6c7cff` (`Theme.accent`, `Theme.accentEnd`);
  glass tint `#0c0e26` at 0.72 for panels and 0.62 for the taskbar; hairline
  `#1affffff`; fills `#0fffffff`, `#1affffff`, `#26ffffff`. Focus ring stays
  `#ffb400`, 3 px, and every text/background pair keeps the contrast checked
  by `tst_theme.qml` (4.5:1 for text, 3:1 for the ring and indicators).
- Shape: panel radius `1.25 × gridUnit`, taskbar radius `gridUnit`, button
  radius `0.67 × gridUnit`; soft shadows (`MultiEffect`, only with a GPU
  scene graph).
- Motion: panels slide 2 % and fade in over `Theme.durationMedium` (220 ms ×
  `Theme.animationFactor`); hover and press fades `Theme.durationShort`
  (120 ms × factor). The Plasma adapter sets `animationFactor` from the
  platform (`Kirigami.Units.longDuration / 250`, so 0 with reduced motion);
  unit tests set 0.
- Symbols: original 24 × 24 line symbols in `StarOS.Shell/symbols/` (white
  strokes, CC-BY-SA-4.0, under 2 KB each) for the tray, quick settings,
  calendar, widgets and menus; `logo.svg` (the Star OS star) for the Star
  button. App icons stay: Star OS artwork, else the app's theme icon, else a
  monogram.

## 2. Applications catalogue (ADR-0013)

- `StarOS.System` gains `ApplicationsModel` (C++, KService): every
  application KService lists for the current desktop (not `NoDisplay`, not
  hidden, `OnlyShowIn`/`NotShowIn` honoured), sorted by name. Roles:
  `AppName`, `GenericName`, `Comment`, `AppId` (desktop file id with
  `.desktop`), `decoration` (icon name), `Keywords`, `Categories`,
  `Source` (`system`, `flatpak` or `user`), `InstalledAt`, `IsNew`.
- `filter`: case-insensitive; ranked name prefix, word prefix, name
  contains, then generic name, keywords and id. `launch(row)` and
  `launchDesktopId(id)` start the app through `KIO::ApplicationLauncherJob`.
- Live updates: the model watches every `applications` directory of
  `XDG_DATA_HOME`/`XDG_DATA_DIRS` (creating the user's
  `~/.local/share/applications` and, when it is on `XDG_DATA_DIRS`, the
  per-user Flatpak export directory), and after a change runs `kbuildsycoca6`
  and reloads on `KSycoca::databaseChanged`. An app installed from Sun Store
  appears without restarting the session.
- "Recently installed": apps whose desktop file (the link itself for Flatpak
  exports) is under the user's data directory or a Flatpak export directory
  and changed in the last 30 days, newest first. `IsNew` holds for three
  days or until the app is launched once (`~/.local/share/staros/apps.json`).
- `AppCatalogue.qml` (the curated list) is removed. Pinned apps are desktop
  ids in the taskbar plasmoid's configuration; ids the image lacks are left
  out.

## 3. Taskbar

- One glass "pill" centred at the bottom, `0.5 × gridUnit` above the edge;
  the panel window spans the width and its thickness includes the gap and
  room for the shadow (windows maximise above it).
- Contents: Star button (accessible "Applications", description "Open the
  application launcher"); the "Apps" list (pinned launchers and open windows,
  icons only: a dot under running apps, an accent bar under the active
  window; names "<title>" with descriptions "Pinned app", "Window", "Active
  window"); the tray button "Quick settings" (network, volume, battery
  symbols); the clock button "Clock" (time and date; description the full
  date); the notifications button "Notifications" (badge with the unread
  count). The M0.4 "System status" meter moves into quick settings; "Leave"
  moves into the start menu's power menu.
- Keyboard: Meta+Alt+P focuses the Star button; Left/Right move through the
  pill; Return/Space activate; Escape returns focus to the window.

## 4. Start menu (replaces the full-screen launcher)

- A layer-shell overlay over the whole screen with a light dim; the menu panel
  (`37 × gridUnit` wide) sits above the taskbar, centred. Clicking outside or
  Escape closes it; it opens on Meta, Alt+F1 and the Star button.
- Search field "Search applications" (quick answers and `note:` as in M0.4).
  Without search text: "Pinned" (grid of 6 columns), "All apps" button
  (alphabetical list with letter headings), "Recently installed" (up to four,
  each with "NEW" while new, and a "Sun Store" button). With search text: the
  ranked results list; Return launches the first.
- Footer: the live user, then "Lock", "Settings" and "Power" (menu: Log out,
  Restart, Shut down through `org.kde.LogoutPrompt`; Lock through
  `org.freedesktop.ScreenSaver`).

## 5. Quick settings, calendar, notifications (ADR-0014)

- Quick settings panel above the tray button: tiles "Network", "Night
  light", "Do not disturb", "Game mode", "Clipboard", "Star Lens"; sliders
  "Volume" and "Brightness" (brightness only where PowerDevil reports a
  display with adjustable brightness); the storage line ("Live session · 1.9
  GB free" / "Star Storage · …", opens Star Storage); battery when present;
  "Settings" and "Power" buttons.
- Backends in `StarOS.System`: `AudioControl` (PulseAudioQt over
  PipeWire's Pulse server: default sink volume and mute; volume keys with an
  on-screen display), `NetworkStatus` (systemd-networkd and iwd over D-Bus:
  state, wired/Wi-Fi, network name; Wi-Fi list and connect through iwd with a
  passphrase prompt), `DisplayControl` (PowerDevil's
  `org.kde.ScreenBrightness`; night light through `kwinrc` `[NightColor]`
  with KWin's config watcher, `Mode=Constant`), battery from Solid (as in
  M0.4's `SystemStatus`).
- Notifications: the shell becomes the notification server by creating
  libnotificationmanager's `Notifications` model (public QML module
  `org.kde.notificationmanager`). Toasts appear at the top right for
  `Theme.toastTimeout` (5 s, critical ones stay); the notification centre
  lists them above the calendar; "Do not disturb" sets
  `notificationsInhibitedUntil`.
- Calendar: month grid, today highlighted, previous/next month, the full
  date as heading.

## 6. Clipboard history (ADR-0014)

- `ClipboardHistory` in `StarOS.System` (KSystemClipboard,
  `ext_data_control`): keeps the last 20 text and image copies in memory
  (never on disk), and when the clipboard empties because the app that owned
  it closed, offers the last copy again. Meta+V (KGlobalAccel, component
  "staros-shell") opens the clipboard panel above the taskbar; Return copies
  the chosen item back; Delete removes it; "Clear" empties the history.

## 7. Desktop widgets

- The desktop gains a widgets column (top right): Clock, Weather, System
  (processor, memory, storage) and Calendar; each can be removed and added
  back from a "Widgets" button, positions saved in
  `~/.local/share/staros/widgets.json` like the notes.
- Weather (ADR-0015) asks for a city first; only then does it contact
  Open-Meteo (`geocoding-api.open-meteo.com`, `api.open-meteo.com`, no key),
  every 30 minutes while shown. Without network it says so.

## 8. Lock screen and session look (ADR-0016)

- A Star OS look-and-feel package `org.staros.lookandfeel` with
  `lockscreen/LockScreen.qml` (clock, date, blurred wallpaper, the user,
  password field; Return with an empty field unlocks the passwordless live
  user through PAM's `nullok`) and `logout/Logout.qml` (Log out, Restart,
  Shut down, Cancel). `kdeglobals` names it. On the live medium the screen
  never locks by itself (`Autolock=false`), but Lock and Meta+L work.
- `StarOS` colour scheme (`/usr/share/color-schemes/StarOS.colors`) is the
  default for KDE apps and window title bars; the accent matches the shell.

## 9. Game Center and Welcome (ADR-0017)

- `apps/games` (`staros-games`, "Game Center"): games from KService
  (`Categories` containing `Game`) and from Steam's library manifests
  (native and Flatpak Steam), with search, filters (All, Steam, Flatpak,
  Emulators) and "Get games" (Sun Store, Games). Launching uses the app's
  desktop entry or `steam://rungameid/<id>`. "Game mode" starts games through
  Feral GameMode (`gamemoderun`, package `gamemode`) and turns on Do not
  disturb while a game runs.
- `apps/welcome` (`staros-welcome`, "Welcome to Star OS"): five pages (Star OS,
  Star Lens, Star Storage, Sun Store and Game Center, quick answers and
  keyboard), opened once per user by an autostart entry that it disables when
  finished or skipped; in Applications afterwards.

## 10. Accessibility and keyboard

Everything above is reachable by keyboard and named for screen readers; the
focus ring is visible on glass. Reduced motion turns animations off.

## 11. Tests (T0-41..T0-48 in `test-plan.md`)

Unit tests for every new StarOS.Shell view (with fakes) and StarOS.System
class (with temporary XDG directories, fake D-Bus services where needed).
Session tests in QEMU: the floating taskbar and start menu by keyboard; an app
exported into the user's Flatpak directory appears in "Recently installed"
and starts; quick settings volume changes the PipeWire sink volume; a
notification sent over D-Bus shows a toast and is listed; Meta+V shows a copy
made by an app that has since closed; the lock screen locks and unlocks; Game
Center and Welcome open. Not testable in CI: Wi-Fi hardware, brightness,
battery, the weather service, Steam.
