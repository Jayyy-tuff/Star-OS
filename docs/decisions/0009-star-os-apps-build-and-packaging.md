# ADR-0009: Star OS applications: C++/Qt Quick, built as pacman packages

- Status: Accepted
- Date: 2026-10-22
- Deciders: project owner

## Context

Milestone M0.3 adds the first Star OS applications, a file manager (Files) and
an app store (Sun Store). They need a language and toolkit, a way into the
live image, and a place in CI where they are built and tested before an ISO is
made. Until now the image only received files copied by `build-iso.sh` (the
shell in `shell/`), which is enough for QML but not for compiled programs.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **C++ backend, Qt Quick (QML) UI, pacman packages** | Same toolkit as the shell (ADR-0004, ADR-0008); KIO and KDE Frameworks give a mature file layer; packages have owners, versions and a manifest entry; `makepkg check()` runs the tests on the build host | A package build stage in CI; Star OS packages are unsigned for now |
| Python with PySide 6 | Faster to write | Another runtime in the image; no KIO bindings; harder to keep the shell's look |
| Copy built binaries into the overlay | No packaging work | Files no package owns; nothing records versions; breaks the image policy's "overlay files unowned" model for binaries |

## Decision

- Applications are C++20 with a Qt Quick UI. Each QML module is compiled into
  its binary (`qt_add_qml_module`, static library). The look (frosted glass,
  icons, focus ring) comes from `StarOS.Shell`, imported at run time from the
  image's shell tree.
- Each application has a PKGBUILD in `distro/packages/<name>/` with a fixed
  version (`0.3.0-1`), bumped in reviewed changes so the package manifest
  stays stable between commits. The source is a tarball of the checked-out
  tree (`star-os-src.tar.gz`, checksum `SKIP` because it is made from the
  checkout itself); any downloaded source has a pinned checksum.
- `scripts/build-packages.sh OUTDIR` builds every PKGBUILD in a disposable,
  pinned Arch container: dependencies are installed by pacman as root,
  `makepkg --check` runs as the unprivileged user `builder`, and `repo-add`
  makes the repository `staros`.
- `scripts/build-iso.sh` reads that repository from `STAROS_LOCAL_REPO` and
  adds `[staros]` (`SigLevel = Optional TrustAll`, `Server = file://…`) to the
  profile's `pacman.conf` only. The image's `/etc/pacman.conf` is the pacman
  package's and does not list it; the image policy checks this.
- CI gains the job `packages` (after `lint`, before `build`). It uploads the
  repository and the test logs.

## Consequences and trade-offs

- Packages are unsigned. That is acceptable only because the repository
  exists for the length of one CI build, as a local directory, and never
  reaches users. A signed Star OS repository is Phase 4 work (threat #1).
- The applications depend on `StarOS.Shell`, which no package owns yet; the
  shell becomes a package when the first installed system needs it.
- Building in CI adds about one compile of each application per run.

## Revisit if

- Applications must be installable or updatable outside the ISO (needs a
  signed repository).
- A dependency is not in the pinned Arch snapshot.

## Approval

- Chosen in the AI agent session on 2026-10-22: "C++/QML, pacman pkgs
  (Recommended)".
- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-22.
