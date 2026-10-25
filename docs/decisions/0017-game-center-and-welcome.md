# ADR-0017: Game Center lists installed games and runs them with GameMode; Welcome opens once

- Status: Accepted
- Date: 2026-10-25
- Deciders: project owner

## Context

The owner chose a Game Center and a Welcome tour (2026-10-25). Star OS is
meant for gaming; games come from Sun Store (Flatpak) and Steam. Feral
Interactive's GameMode (`gamemode`, BSD-3-Clause, in Arch) is what Steam,
Lutris and Heroic use to request performance settings while a game runs.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Game Center reads desktop entries (Game category) and Steam manifests; Game mode = GameMode + Do not disturb** | No accounts or network; works for Flatpak and Steam; GameMode is the common standard | Covers only what is installed; no store of its own |
| Bundle Steam or Lutris | One-click store | Proprietary (Steam) or a second launcher; large |
| Power profiles daemon for game mode | Simple switch | Not in the image; desktop-wide, not per game |

## Decision

- `staros-games` ("Game Center", C++/Qt Quick per ADR-0009) lists games from
  KService and from `steamapps/appmanifest_*.acf` under the native and the
  Flatpak Steam folders, launches them through their desktop entries or
  `steam://rungameid/<id>`, and links to Sun Store's Games category.
- "Game mode" (off by default): games start through `gamemoderun`; Do not
  disturb is on while a Game Center game runs. Adds `gamemode` to the image.
- `staros-welcome` ("Welcome to Star OS") opens once per user from
  `/etc/xdg/autostart`, remembers that it was shown in
  `~/.config/staros-welcomerc`, and stays in Applications.

## Consequences and trade-offs

- No games are installed by default; Game Center starts with "Get games".
- GameMode changes CPU governor and process priority only while a game runs
  and only through its own polkit rules.
- The live medium shows Welcome at every boot (its home is fresh), unless
  Star Storage keeps the setting.

## Revisit if

- Star OS gets its own game store integration or controller-first mode.

## Approval

- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-25, choosing
  "Game Center" and "Welcome tour"; GameMode awaits review in the M0.5
  report.
