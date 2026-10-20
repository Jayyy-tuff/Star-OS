#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints facts about the package baseline that milestone M0.2 depends on
# (ADR-0008, docs/architecture/m02-shell-prototype-design.md, iteration 0).
# Runs in a throwaway Arch container already pinned by
# prepare-arch-build-host.sh. It installs the planned packages into the
# container; nothing here touches the ISO. Every probe may fail; results are
# printed as "FACT <name> <value>" lines so they can be read from the CI log.

set -uo pipefail

# shellcheck source=scripts/lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

planned_file="$staros_repo_root/distro/archiso/staros/packages.x86_64.append"
section() { printf '\n######## %s\n' "$*"; }
fact() { printf 'FACT %s %s\n' "$1" "${*:2}"; }

if [[ -f $planned_file ]]; then
    mapfile -t planned < <(grep -v -E '^\s*(#|$)' "$planned_file")
else
    planned=(kwin plasma-workspace plasma-desktop kactivitymanagerd layer-shell-qt
        kitemmodels xorg-xwayland mesa noto-fonts konsole systemsettings
        polkit-kde-agent libkscreen orca speech-dispatcher python-gobject pipewire
        pipewire-pulse wireplumber)
fi
probe_tools=(qemu-guest-agent kpackage qt6-declarative desktop-file-utils sudo binutils file)

section "Planned packages exist in the baseline"
missing=0
for p in "${planned[@]}" "${probe_tools[@]}"; do
    if pacman -Si "$p" >/dev/null 2>&1; then
        fact "pkg.$p" "$(pacman -Si "$p" | awk -F': ' '/^Version/{print $2}')"
    else
        fact "pkg.$p" MISSING
        missing=1
    fi
done
fact planned.missing "$missing"

section "Closure of releng + planned packages against the recorded ISO list"
closure_root=/tmp/closure
mkdir -p "$closure_root/db/local"
cp -r /var/lib/pacman/sync "$closure_root/db/" 2>/dev/null
mapfile -t releng < <(grep -v -E '^\s*(#|$)' /usr/share/archiso/configs/releng/packages.x86_64)
if pacman --root "$closure_root" --dbpath "$closure_root/db" -Sp --print-format '%n' \
    "${releng[@]}" "${planned[@]}" 2>/tmp/closure.err | sort -u >/tmp/closure.txt; then
    cut -d' ' -f1 "$staros_repo_root/distro/baseline/packages.x86_64.txt" | sort -u >/tmp/baseline.txt
    comm -13 /tmp/baseline.txt /tmp/closure.txt >/tmp/new.txt
    fact closure.total "$(wc -l </tmp/closure.txt)"
    fact closure.new "$(wc -l </tmp/new.txt)"
    total_kib=0
    while read -r size unit; do
        case $unit in
            B) total_kib=$((total_kib + ${size%.*} / 1024)) ;;
            KiB) total_kib=$((total_kib + ${size%.*})) ;;
            MiB) total_kib=$((total_kib + ${size%.*} * 1024)) ;;
            GiB) total_kib=$((total_kib + ${size%.*} * 1024 * 1024)) ;;
        esac
    done < <(xargs -a /tmp/new.txt pacman -Si 2>/dev/null | awk -F': ' '/^Installed Size/{print $2}')
    fact closure.new_installed_mib "$((total_kib / 1024))"
    printf 'NEW %s\n' "$(tr '\n' ' ' </tmp/new.txt)"
else
    fact closure.error "$(head -c 400 /tmp/closure.err)"
fi

section "Install planned packages and probe tools into this container"
pacman -S --noconfirm --needed "${planned[@]}" "${probe_tools[@]}" >/tmp/install.log 2>&1
fact install.exit "$?"
tail -n 5 /tmp/install.log

section "Tool owners"
for f in /usr/bin/kscreen-doctor /usr/bin/kwriteconfig6 /usr/bin/kpackagetool6 \
    /usr/lib/qt6/bin/qmltestrunner /usr/lib/qt6/bin/qmllint /usr/bin/gsettings \
    /usr/bin/desktop-file-validate /usr/bin/busctl /usr/bin/runuser; do
    fact "owner.$(basename "$f")" "$(pacman -Qoq "$f" 2>/dev/null || echo MISSING)"
done

