# Initial threat model

Status: draft (Phase 0). This model will be revisited at each phase gate and for
every new privileged component.

## Assets

| Asset | Why it matters |
| --- | --- |
| User files and personal data | Loss or disclosure harms users directly |
| Credentials, tokens, Wi-Fi keys | Account takeover, network access |
| Disk-encryption passphrases and recovery keys | Lockout if lost; disclosure defeats encryption |
| Integrity of the installed system | A tampered system can do anything |
| Star OS package and release signing keys | Compromise lets an attacker ship updates to every user |
| Build and CI infrastructure | Compromise lets an attacker tamper with ISOs and packages |
| Users' disks during installation | The installer can destroy data |

## Adversaries and failure sources

1. Network attacker (public Wi-Fi, hostile mirror, DNS manipulation).
2. Compromised or malicious upstream package or dependency.
3. Malicious or buggy local application running as the user.
4. Physical attacker with a lost or stolen device.
5. Malicious contribution (pull request) or compromised maintainer account.
6. Compromised CI runner or third-party CI action.
7. **Our own bugs**, especially in the installer, updater, and privileged
   services. For data loss, this is the most likely source.

## Trust boundaries

```
[User apps] --D-Bus--> [Star OS user services] --D-Bus + Polkit--> [privileged services] --> [system]
[Mirrors / Star OS repo] --signed packages--> [pacman] --> [system]
[Git repo] --> [CI build] --> [ISO + checksums/signatures] --> [user download]
[Installer UI (root in live session)] --> [partitioning / encryption / bootloader] --> [user disks]
```

## Key threats and planned mitigations

| # | Threat | Planned mitigation | Phase |
| --- | --- | --- | --- |
| 1 | Tampered packages from a mirror | pacman signature verification is never disabled; `archlinux-keyring` stays current; Star OS repository signed with documented key rotation | 0 (policy), 4 (Star OS repo) |
| 2 | Tampered ISO download | Published SHA-256 checksums, then signed checksums before any public release | 0 (checksums), 7 (signing) |
| 3 | GUI tricks a privileged service | Privileged services validate every input themselves and authorize per action through Polkit; no shell-string construction; no implicit elevation | 1+ |
| 4 | Installer erases the wrong disk | Explicit target selection; destructive confirmation naming the disk (model, size, partitions); release-blocking multi-disk tests (ADR-0005) | 2 |
| 5 | Encryption lockout | Recovery-key explanation **before** formatting; tested unlock and recovery procedure; honest limits | 2 |
| 6 | Unsafe update leaves the system unbootable | Pre-update snapshot verified before risky updates; low-space and conflict checks; documented recovery (ADR-0006) | 2, 4 |
| 7 | Compromised CI or third-party actions | Pin actions to commit SHAs; minimal workflow permissions; no secrets for fork PRs; no release-signing keys on hosted runners | 0 |
| 8 | Malicious pull request | Mandatory review for `distro/`, `scripts/`, `.github/`, and privileged services; CODEOWNERS once the team exists | 0 |
| 9 | Secrets in logs or diagnostic bundles | Redaction rules, opt-in diagnostics with a preview of contents, secrets only in system credential stores | 1+ |
| 10 | Theme/preset import runs code | Presets are data only, validated against a schema; never executed | 5 |
| 11 | Lost device | Full-disk encryption recommended at install | 2 |
| 12 | A Flathub app is malicious or vulnerable | Sun Store adds Flathub only after the person reads "Star OS does not review these apps" and chooses "Enable Flathub"; apps install per user (no root, no Polkit); each app's permissions are listed before install; Flatpak's sandbox; no system-wide remote in the image: the static Flathub remote that Arch's flatpak package ships is not extracted, and the image policy check fails if any system remote exists (ADR-0010) | 0 (M0.3) |
| 13 | Tampered Flatpak downloads or remote definition | flatpak verifies Flathub's signed commits with the key in `flathub.flatpakrepo`; that file's sha256 is pinned in the PKGBUILD; HTTPS | 0 (M0.3) |
| 14 | Argument or path injection into `flatpak` | Argument lists through `QProcess`, never a shell; app ids must match a strict reverse-DNS pattern (no leading `-`, no `/`, no spaces) or nothing runs; standard input closed | 0 (M0.3) |
| 15 | The file manager destroys data or runs untrusted files | Delete moves to the Trash; permanent deletion and emptying the Trash ask first, with Cancel focused; Files never starts programs (executables are refused, scripts and desktop entries open as text); it runs as the user only | 0 (M0.3) |
| 16 | Unsigned Star OS packages | The `[staros]` repository is a local directory used during one CI build only; the image's pacman configuration does not list it (image policy); a signed repository is Phase 4 (threat #1) | 0 (M0.3) |
| 17 | Star Storage erases the wrong disk | The person types the disk's exact name; the warning lists its partitions; the helper re-reads `lsblk` as root and refuses the Star OS medium (iso9660 or the ISO's UUID), disks with a mounted partition, read-only disks, disks under 8 GiB, names outside `sd*`, `vd*`, `xvd*`, `nvme*n*`, `mmcblk*`, a mismatched confirmation and a second `STAROS_DATA` disk; unit tests cover every refusal and the exact commands; CI uses a scratch image only (ADR-0011) | 0 (M0.4) |
| 18 | The Star Storage helper is abused for root | pkexec runs only `/usr/lib/staros/staros-storage-helper` under `org.staros.storage.manage` (`exec.path` annotation, `auth_admin_keep`); the helper takes three fixed commands, validates every argument, runs tools from `/usr/bin` without a shell and with a fixed environment; the live-only polkit rule matches that action and `liveuser` only (image policy) | 0 (M0.4) |
| 19 | Screen contents leak through Star Lens | Screenshots only through KWin's packaged grant to `/usr/bin/staros-lens` (no permission bypass); recognition is offline; links open only if recognised and http(s); Google Lens is opened only after a warning every time, and the person uploads the image themselves (ADR-0012) | 0 (M0.4) |

