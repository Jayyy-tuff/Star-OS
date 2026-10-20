#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Checks the built live image's root file system against the M0.2 policy
# (ADR-0008, docs/security/threat-model.md): no CI-only bypass variables, the
# least-privilege live user, live-only login and service settings, the Star OS
# shell files, and overlay files that no package owns (or that are backup files
# of their package). Prints one POLICY line per check and fails on any FAIL.
#
# Usage: scripts/ci/check-image-policy.sh AIROOTFS [REPORT]
#   AIROOTFS  mkarchiso's work/x86_64/airootfs
#   REPORT    file that receives the POLICY lines (default: none)
# Needs root (it reads /etc/shadow of the image), pacman, visudo and
# desktop-file-validate.

set -euo pipefail
# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

[[ $# -ge 1 && $# -le 2 ]] || die "usage: $0 AIROOTFS [REPORT]"
root=$(realpath -- "$1")
report=${2:-/dev/null}
[[ -d $root/etc && -d $root/usr ]] || die "$root does not look like a root file system"
overlay="$staros_repo_root/distro/archiso/staros/airootfs"
forbidden_list="$staros_repo_root/scripts/ci/forbidden-env.txt"
failures=0
: >"$report"

result() {
    local status=$1
    shift
    printf 'POLICY %s %s\n' "$status" "$*" | tee -a "$report"
    [[ $status != FAIL ]] || failures=$((failures + 1))
}

check() {
    local name=$1
    shift
    if "$@"; then result PASS "$name"; else result FAIL "$name"; fi
}

# Shell file trees installed by build-iso.sh, relative to the root.
shell_paths=(
    usr/lib/qt6/qml/StarOS
    usr/share/plasma/shells/org.staros.shell
    usr/share/plasma/plasmoids/org.staros.taskbar
    usr/share/plasma/plasmoids/org.staros.desktop
)

no_forbidden_env() {
    local -a names args=() paths=()
    local hits path
    mapfile -t names < <(grep -vE '^[[:space:]]*(#|$)' "$forbidden_list")
    ((${#names[@]} > 0)) || return 1
    for path in "${names[@]}"; do args+=(-e "$path"); done
    for path in etc usr/local home "${shell_paths[@]}" usr/share/wayland-sessions/staros.desktop; do
        [[ -e $root/$path ]] && paths+=("$root/$path")
    done
    hits=$(grep -rIlwF "${args[@]}" -- "${paths[@]}" 2>/dev/null || true)
    [[ -z $hits ]] || { printf '    %s\n' "${hits//"$root"/}"; return 1; }
}

no_shell_package_override() {
    local file
    for file in "$root/etc/xdg/plasmashellrc" "$root/home/liveuser/.config/plasmashellrc"; do
        if [[ -f $file ]] && grep -q '^[[:space:]]*ShellPackage[[:space:]]*=' "$file"; then
            printf '    %s pins a ShellPackage\n' "${file#"$root"}"
            return 1
        fi
    done
}

root_locked() {
    local hash
    hash=$(awk -F: '$1 == "root" { print $2 }' "$root/etc/shadow")
    [[ $hash == '!'* || $hash == '*'* ]]
}

live_user() {
    local entry uid gid home shell
    entry=$(awk -F: '$1 == "liveuser"' "$root/etc/passwd")
    IFS=: read -r _ _ uid gid _ home shell <<<"$entry"
    [[ $uid == 1000 && $gid == 1000 && $home == /home/liveuser && $shell == /bin/bash ]] \
        || { printf '    passwd entry: %s\n' "$entry"; return 1; }
    grep -qxF "$shell" "$root/etc/shells" || { echo "    $shell is not in /etc/shells"; return 1; }
    [[ $(stat -c %u:%g "$root/home/liveuser") == 1000:1000 ]] \
        || { echo "    /home/liveuser is not owned by 1000:1000"; return 1; }
}

live_user_not_admin() {
    local group
    for group in wheel root sys adm; do
        if awk -F: -v g="$group" '$1 == g { print $4 }' "$root/etc/group" \
            | tr ',' '\n' | grep -qxF liveuser; then
            echo "    liveuser is a member of $group"
            return 1
        fi
    done
}

system_groups_created() {
    # The overlay's /etc/group lists only root and liveuser; the systemd-sysusers
    # pacman hook must have added the system groups.
    grep -q '^wheel:' "$root/etc/group" && grep -q '^wheel:' "$root/etc/gshadow"
}

sudoers_valid() {
    local file="$root/etc/sudoers.d/10-staros-live"
    [[ -f $file && $(stat -c %a:%u:%g "$file") == 440:0:0 ]] \
        || { echo "    $(stat -c '%a:%u:%g' "$file" 2>/dev/null || echo missing)"; return 1; }
    [[ $(stat -c %a:%u:%g "$root/etc/sudoers.d") == 750:0:0 ]] || return 1
    visudo -c -f "$file" >/dev/null
}

sshd_masked() {
    [[ $(readlink "$root/etc/systemd/system/sshd.service") == /dev/null ]] \
        && [[ ! -e $root/etc/systemd/system/multi-user.target.wants/sshd.service \
            && ! -L $root/etc/systemd/system/multi-user.target.wants/sshd.service ]]
}

no_getty_autologin() {
    [[ ! -e $root/etc/systemd/system/getty@tty1.service.d/autologin.conf ]] \
        && ! grep -rqs -- '--autologin' "$root/etc/systemd/system/"getty@*.service.d
}

live_session_unit() {
    [[ $(readlink "$root/etc/systemd/system/display-manager.service") \
        == /etc/systemd/system/staros-live-session.service ]] \
        && [[ -f $root/etc/systemd/system/staros-live-session.service ]]
}

default_target_graphical() {
    local link
    if [[ -L $root/etc/systemd/system/default.target ]]; then
        link=$(readlink "$root/etc/systemd/system/default.target")
    else
        link=$(readlink "$root/usr/lib/systemd/system/default.target")
    fi
    [[ $(basename -- "$link") == graphical.target ]]
}

session_entry_valid() {
    "$staros_repo_root/scripts/ci/validate-session-entry.sh" \
        "$root/usr/share/wayland-sessions/staros.desktop"
}

shell_files_present() {
    local path
    for path in usr/lib/qt6/qml/StarOS/Shell/qmldir \
        usr/share/plasma/shells/org.staros.shell/metadata.json \
        usr/share/plasma/shells/org.staros.shell/contents/layout.js \
        usr/share/plasma/plasmoids/org.staros.taskbar/metadata.json \
        usr/share/plasma/plasmoids/org.staros.taskbar/contents/ui/main.qml \
        usr/share/plasma/plasmoids/org.staros.desktop/metadata.json \
        usr/share/plasma/plasmoids/org.staros.desktop/contents/ui/main.qml; do
        [[ -f $root/$path ]] || { echo "    missing /$path"; return 1; }
    done
}

no_private_plasma_imports() {
    local hits path
    local -a paths=()
    for path in "${shell_paths[@]}"; do paths+=("$root/$path"); done
    hits=$(grep -rlF 'org.kde.plasma.private' -- "${paths[@]}" || true)
    [[ -z $hits ]] || { printf '    %s\n' "${hits//"$root"/}"; return 1; }
}

pacman_root() {
    pacman --root "$root" --dbpath "$root/var/lib/pacman" "$@"
}

# True if REL (relative to the root) is in the %BACKUP% list of package PKG
# (pacman keeps it in the local database entry's "files").
is_backup_file() {
    local name version
    read -r name version < <(pacman_root -Q "$1" 2>/dev/null)
    awk -F '\t' -v want="$2" '/^%BACKUP%$/ { b = 1; next } /^%/ { b = 0 }
        b && $1 == want { found = 1 } END { exit !found }' \
        "$root/var/lib/pacman/local/$name-$version/files"
}

# Every overlay and shell file must be new (no package owns it), or a backup
# file of the package that owns it (pacman keeps the existing file then).
overlay_paths_unowned() {
    local rel owner bad=0
    local -a rels
    mapfile -t rels < <(
        cd -- "$overlay" && find . \( -type f -o -type l \) -printf '%P\n'
        cd -- "$root" && find "${shell_paths[@]}" \( -type f -o -type l \) -print
    )
    for rel in "${rels[@]}"; do
        if owner=$(pacman_root -Qqo "$root/$rel" 2>/dev/null); then
            if is_backup_file "$owner" "$rel"; then
                printf '    /%s: backup file of %s\n' "$rel" "$owner"
            else
                printf '    /%s: owned by %s and not a backup file\n' "$rel" "$owner"
                bad=1
            fi
        fi
    done
    printf '    %s overlay and shell paths checked\n' "${#rels[@]}"
    ((bad == 0))
}

info_present() {
    local path
    for path in usr/bin/kwriteconfig6 usr/bin/kscreen-doctor usr/bin/gsettings \
        usr/lib/udev/rules.d/99-qemu-guest-agent.rules; do
        if [[ -e $root/$path ]]; then
            result INFO "present /$path"
        else
            result INFO "absent /$path"
        fi
    done
}

check "no forbidden environment variable names in the image" no_forbidden_env
check "no plasmashellrc pins a ShellPackage" no_shell_package_override
check "root is locked" root_locked
check "liveuser is 1000:1000 with /bin/bash and owns its home" live_user
check "liveuser is not in wheel, root, sys or adm" live_user_not_admin
check "system groups were created by systemd-sysusers" system_groups_created
check "live sudoers file is 0440 root:root, directory 0750, and valid" sudoers_valid
check "sshd is masked and not enabled" sshd_masked
check "no getty autologin" no_getty_autologin
check "display-manager.service is the Star OS live session unit" live_session_unit
check "default.target is graphical.target" default_target_graphical
check "staros.desktop passes desktop-file-validate (DesktopNames allowed)" session_entry_valid
check "Star OS shell files are installed" shell_files_present
check "no org.kde.plasma.private import in Star OS shell files" no_private_plasma_imports
check "overlay and shell paths are unowned or package backup files" overlay_paths_unowned
info_present

if ((failures > 0)); then
    die "$failures image policy check(s) failed"
fi
log "Image policy: all checks passed"
