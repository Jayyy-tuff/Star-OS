# ADR-0014: The Star OS shell provides notifications, quick settings and clipboard history

- Status: Accepted
- Date: 2026-10-25
- Deciders: project owner

## Context

The owner chose quick settings with a tray, clock/calendar/notifications and
clipboard history (2026-10-25). The Star OS session runs plasmashell with the
Star OS shell package but none of Plasma's own applets, so today nothing
receives desktop notifications, volume keys do nothing, and copies vanish
when the app that made them quits (no clipboard manager, noted in ADR-0012).
Plasma's applets for these use private QML APIs (`org.kde.plasma.private.*`),
which ADR-0008 rules out.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Star OS views on public libraries: libnotificationmanager (QML), PulseAudioQt, Solid, systemd-networkd and iwd D-Bus, PowerDevil and KWin D-Bus/config, KSystemClipboard, KGlobalAccel** | Public, documented APIs; one look; testable with fakes | More Star OS code; Wi-Fi through iwd only |
| Embed Plasma's system tray applet | Complete features at once | Private APIs inside; Breeze look; ADR-0008 |
| Switch the image to NetworkManager and plasma-nm | KDE's usual network stack | Replaces releng's networking; larger change than the owner asked for |

## Decision

- Notifications: creating libnotificationmanager's `Notifications` model in
  the taskbar adapter registers `org.freedesktop.Notifications`; Star OS
  draws toasts and the notification centre.
- Audio: add the `pulseaudio-qt` package (LGPL-2.1, KDE); `AudioControl`
  controls the default sink of PipeWire's Pulse server and registers volume
  keys with KGlobalAccel.
- Network: `NetworkStatus` reads systemd-networkd (`org.freedesktop.network1`)
  and iwd (`net.connman.iwd`); Wi-Fi networks are listed and joined through
  iwd with a passphrase agent. The image keeps releng's networkd and iwd.
  iwd's own D-Bus policy lets only root and the `wheel` group talk to it, so
  the live medium adds `/etc/dbus-1/system.d/staros-live-iwd.conf`, which lets
  `liveuser` send to `net.connman.iwd`. The live user already has
  passwordless sudo (ADR-0008), so this grants nothing new; the Phase 2
  installer must not copy the file (`check-image-policy.sh` checks it names
  only `liveuser` and only iwd).
- Display: brightness through PowerDevil's `org.kde.ScreenBrightness`; night
  light by writing `kwinrc` `[NightColor] Active` and `Mode=Constant` with
  KConfig's notify flag (KWin's config watcher applies it).
- Clipboard: `ClipboardHistory` keeps up to 20 copies in memory and offers
  the last one again when its owner disappears; Meta+V opens the history.

## Consequences and trade-offs

- Desktop notifications start working in the Star OS session.
- Copies made in any app survive the app closing, held in plasmashell's
  memory; the history is never written to disk and is lost at logout.
- Wi-Fi works only with iwd-managed adapters; enterprise (802.1X) networks
  are not offered. CI can test none of the Wi-Fi path; the owner's VMware has
  no Wi-Fi either.
- Brightness and battery appear only where the hardware reports them.

## Revisit if

- The installed system (Phase 2) moves to NetworkManager.
- Plasma makes its tray applets' backends public.

## Approval

- Features chosen by the owner on 2026-10-25; backends chosen by the agent.
- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-25, for the
  features; the backend choices await review in the M0.5 report.
