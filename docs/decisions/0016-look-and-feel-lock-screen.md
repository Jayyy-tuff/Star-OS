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
