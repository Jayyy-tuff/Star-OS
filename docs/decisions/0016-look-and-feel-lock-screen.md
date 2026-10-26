# ADR-0016: Star OS look and feel: Inter, a dark colour scheme, and a lock screen that works on the live medium

- Status: Accepted
- Date: 2026-10-25
- Deciders: project owner

## Context

The owner asked for a modern, "admirable" look with a deep space dark mood
and a matching lock screen (2026-10-25). Since M0.2 the live medium disabled
locking (`kdeglobals` `action/lock_screen=false`, `Autolock=false`) because
the live user has no password. KDE apps (Settings, Konsole) still use Breeze
Light colours, and the UI font is Noto Sans.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Look-and-feel package with lock and logout screens, a StarOS colour scheme, Inter; manual locking allowed, never automatic** | KDE's supported theming points; apps and title bars match | The lock screen QML uses kscreenlocker's greeter API |
| Keep locking disabled | Nothing can lock the live user out | No lock screen, which the owner asked for |
| Lock automatically after idle | Usual on installed systems | Pointless without a password on the live medium |

## Decision

- `org.staros.lookandfeel` provides `lockscreen/LockScreen.qml` and
  `logout/Logout.qml`; `/etc/xdg/kdeglobals` sets it, the `StarOS` colour
  scheme and the Inter font. Splash stays off (M0.2: nothing hides a startup
  hang).
- The live medium allows manual locking (Meta+L, the start menu's Lock).
  `Autolock` and `LockOnResume` stay false. The live user has an empty
  password, and PAM's `pam_unix nullok` (Arch's `system-auth`) accepts it, so
  Return unlocks; the session test locks and unlocks.
- If the Star OS lock screen QML fails, kscreenlocker's built-in fallback
  takes over (its behaviour), so a broken theme cannot lock the person out.
  That fallback asks for `loginctl unlock-session` from another console;
  the session test uses it only to recover, and fails the step.

### Amendment (2026-10-26, implementation)

- The live user's `kdeglobals` with `action/lock_screen=false` is removed;
  `kscreenlockerrc` keeps `Autolock=false` and `LockOnResume=false`
  (`check-image-policy.sh` checks both).
- `/etc/xdg/kdeglobals` carries the colour groups of
  `/usr/share/color-schemes/StarOS.colors` and `breeze-dark` icons, because
  KDE apps read colours from `kdeglobals`, not from the scheme file.
- The lock screen checks which authenticator methods kscreenlocker offers
  (`startAuthenticating`/`respond`, or `tryUnlock`) instead of assuming
  one, and logs what it found (`STAROS-LOCK ready … api=`). Without a
  password PAM can accept before anything is typed; as in Breeze, the screen
  then waits for Return.
- Plasma 6.7's Breeze package has no `lockscreen/` folder any more
  (kscreenlocker carries its own); kscreenlocker still loads the look's
  `lockscreen/LockScreen.qml` (its `lockscreenmainscript`). `inspect-kde.sh`
  prints where kscreenlocker's own lock screen lives and the authenticator
  names it uses.
- `logout/Logout.qml` follows Breeze's Plasma 6.7 logout screen (the same
  signals; `sdtype`, `maysd`, `canLogout`, `spdMethods` read defensively,
  without Breeze's private `org.kde.plasma.private.sessions` import). Asked
  for one action, it counts down 30 seconds as Breeze does; Power shows every
  choice without a countdown.

## Consequences and trade-offs

- Anyone at the computer can unlock the live session by pressing Return, as
  before locking was possible; the lock screen is a privacy curtain, not a
  security boundary, on the live medium.
- `inter-font` (OFL-1.1) is added to the image.

## Revisit if

- The installed system (Phase 2) has user passwords: automatic locking
  becomes the default there.

## Approval

- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-25, choosing
  "Deep space dark" and "Matching lock screen".
