#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Checks the built live image's root file system against the M0.2 and M0.3
# policy (ADR-0008, ADR-0009, ADR-0010, docs/security/threat-model.md): no
# CI-only bypass variables, the least-privilege live user, live-only login and
# service settings, the Star OS shell files, overlay files that no package owns
# (or that are backup files of their package), the Star OS apps, no Flatpak
# remote before the user agrees, and no build-time repository in the image.
# Prints one POLICY line per check and fails on any FAIL.
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
# (StarOS/System comes from the staros-system package.)
shell_paths=(
    usr/lib/qt6/qml/StarOS/Shell
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

star_os_apps_installed() {
    local pkg app
    for pkg in staros-files staros-sunstore staros-lens staros-storage; do
        pacman_root -Q "$pkg" >/dev/null 2>&1 || { echo "    $pkg is not installed"; return 1; }
    done
    for app in staros-files staros-sunstore staros-lens staros-storage; do
        [[ -x $root/usr/bin/$app ]] || { echo "    /usr/bin/$app is missing"; return 1; }
    done
}

app_entries_valid() {
    local entry
    for entry in org.staros.files org.staros.sunstore org.staros.lens org.staros.storage; do
        desktop-file-validate "$root/usr/share/applications/$entry.desktop" \
            || { echo "    $entry.desktop is not valid"; return 1; }
    done
}

# Desktop files of the apps pinned in the taskbar and the start menu (the
# taskbar plasmoid's main.qml) that the image must have, so a renamed desktop
# file is noticed; the start menu itself lists every installed app (ADR-0013).
catalogue_apps=(
    org.kde.konsole systemsettings org.staros.files org.staros.sunstore org.staros.lens
    org.staros.storage firefox vlc org.kde.okular org.kde.gwenview org.kde.ark org.kde.kwrite org.kde.kcalc
)

catalogue_apps_present() {
    local id similar missing=0
    for id in "${catalogue_apps[@]}"; do
        [[ -f $root/usr/share/applications/$id.desktop ]] && continue
        similar=$(find "$root/usr/share/applications" -maxdepth 1 -iname "*${id##*.}*" -printf '%f ' 2>/dev/null)
        printf '    missing /usr/share/applications/%s.desktop (similar: %s)\n' "$id" "${similar:-none}"
        missing=1
    done
    ((missing == 0))
}

# Inter is the UI font of KDE apps and the shell, and fontconfig's
# sans-serif (ADR-0016).
inter_ui_font() {
    pacman_root -Q inter-font >/dev/null 2>&1 \
        && grep -qx 'font=Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1' "$root/etc/xdg/kdeglobals" \
        && grep -q '<family>Inter</family>' "$root/etc/fonts/local.conf"
}

star_os_system_module() {
    [[ -f $root/usr/lib/qt6/qml/StarOS/System/qmldir ]] \
        && [[ $(pacman_root -Qqo "$root/usr/lib/qt6/qml/StarOS/System/qmldir" 2>/dev/null) == staros-system ]]
}

# KWin grants its screenshot interface to the program named by an absolute
# Exec in a desktop file that lists the interface (ADR-0012); English text
# recognition data must be there.
lens_screenshot_grant() {
    local file="$root/usr/share/applications/org.staros.lens.desktop"
    grep -qx 'Exec=/usr/bin/staros-lens' "$file" \
        && grep -qx 'X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2' "$file" \
        && grep -qx 'X-KDE-Shortcuts=Meta+Shift+L' "$file" \
        && [[ -f $root/usr/share/tessdata/eng.traineddata ]]
}

# Star Storage (ADR-0011): the helper is root's only through the polkit action
# that names it; the live rule allows only that action, only for liveuser.
storage_helper_and_polkit() {
    local helper=usr/lib/staros/staros-storage-helper
    local policy=usr/share/polkit-1/actions/org.staros.storage.policy
    local rule=etc/polkit-1/rules.d/49-staros-live-storage.rules
    [[ -x $root/$helper && $(stat -c '%U:%G %a' "$root/$helper") == 'root:root 755' ]] \
        || { echo "    /$helper is missing or not root:root 755"; return 1; }
    [[ $(pacman_root -Qqo "$root/$helper" 2>/dev/null) == staros-storage ]] \
        || { echo "    /$helper is not owned by staros-storage"; return 1; }
    if ! grep -q '<allow_active>auth_admin_keep</allow_active>' "$root/$policy" \
        || ! grep -q "<annotate key=\"org.freedesktop.policykit.exec.path\">/$helper</annotate>" "$root/$policy"; then
        echo "    /$policy does not require an administrator for /$helper"
        return 1
    fi
    if [[ $(grep -c 'polkit.Result.YES' "$root/$rule") -ne 1 ]] \
        || ! grep -q 'action.id === "org.staros.storage.manage" && subject.user === "liveuser"' "$root/$rule"; then
        echo "    /$rule allows more than the Star Storage action for liveuser"
        return 1
    fi
}

# Quick settings' Wi-Fi (ADR-0014): the live-only D-Bus rule lets liveuser,
# and nobody else, talk to iwd; it allows nothing else.
live_iwd_policy() {
    local file="$root/etc/dbus-1/system.d/staros-live-iwd.conf"
    [[ -f $file ]] || { echo "    /etc/dbus-1/system.d/staros-live-iwd.conf is missing"; return 1; }
    if [[ $(grep -c '<allow ' "$file") -ne 1 || $(grep -c '<policy ' "$file") -ne 1 ]] \
        || ! grep -q '<allow send_destination="net.connman.iwd"/>' "$file" \
        || ! grep -q '<policy user="liveuser">' "$file"; then
        echo "    the live iwd rule allows more than iwd for liveuser"
        return 1
    fi
}

flathub_file_shipped() {
    local file="$root/usr/share/staros-sunstore/flathub.flatpakrepo"
    [[ -f $file ]] && grep -qx '\[Flatpak Repo\]' "$file" \
        && grep -qx 'Url=https://dl.flathub.org/repo/' "$file" \
        && [[ $(pacman_root -Qqo "$file" 2>/dev/null) == staros-sunstore ]]
}

# Flathub is added per user, after consent (ADR-0010): no system remote,
# neither configured nor as a static remote file of a package.
no_system_flatpak_remote() {
    local found
    found=$(find "$root/etc/flatpak/remotes.d" "$root/usr/share/flatpak/remotes.d" -type f 2>/dev/null || true)
    [[ -z $found ]] || { printf '    %s\n' "${found//"$root"/}"; return 1; }
    if [[ -f $root/var/lib/flatpak/repo/config ]] \
        && grep -q '^\[remote ' "$root/var/lib/flatpak/repo/config"; then
        echo "    /var/lib/flatpak/repo/config defines a remote"
        return 1
    fi
}

no_build_repository() {
    ! grep -rqs '^[[:space:]]*\[staros\]' "$root/etc/pacman.conf" "$root/etc/pacman.d"
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
check "staros-files, -sunstore, -lens and -storage are installed" star_os_apps_installed
check "Files, Sun Store, Star Lens and Star Storage desktop entries pass desktop-file-validate" app_entries_valid
check "the Star Storage helper is root's only through its polkit action" storage_helper_and_polkit
check "Star Lens has KWin's screenshot grant, its shortcut and English OCR data" lens_screenshot_grant
check "the live iwd D-Bus rule allows only iwd, only for liveuser" live_iwd_policy
check "staros-sunstore ships Flathub's remote file" flathub_file_shipped
check "the pinned apps have their desktop files" catalogue_apps_present
check "StarOS.System is installed by staros-system" star_os_system_module
check "Inter is the UI font" inter_ui_font
check "no system-wide Flatpak remote" no_system_flatpak_remote
check "the image's pacman configuration has no [staros] build repository" no_build_repository
info_present

if ((failures > 0)); then
    die "$failures image policy check(s) failed"
fi
log "Image policy: all checks passed"
