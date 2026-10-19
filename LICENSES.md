# Licensing

Decided in [ADR-0007](docs/decisions/0007-licensing.md).

| Material | License | Text |
| --- | --- | --- |
| Original Star OS code, scripts, build and CI files | GPL-3.0-or-later | [LICENSE](LICENSE), [LICENSES/GPL-3.0-or-later.txt](LICENSES/GPL-3.0-or-later.txt) |
| Documentation (`docs/`, Markdown files) | CC-BY-SA-4.0 | [LICENSES/CC-BY-SA-4.0.txt](LICENSES/CC-BY-SA-4.0.txt) |
| Artwork, logos, and the Star OS name | Not yet licensed; a separate artwork and trademark policy will be written before any artwork is added | — |

New source files start with an SPDX identifier, for example
`# SPDX-License-Identifier: GPL-3.0-or-later`.

## Third-party components

Star OS ISOs contain Arch Linux packages and other third-party software under
their own licenses. Building or redistributing a Star OS image does not
relicense them. A dependency and license inventory is a Phase 0/1 deliverable.
Until it exists, prototype ISOs are test artifacts only (see
[SECURITY.md](SECURITY.md)).

The ISO's package list is recorded with every build (`packages.x86_64.txt`).
