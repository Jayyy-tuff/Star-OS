# ADR-0004: Wayland compositor and shell foundation

- Status: Proposed
- Date: 2026-10-19
- Deciders: pending owner approval

## Context

Star OS needs an original desktop shell (taskbar, launcher, notifications,
gaming mode) written in Qt Quick / QML, running on a mature Wayland compositor.
The specification forbids writing a new display server and requires
evaluating stability, Qt/QML fit, window management, input, scaling and
multi-monitor, accessibility, GPU acceleration, security boundaries, power
management, compatibility with existing apps, and how feasible the original
design is.

Facts below come from upstream documentation and project history as known on
the date above. Items marked *(verify)* must be confirmed in the Phase 0b
prototype before the decision is accepted.

## Options considered

### A. KWin, with the Star OS shell loaded as a Plasma shell package

KWin is KDE's compositor. `plasmashell` can load alternative **shell
packages**; Plasma Mobile and Plasma Bigscreen are distinct user experiences
built this way on KWin.

- Mature Wayland support: fractional scaling, multi-monitor, VRR, HDR, tearing
  control for games, direct scanout, Xwayland, virtual desktops, screen
  locking, input methods.
- Qt-native: Star OS QML can use Plasma's existing models (task manager,
  notifications, search) instead of re-implementing them.
- Risk: Plasma's look and conventions can leak into Star OS, and a major Plasma
  release can break shell packages (Plasma 5 → 6 did). This is controlled by the
  package baseline (ADR-0002) and tests.

### B. KWin, with a standalone Star OS shell process

Same compositor. The shell is our own Qt application that uses
`layer-shell-qt` for panels and overlays, and KWin's restricted Wayland
interfaces (window management) where KWin grants them to trusted shell
clients *(verify the mechanism and which interfaces are needed)*.

- More independence from Plasma's shell code and theming.
- Costs more glue work (window list, struts, multi-monitor panel placement,
  notifications server, polkit agent). Running KWin without `plasmashell` is
  not a configuration KDE documents for end users *(verify)*.

### C. labwc (wlroots) with a standalone Star OS QML shell

labwc is a lightweight stacking compositor built on wlroots, used by Raspberry
Pi OS and offered by LXQt.

- Small and simple. The shell is fully ours through `layer-shell-qt` and the
  wlr foreign-toplevel protocol.
- Accessibility (zoom, focus tracking for screen readers), HDR/colour
  management, and gaming features such as tearing control and VRR are less
  developed than in KWin *(verify against current releases)*. Star OS would
  integrate many more separate pieces itself.

### D. Treeland (deepin)

A Qt/QML compositor built on wlroots, developed for deepin's DDE.

- The closest technical match ("compositor in QML"), but young, mainly
  maintained for one distribution, and with a small outside user base. High
  maintenance risk for us.

### E. Custom compositor on Qt Wayland Compositor

Qt's module for writing compositors in QML.

- Aimed mostly at embedded and kiosk use. Desktop features (Xwayland, many
  modern protocols, direct scanout for games) would be ours to build — in
  effect a new display server, which the specification rules out.
- The module's licensing differs from Qt's LGPL core modules *(verify)*.
- Earlier desktop projects built this way struggled to reach maturity.

### F. Hyprland or niri, with Quickshell

Popular with enthusiasts. Quickshell is a QtQuick toolkit for building shells.

- Fast-moving and configuration-centric. Hard to commit to a stable,
  beginner-oriented release baseline. Hyprland's renderer is no longer
  wlroots-based, which reduces the shared-maintenance benefit.

### G. GNOME Shell / Mutter

Excluded: the shell is JavaScript/Clutter, not Qt/QML.

### Gaming mode note

Gamescope (Valve's micro-compositor) is **not** a desktop compositor. It is
evaluated in Phase 6 as an optional per-game wrapper and as a possible
dedicated gaming session. The initial gaming-mode design is a full-screen Star
OS QML surface inside the same compositor session. That keeps switching fast
(spec target: about 3 s) and avoids a logout.

## Comparison summary

| Criterion | A KWin + shell pkg | B KWin standalone | C labwc | D Treeland | E Qt WC |
| --- | --- | --- | --- | --- | --- |
| Maturity / maintenance | High | High (compositor) / ours (shell) | Medium-high | Low-medium | Ours |
| Qt/QML fit | Native | Native | Client-side only | Native | Native |
| Gaming features (VRR, tearing, HDR) | Strong | Strong | Weaker *(verify)* | Unknown | Ours to build |
| Accessibility | Strongest available | Strong (compositor side) | Weaker | Unknown | Ours to build |
| Original UX freedom | Good | Best | Best | Good | Best |
| Integration work for Star OS | Lowest | Medium | High | Medium | Very high |
| Idle resource cost | Highest *(measure)* | High *(measure)* | Lowest | Unknown | Unknown |

## Decision (proposed)

**Use KWin as the compositor.** Start with **option A** (Star OS shell
package on `plasmashell`), keeping Star OS logic in its own QML modules and
services so that a move to **option B** stays possible.

Whether A or B ships in Phase 1 is decided by the **Phase 0b shell prototype**,
which must show on the live ISO:

1. A Star OS taskbar and full-screen launcher, written in original QML, that
   start and stay up on KWin.
2. Launching, listing, and switching windows from the taskbar.
3. Full keyboard-only operation with visible focus.
4. Orca reading launcher entries *(screen-reader path to verify)*.
5. Correct layout at 100%, 150%, and 200% scaling.
6. Measured idle RAM and CPU of the session, recorded as the first data point
   for the idle-memory budget.

The display manager is decided in Phase 1. SDDM supports QML login themes.
Plasma's newer Plasma Login Manager reportedly offers less theming *(verify)*.

## Consequences and trade-offs

- Star OS depends on Qt 6, KDE Frameworks, and KWin release cadence; Plasma
  updates must pass Star OS tests before a baseline moves.
- The idle memory footprint will be higher than a wlroots-based design. It must
  be measured, not assumed, and the budget set from measurements.
- KWin is GPL-2.0-or-later licensed (*verify per file*). Star OS talks to it
  over Wayland and D-Bus. A shell package is loaded by GPL/LGPL Plasma code,
  which has licensing implications for ADR-0007.

## Revisit if

- The Phase 0b prototype cannot meet criteria 1–5 without patching KWin or Plasma.
- Measured idle resource use is unacceptable on the minimum reference machine.
- KDE changes the shell-package or restricted-interface mechanisms in a way
  that blocks an original shell.

## Approval

- Approved by: pending
