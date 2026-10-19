# ADR-0007: Licensing of original components

- Status: Accepted
- Date: 2026-10-19
- Deciders: project owner

## Context

Star OS must be free and open source. Its original code will sit next to, and
sometimes be loaded by, components with their own licenses: Qt (LGPL-3.0 /
GPL), KDE Frameworks (mostly LGPL), KWin and Plasma (mostly GPL-2.0-or-later),
and Calamares (GPL-3.0-or-later). Exact licenses must be confirmed per
component in the dependency inventory before distribution. This ADR is not
legal advice. If the project expects commercial redistribution or outside
funding, a lawyer should review the final choice.

## Options considered

| Option | Effect | Fit |
| --- | --- | --- |
| **GPL-3.0-or-later** | Strong copyleft: anyone distributing modified Star OS components must publish their source under the same terms. | Compatible with GPL-2.0-or-later KDE code, LGPL Qt/KF, and GPL-3 Calamares. Matches most of the stack. Rules out closed-source forks of the shell. |
| **MPL-2.0** | File-level copyleft: modified Star OS files stay open, but they can be combined with closed code. | Compatible with GPL via MPL's secondary-license clause. A middle ground. |
| **Apache-2.0** or **MIT** | Permissive: anyone may reuse the code, including in closed products. | Simple for contributors and companies. Apache-2.0 includes a patent grant. Apache-2.0 is not compatible with GPL-2.0-**only** code. |

Separate from code:

- **Documentation:** CC BY-SA 4.0 (proposed).
- **Artwork and branding:** licensed separately from code, with a trademark
  policy for the name and logo, so that forks must rebrand. The name has not
  been cleared (see README).
- **Contributions:** Developer Certificate of Origin (`Signed-off-by:` lines)
  instead of a contributor license agreement (proposed in CONTRIBUTING.md).

## Recommendation

**GPL-3.0-or-later** for original code, CC BY-SA 4.0 for documentation, and a
separate artwork/trademark policy. Reasoning: most of the stack Star OS builds
on is already copyleft, and the project goal is a free OS rather than a
reusable proprietary-friendly toolkit. If some Star OS libraries are later
meant for third-party apps, they can be released under LGPL-3.0-or-later.

## Approval

- Chosen: GPL-3.0-or-later for original code, CC-BY-SA-4.0 for documentation, separate artwork/trademark policy (to be written). The DCO sign-off for contributions is still a proposal.
- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-19, in the AI agent session