## Accepted risks in Phase 0

- **Live medium: passwordless `liveuser` with autologin and `NOPASSWD` sudo**
  (M0.2, ADR-0008). `staros-live-session.service` logs `liveuser` (UID 1000,
  no supplementary groups, not in `wheel`) into the graphical session on tty1;
  `/etc/sudoers.d/10-staros-live` lets it run any command as root without a
  password. Root is locked, releng's root console autologin is removed, and
  sshd is masked with no wants link. Screen locking is disabled for this user
  (kiosk `action/lock_screen=false`), so an empty password can never lock the
  owner out. Anyone with access to a running live session has root; that is
  acceptable for a test medium that holds no user data. `check-image-policy.sh`
  verifies this posture on every build (test T0-26).
- **Installer requirement (Phase 2).** The installer must never copy these
  live-only files to an installed system: `/etc/sudoers.d/10-staros-live`,
  `staros-live-session.service` and the `display-manager.service` link, the
  sshd mask, the overlay's `/etc/passwd`, `shadow`, `group` and `gshadow`,
  `/home/liveuser`, and the diagnostics units (`staros-boot-check`,
  `staros-session-report`).
- **Prototype diagnostics run as root.** `staros-session-report` runs as root
  for about 10 minutes after the session starts. It only reads (`/proc`,
  `loginctl`, `systemctl`, the journal, read-only queries on the live user's
  session bus, plus a Plasma script that prints the layout) and writes to the
  journal and the serial port. Phase 1 removes it or makes it opt-in.
- **QEMU guest agent.** releng installs `qemu-guest-agent`, and Arch's package
  starts it through a udev rule when the hypervisor offers its virtio port
  (checked at the 2026-10-15 snapshot). A hypervisor that offers the port can
  run commands as root in the guest; this is the same class of access as
  releng's already-enabled VMware tools, and the hypervisor controls the VM
  anyway. The owner approved using this channel for CI tests (ADR-0008).
- **No CI-only bypasses.** The image, the shell sources and the CI steps that
  run the shell never set KWin's Wayland permission-check bypasses, forced Qt
  accessibility, or a forced compositing backend
  (`scripts/ci/forbidden-env.txt`). The taskbar gets the window list only
  through plasmashell's packaged grant. Checked in the repository, in the
  built image, and in the running session's KWin and plasmashell environment.
- **Flathub apps are not reviewed by Star OS** (M0.3, ADR-0010). Sun Store
  says so before Flathub is added. Flatpak's static permissions are not a
  complete boundary: an app with X11 access can read other X11 windows'
  input, and one with home or host file access can read and change the
  person's files. Sun Store lists such permissions in plain words; it does not
  block them. On the live medium installed apps live in RAM and disappear at
  shutdown.
- **Star Storage on the live medium** (M0.4, ADR-0011). The polkit rule
  `/etc/polkit-1/rules.d/49-staros-live-storage.rules` lets `liveuser` run
  the Star Storage helper without a password, as its sudo rule already does
  for everything; the installer must not copy the rule. The Star Storage disk
  is plain ext4: anyone holding it can read the kept files, settings and
  Flatpak apps. Persistence keeps everything written to the overlay, including
  logs and caches. Pending owner review of the rule.
- **Star Lens keeps running after a copy** until something else is copied,
  so the copy survives without a clipboard manager (ADR-0012). "Search the
  web" sends the recognised text to Google when pressed.
- **No Secure Boot.** Users must disable Secure Boot to boot prototypes
  (ADR-0006).
- **Prototype ISOs are unsigned.** CI artifacts are for testing only and must
  not be called official builds.

Upstream observation for later phases: KWin 6.7.5's EIS remote-desktop D-Bus
method does not check its caller (threat #3 class); revisit before Star OS
ships its own privileged session services.

## Open questions

- Who holds the package and release signing keys, and on what hardware?
- Will the project apply for Microsoft-signed shim (ADR-0006)?
- The browser: Firefox from the pinned Arch snapshot is preinstalled since
  M0.4 and is the default for links (Moon Browser stays reserved for the
  owner). Its updates follow the snapshot, so a live ISO's Firefox ages with
  the ISO; the update process is a Phase 4 question.
