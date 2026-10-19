# Contributing to Star OS (draft)

> Draft. Contributions are accepted under GPL-3.0-or-later (code) and
> CC-BY-SA-4.0 (documentation); see [LICENSES.md](LICENSES.md).

## How work is done

1. Read the relevant docs and ADRs before changing anything.
2. Propose a small, focused change. For anything architectural,
   security-sensitive, licensing-related, or destructive (installer, disks,
   updates), open an issue or ADR first and wait for approval.
3. Implement the change with tests.
4. Report the exact test commands you ran and their real results in the pull
   request. If something was not tested, say so.
5. Merge only after review and green CI.

## Rules

- Do not claim something boots, installs, works on hardware, or is secure
  without a recorded test.
- Never run destructive tests against a real disk.
- No privileged operation built from shell strings or untrusted input. Privileged
  code validates its own inputs.
- Do not swap a dependency for another one silently. Explain why and get
  approval.
- Keep source files focused. No hidden dependencies.
- GitHub Actions are pinned to full commit SHAs.

## Sign-off (proposed)

Each commit carries a `Signed-off-by:` line under the
[Developer Certificate of Origin](https://developercertificate.org/)
(`git commit -s`).

## Code of conduct

Not yet adopted. Needs an owner decision.
