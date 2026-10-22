# ADR-0010: Sun Store installs Flatpak apps from Flathub, per user, after consent

- Status: Accepted
- Date: 2026-10-22
- Deciders: project owner

## Context

The owner asked for an app store named Sun Store, "using flatpak or something
similar". Star OS has no application repository of its own, and Arch's
packages need root to install. A store must make clear where apps come from,
must not grant itself root, and must work on the live medium.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Flatpak, user installation, Flathub added after consent** | No root or Polkit needed; apps are sandboxed and show their permissions; Flathub is the largest Flatpak catalogue | Flathub apps are not reviewed by Star OS; downloads are large; on the live medium they live in RAM |
| Flatpak, system installation | Shared between users | Needs Polkit rules and root-owned changes; more attack surface |
| pacman front end | Native packages | Root for every install; partial upgrades can break the system |
| Flathub preconfigured | One less step | Adds a third-party source before the person has been told about it |

## Decision

- Sun Store drives the `flatpak` command line (asynchronous `QProcess`, never
  through a shell, standard input closed), always with `--user`. Commands:
  `remotes`, `remote-add --if-not-exists flathub <file>`, `update --appstream
  flathub`, `list --app`, `remote-ls --updates --app`, `remote-info
  --show-metadata`, `install --noninteractive -y flathub <id>`, `uninstall
  --noninteractive -y <id>`, `update --noninteractive -y`, and `run <id>`
  (detached). App ids must match a strict reverse-DNS pattern before they are
  passed; anything else is refused without starting flatpak.
- No Flatpak remote exists in the image. Arch's `flatpak` package ships
  Flathub as a static system-wide remote
  (`/usr/share/flatpak/remotes.d/flathub.flatpakrepo`; found by the image
  policy check in CI run 16), so the ISO build does not extract that file
  (`NoExtract` in the build-time pacman configuration). On first start Sun Store shows:
  "Sun Store installs apps from Flathub, a community app store. Star OS does
  not review these apps." with "Enable Flathub" and "Not now". Only "Enable
  Flathub" adds the remote, for the current user. "Not now" closes Sun Store
  and changes nothing.
- The remote definition is Flathub's `flathub.flatpakrepo` (URL, title and
  signing key), downloaded when the package is built, with a pinned sha256,
  and shipped at `/usr/share/staros-sunstore/flathub.flatpakrepo`. Flatpak
  verifies Flathub's signatures with that key. The pinned file (CI run 13,
  2026-10-22) carries "Flathub Repo Signing Key <flathub@flathub.org>",
  primary key fingerprint `6E5C 05D9 79C7 6DAF 93C0 8135 4184 DD4D 907A 7CAE`.
- Each app page lists the app's static permissions (network, display,
  devices, file system, bus names) from its Flathub metadata before install.
- The catalogue is Flathub's AppStream data in the user installation, read
  with `QXmlStreamReader`.
- The live medium's copy-on-write space is raised to half the RAM
  (`cow_spacesize=50%`) so that apps fit; the space is used only when
  written.

## Consequences and trade-offs

- People can install software Star OS has not reviewed. The consent text says
  so, and the sandbox and permission list limit and expose what an app may do.
  Flatpak's static permissions are not a complete security boundary (for
  example X11 or full home access); the permission list names those plainly.
- On the live medium installed apps disappear at shutdown and consume RAM.
- Leaving out a file of the `flatpak` package means `pacman -Qk flatpak`
  reports it missing on the live image. An installed system (Phase 2) needs
  the same rule in its own `/etc/pacman.conf`, or the file returns with the
  next flatpak update.
- Parsing flatpak's text output ties Sun Store to flatpak's table format
  (tab-separated without a terminal, checked against flatpak 1.18.4). A
  libflatpak backend would avoid that; it is a later option.
- CI has no network in the VM, so the session test checks the consent screen
  and that no remote was added; installing from Flathub is an owner test.

## Revisit if

- Star OS gets its own reviewed app repository or curated Flathub subset.
- flatpak's output format changes (the parser tests use recorded output).

## Approval

- Chosen in the AI agent session on 2026-10-22: "Per user, Flathub
  (Recommended)".
- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-22.
