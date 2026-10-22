# Sun Store

The Star OS app store (milestone M0.3,
`docs/architecture/m03-glass-files-store-design.md` section 3, ADR-0010): a
Qt Quick front end for Flatpak apps from [Flathub](https://flathub.org).

- Apps are installed for the current user only (`flatpak --user`); Sun Store
  needs no administrator rights and changes nothing system-wide.
- Flathub is not set up in advance. On first start Sun Store says where apps
  come from ("Sun Store installs apps from Flathub, a community app store.
  Star OS does not review these apps.") and adds the Flathub remote only after
  "Enable Flathub". The remote definition is the `flathub.flatpakrepo` file
  that the package ships in `/usr/share/staros-sunstore/`, downloaded at
  package build time with a pinned checksum.
- Each app page lists what the app may access (from its Flathub metadata)
  before it is installed.
- All work goes through the `flatpak` command line, started without a shell
  and only with app ids that pass a strict check.

The catalogue is Flathub's AppStream data, which flatpak downloads into the
user installation; Sun Store reads it with `QXmlStreamReader` (and KArchive for
the gzip file of older flatpak releases).

The QML module `StarOS.SunStore` is compiled into the binary. The frosted
glass look, icons and focus ring come from `StarOS.Shell`, which the Star OS
ISO installs in Qt's QML directory; builds and tests use the copy in
`shell/qml`.

## Build and test

Needs Qt 6.12, KDE Frameworks 6.31 (KArchive) and ECM; flatpak at run time.

```sh
cmake -B build -S apps/sunstore -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

The tests run headless and offline: the backend tests and the window test use
a fake `flatpak` script (`tests/fakeflatpak.h`), the view test a fake store.
In CI the `packages` job builds the `staros-sunstore` package from
`distro/packages/staros-sunstore/PKGBUILD`, whose `check()` runs the same
tests.