section "qemu-guest-agent autostart"
pacman -Ql qemu-guest-agent 2>/dev/null | grep -E 'udev|systemd|\.conf' | sed 's/^/    /'
rule=$(pacman -Ql qemu-guest-agent 2>/dev/null | awk '/rules\.d\/.*\.rules$/{print $2}' | head -1)
if [[ -n $rule ]]; then
    fact qga.udev_rule "$rule"
    sed 's/^/    /' "$rule"
else
    fact qga.udev_rule ABSENT
fi
sed -n '1,40p' /usr/lib/systemd/system/qemu-guest-agent.service 2>/dev/null | sed 's/^/    /'

section "Desktop entries for the curated catalogue"
for id in org.kde.konsole systemsettings org.kde.kmenuedit org.kde.dolphin org.kde.kinfocenter org.kde.plasma-systemmonitor org.kde.spectacle; do
    f=/usr/share/applications/$id.desktop
    if [[ -f $f ]]; then
        fact "desktop.$id" "present nodisplay=$(grep -m1 -E '^NoDisplay=' "$f" | cut -d= -f2 || true) owner=$(pacman -Qoq "$f")"
    else
        fact "desktop.$id" ABSENT
    fi
done
printf 'VISIBLE %s\n' "$(grep -L -E '^NoDisplay=true' /usr/share/applications/*.desktop | xargs -n1 basename | sort | tr '\n' ' ')"

section "Accounts, shells, PAM, sysusers, targets"
fact shells "$(grep -v '^#' /etc/shells | tr '\n' ' ')"
fact filesystem.backup "$(pacman -Qii filesystem | awk '/^Backup Files/{f=1} f' | grep -E 'passwd|group|shadow|gshadow|shells' | awk '{print $1}' | tr '\n' ' ')"
fact filesystem.group "$(pacman -Ql filesystem | awk '{print $2}' | grep -E 'etc/(group|gshadow)$' | tr '\n' ' ')"
fact sysusers.files "$(find /usr/lib/sysusers.d -name '*.conf' -printf '%f ')"
grep -h -E '^(g|m) ' /usr/lib/sysusers.d/{basic,arch}.conf 2>/dev/null | sed 's/^/    sysusers: /'
show_file() { printf -- '---- %s\n' "$1"; sed 's/^/    /' "$1" 2>&1; }
show_file /etc/pam.d/login
show_file /etc/pam.d/system-local-login
grep -H -E 'nullok' /etc/pam.d/* 2>/dev/null | sed 's/^/    nullok: /'
fact default.target "$(readlink /usr/lib/systemd/system/default.target)"
fact pacman_hooks "$(find /usr/share/libalpm/hooks -name '*sysusers*' -o -name '*tmpfiles*' | tr '\n' ' ')"
fact polkit.tmpfiles "$(grep -h rules.d /usr/lib/tmpfiles.d/polkit*.conf 2>/dev/null | tr '\n' ' ')"
fact kwin.caps "$(getcap /usr/bin/kwin_wayland 2>/dev/null)"

section "Unprivileged KWin virtual-backend smoke (no permission bypass)"
useradd -m probe 2>/dev/null
runtime=/tmp/probe-xdg
mkdir -p "$runtime" && chown probe: "$runtime" && chmod 0700 "$runtime"
cat >/tmp/kwin-marker.sh <<'EOF'
#!/bin/bash
echo "KWIN-SESSION-RAN wayland=$WAYLAND_DISPLAY"
sleep 3
EOF
chmod 0755 /tmp/kwin-marker.sh
run_kwin() {
    timeout 60 runuser -u probe -- env XDG_RUNTIME_DIR="$runtime" QT_FORCE_STDERR_LOGGING=1 \
        dbus-run-session kwin_wayland --virtual --no-lockscreen --width 1280 --height 800 \
        --exit-with-session /tmp/kwin-marker.sh >/tmp/kwin.log 2>&1
}
run_kwin
status=$?
if [[ $status -ne 0 ]] && grep -q -i 'operation not permitted' /tmp/kwin.log; then
    # File capabilities cannot be raised under the container's NoNewPrivileges.
    fact kwin.retry_without_caps yes
    setcap -r /usr/bin/kwin_wayland 2>/dev/null
    run_kwin
    status=$?
fi
fact kwin.smoke_exit "$status"
fact kwin.session_ran "$(grep -c KWIN-SESSION-RAN /tmp/kwin.log)"
grep -i -E 'composit|render|opengl|qpainter|egl|error|fail' /tmp/kwin.log | head -n 25 | sed 's/^/    /'
tail -n 15 /tmp/kwin.log | sed 's/^/    tail: /'
