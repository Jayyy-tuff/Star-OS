# ADR-0013: The launcher lists every installed application, live, from KService

- Status: Accepted
- Date: 2026-10-25
- Deciders: project owner

## Context

Since M0.2 the launcher showed a curated list of desktop ids
(`AppCatalogue.qml`, 13 in M0.4) through libtaskmanager's launcher rows. The
owner reported that apps installed from Sun Store do not appear: "When you
install an app it should show up in Applications section." Flatpak exports
desktop files into `~/.local/share/flatpak/exports/share/applications`
(per user, ADR-0010), which is on `XDG_DATA_DIRS` through Flatpak's systemd
environment generator. KService's database (KSycoca) only rebuilds when a
caller checks it and a directory that existed at the last build is newer;
a directory created later is not noticed.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Star OS `ApplicationsModel` in StarOS.System on KService, with its own directory watch and `kbuildsycoca6`** | Public KF6 API; every installed app; we control ranking, "Recently installed" and testing | One more C++ class to maintain |
| Plasma's kicker backend (`org.kde.plasma.private.kicker`) | Ready-made menus and favourites | Private API, forbidden since ADR-0008 |
| Keep the curated list and add Flatpak ids from Sun Store | Small | Misses apps installed any other way |

## Decision

`ApplicationsModel` (see the M0.5 design contract, section 2) replaces
`AppCatalogue.qml`. It lists KService applications for the current desktop,
watches every `applications` directory on the data paths (creating the
user's own and the per-user Flatpak export directory when that is on
`XDG_DATA_DIRS`), runs `kbuildsycoca6` after a change and reloads on
`KSycoca::databaseChanged`. Apps start through `KIO::ApplicationLauncherJob`.
"Recently installed" lists apps under the user's data directory or a Flatpak
export directory changed in the last 30 days.

## Consequences and trade-offs

- The launcher shows more than the curated set (every app the image and the
  person installed); the image policy no longer fails when a curated id is
  renamed, but pinned ids that are missing are left out quietly.
- The session tests now find apps by typing, not by a fixed list.
- `staros-system` depends on KService, KIO and KConfig.

## Revisit if

- Plasma publishes a public application model.
- Categories or folders are wanted in the start menu.

## Approval

- Requested by the owner on 2026-10-25 ("When you install an app it should show
  up in Applications section"); the implementation choice is the agent's,
  recorded here for review.
- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-25, for the
  behaviour; the implementation awaits review in the M0.5 report.
