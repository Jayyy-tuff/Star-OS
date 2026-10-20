# ADR-0008: M0.2 shell hosting and live session

- Status: Accepted (implementation in progress)
- Date: 2026-10-20
- Deciders: project owner

## Context

ADR-0004 accepted KWin. It chose to **start with option A**: a Star OS shell package loaded by `plasmashell`, with Star OS logic kept in its own QML modules so that option B (a standalone shell process) stays possible. ADR-0004 left two things to milestone M0.2:
- show its six prototype checks on the live ISO;
- decide whether A or B ships in Phase 1.

The live ISO also needs a graphical autologin now, although the display manager is a Phase 1 decision.

Facts that constrain M0.2. They were verified in upstream source at the baseline tags and in CI probes against the pinned 2026-10-15 snapshot.

- **Versions:** KWin, Plasma and libplasma 6.7.5; Qt 6.12.0; KDE Frameworks 6.31.0; Orca 51.1.
- **Window-list permission:** KWin 6.7.5 offers `org_kde_plasma_window_management`, which a window list needs, only to an executable whose installed `.desktop` file lists it.
  - `/usr/bin/plasmashell` already has this grant, and in 6.7.5 it also makes plasmashell privileged for xdg-activation.
  - `KWIN_WAYLAND_NO_PERMISSION_CHECKS` disables the check and also changes how activation is granted, so a test that uses it does not test the real session.
  - KWin 6.8, which is not in the baseline, changes both rules.
- **Shell package selection:** `plasmashell` chooses its shell package from `plasmashellrc [Shell] ShellPackage`, then from `PLASMA_DEFAULT_SHELL`.
  - Files missing from the package fall back to `org.kde.plasma.desktop` (package plasma-desktop).
  - Containments written purely in QML load without compiled code.
  - Plasma Mobile and Bigscreen select their shells this way.
- **App catalogue:** libtaskmanager has no catalogue of installed applications. KDE's own launchers use the private `org.kde.plasma.private.kicker` module, which is not a stable API.
- **Build and test constraints:**
  - The project has no C++ build path yet. A local unsigned package repository would conflict with threat-model item 1 ("pacman signature verification is never disabled").
  - The implementer can only read CI logs; the owner tests in VMware.
  - CI can boot the real ISO in QEMU/KVM and use QMP for keys, mouse and screen dumps. releng already installs `qemu-guest-agent`, and Arch's package starts it through a udev rule when the hypervisor offers its port; this is seen in Arch packaging and must be re-checked at the snapshot.
- **Current live ISO:** it logs in root on the console and enables sshd with password logins. The threat model accepts this for Phase 0 only.

Three complete designs were compared:
- plasma-native: option A with the private kicker catalogue;
- verification-first: option A with public APIs only;
- standalone: option B2.

Two independent reviews (engineering and architecture) both preferred verification-first. This ADR records that design with the reviewers' corrections and additions.

## Options considered

### Shell hosting for M0.2

**A1. Shell package on plasmashell, full catalogue from the private kicker module.**
- Gives a full app list with search and icons from day one, with no compiled code.
- Depends on a private module that has broken third-party code before.
- Needs a policy exception, plus a contract test that itself needs a KActivities stack in CI.

**A2. Shell package on plasmashell, public APIs only.**
- All visible UI lives in a Star OS QML module, `StarOS.Shell`, which imports only QtQuick and QtQuick.Templates.
- A thin Plasma adapter uses `org.kde.taskmanager`, `org.kde.layershell` and `org.kde.kitemmodels`.
- No compiled code, no new Wayland grant, no private module.
- The M0.2 catalogue is a curated list of installed applications.

**B2. Standalone C++/QML shell in its own systemd session.**
- Most UX freedom and the least Plasma leakage. Least-privilege grant through its own desktop file.
- Costs:
  - about 700 lines of C++;
  - a PKGBUILD and makepkg path;
  - a build-time unsigned local repository, which needs an exception to threat-model item 1;
  - gaps it must fill itself: notifications, power management, session management;
  - an estimated 10–14 days.
- Its compositor-level CI evidence would rest on `kwin_wayland --virtual` in a container.

### Live session vehicle

| Vehicle | For | Against |
| --- | --- | --- |
| SDDM autologin | Real wayland logind session | Takes the display-manager decision early; adds a package and a PAM stack |
| getty autologin plus a login-profile hook | No new package | logind records a `tty` session, with unverified effects on portals, Orca and KWin; getty's immediate restart turns logout into a loop |
| System unit without a display manager (KDE's `plasma-mobile.service` pattern) | Real wayland session on seat0; no display manager; `OnFailure` falls back to a login prompt | Not KDE's default desktop path |

The unit approach uses `User=liveuser`, `PAMName=login` and `TTYPath=/dev/tty1`, and passes `XDG_SESSION_TYPE=wayland` to `pam_systemd`.

### Evidence

| Approach | For | Against |
| --- | --- | --- |
| Container KWin (`--virtual`) with the permission bypass or KDE's selenium runner | Fast | The bypass hides the grant M0.2 must prove; on 6.7.5 it renders through QPainter |
| The real CI-built ISO in QEMU, observed only from outside (serial port, QMP, guest agent) | No bypass; nothing test-specific in the image | Slower |
| Owner only | No CI work | No automated evidence |

## Decision

### 1. Option A2 for M0.2

M0.2 builds and measures **option A2**.

An unmodified `/usr/bin/plasmashell` loads three original packages:
- the Plasma/Shell package `org.staros.shell`;
- the pure-QML Panel containment `org.staros.taskbar`, which is the Plasma adapter;
- the pure-QML Desktop containment `org.staros.desktop`.

The session sets `PLASMA_DEFAULT_SHELL=org.staros.shell` and runs `startplasma-wayland`. Keyboard entry points are Plasma's built-in shortcuts:
- Meta or Alt+F1 opens the launcher, because the taskbar containment provides `org.kde.plasma.launchermenu`;
- Meta+Alt+P focuses the taskbar.

### 2. Catalogue

The catalogue is a curated public-API list: TasksModel launchers for Konsole, System Settings and one more installed, visible application confirmed in CI.
- It has a search field.
- It sits behind a four-member interface: `model`, `count`, `filter`, `launch(row)`.
- No `org.kde.plasma.private` import is allowed anywhere; CI enforces this.

### 3. Live session

- The session vehicle is the display-manager-less system unit. The display manager stays a Phase 1 decision; `staros.desktop` is shipped for it.
- An unprivileged `liveuser` has an empty password, passwordless sudo and no supplementary groups.
- root is locked. releng's root autologin and sshd are removed.
- Screen locking is disabled for the live user, so the user cannot be locked out.
- Live-only files live in `/etc` and `/home/liveuser`, never in `/etc/skel`.

### 4. Evidence

The real ISO in QEMU/KVM is the authority.
- A read-only report service writes session facts, idle RAM/CPU and stability to the serial port and the journal. It works without the guest agent and gives the owner the same numbers in VMware.
- A QMP and guest-agent harness checks keyboard use, the window list, AT-SPI, Orca's debug output and scaling. It has an independent KWin-script oracle for the active window.
- A container probe without any bypass gives fast feedback only.
- No permission-bypass variable is set in the image or in any CI step that runs the shell. One list file drives a repository-wide check and an image check.
- Pixel, mouse and Orca checks start informational. A reviewed commit promotes them after three consecutive green runs.

### 5. Decision rule for ADR-0004 (applied after the owner's VMware run)

- **Keep A for Phase 1** if checks 1–5 pass in CI and in VMware without patching Plasma or KWin.
- **Prototype B** if a check fails because of plasmashell itself, or if the owner judges the measured idle cost unacceptable. plasmashell's PSS is reported separately for this purpose.

## Consequences and trade-offs

**Gained**
- M0.2 needs no compiled code, no new grant and no package-signing exception. The build stays a file copy, and the image is identical in CI and VMware.

**C++ later**
- "No C++" is an M0.2 property only. A full catalogue in Phase 1 needs either a Star OS C++ model over KService plus a C++ build path, or a recorded exception for kicker.
- If Phase 1 adds a C++ build path anyway, B's main extra cost shrinks. The ADR-0004 decision must weigh this.

**Only A is measured**
- B's idle cost is unknown. plasmashell's PSS is an upper bound on what B could save, before subtracting B's own Qt Quick runtime.

**Plasma surfaces stay reachable** (nothing proprietary is copied; an inventory goes into ADR-0004):
- the logout greeter, from the Breeze Look-and-Feel package;
- the Plasma lock screen and activity switcher, from the fallback package;
- KWin's Alt+Tab and Overview.

**Package and session gaps**
- plasma-desktop is a required package, because it provides the fallback shell package and kaccess. The image grows; the exact size is recorded per build.
- The Star OS shell has no notification server yet; this is a documented gap.

**Live medium**
- The threat model's accepted risk changes from root console autologin to the live-user posture.
- The Phase 2 installer must never copy the live-only files.
- The image keeps releng's qemu-guest-agent. It starts only when a hypervisor offers its port, which is the same class of capability as releng's enabled VMware tools.

**Upgrades**
- Moving the baseline to Plasma/KWin 6.8 changes the grant and activation rules and moves the screen-reader toggle. Every M0.2 check and the owner run are repeated on any baseline bump.

## Revisit if

- Any of checks 1–5 cannot pass without patching Plasma or KWin, or fails because of plasmashell itself. Then prototype option B.
- The owner judges the measured idle RAM or CPU unacceptable for the minimum reference machine.
- The display-manager-less unit cannot give a working wayland session in VMware. Then use SDDM autologin as the live vehicle and record it.
- Arch no longer ships the guest agent's udev rule and the owner declines adding one. Then checks 2–5 become owner-only.
- The package baseline moves to Plasma/KWin 6.8 or later.
- Phase 1 needs a C++ build path for the catalogue or other components. Then re-weigh B.

## Approval

- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-20, in the AI agent session. The owner chose, in order: the passwordless `liveuser` posture (live medium only, root locked, root autologin and sshd removed); the curated M0.2 catalogue with the full catalogue deferred to Phase 1; the QEMU guest-agent test channel (including an identical udev rule in the overlay if Arch no longer ships one); and the decision rule "prototype option B only if option A fails a check or its idle cost is unacceptable".
- How the design was produced: three independent designs, two independent reviews and a synthesis, all checked against upstream source at the baseline tags; see [the M0.2 design specification](../architecture/m02-shell-prototype-design.md).

