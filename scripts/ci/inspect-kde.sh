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

section "M0.5: package versions for the baseline"
for p in pulseaudio-qt inter-font wl-clipboard gamemode lib32-gamemode kguiaddons kscreenlocker plasma-workspace; do
    fact "pkg.$p" "$(pacman -Si "$p" 2>/dev/null | awk -F': ' '/^Version/{print $2}' | head -n1)"
done
pacman -S --noconfirm --needed kscreenlocker plasma-workspace gamemode wl-clipboard >/tmp/install-m05.log 2>&1
fact install_m05.exit "$?"
fact gamemode.files "$(pacman -Qlq gamemode 2>/dev/null | grep -E 'bin/|polkit|\.service' | tr '\n' ' ')"

section "M0.5: Breeze look-and-feel lock screen and logout (the kscreenlocker and logout greeter API)"
lnf=/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents
fact lnf.files "$(find "$lnf" -maxdepth 2 \( -path '*/lockscreen/*' -o -path '*/logout/*' -o -name defaults \) | sort | tr '\n' ' ')"
for f in "$lnf/defaults" "$lnf/../metadata.json" "$lnf/lockscreen/LockScreen.qml" "$lnf/lockscreen/LockScreenUi.qml" \
    "$lnf/lockscreen/MainBlock.qml" "$lnf/logout/Logout.qml"; do
    printf -- '---- %s\n' "$f"
    sed 's/^/    | /' "$f" 2>/dev/null || echo "    (missing)"
done
printf -- '---- context properties and signals the lock screen QML uses\n'
grep -rhoE '\b(authenticator|kscreenlocker_[A-Za-z]+|sessionsModel|keystateSource|wallpaper|config)\.[A-Za-z]+' "$lnf/lockscreen" 2>/dev/null \
    | sort | uniq -c | sed 's/^/    /'
printf -- '---- kscreenlocker greeter strings\n'
strings /usr/lib/kscreenlocker_greet 2>/dev/null | grep -E '^(authenticator|kscreenlocker_|org\.kde\.|lockscreen|LockScreen)' | sort -u | head -n 60 | sed 's/^/    /'

section "M0.5: where kscreenlocker keeps its own lock screen, and the authenticator's API"
pacman -Qlq kscreenlocker 2>/dev/null | grep -v -E '/locale/|/doc/|/$' | sed 's/^/    /'
mapfile -t lock_qml < <(grep -rl --include='*.qml' -e 'authenticator' /usr/share /usr/lib/qt6/qml 2>/dev/null | head -n 20)
fact lockscreen.qml "${lock_qml[*]}"
for f in "${lock_qml[@]}"; do
    printf -- '---- %s\n' "$f"
    grep -n -E 'authenticator|Qt\.quit|kscreenlocker_|signal |property ' "$f" | head -n 80 | sed 's/^/    | /'
done
printf -- '---- greeter strings about authentication\n'
strings -n 5 /usr/lib/kscreenlocker_greet 2>/dev/null \
    | grep -E -i '^(startAuthenticating|respond|tryUnlock|cancel|hadPrompt|promptForSecret|prompt|infoMessage|errorMessage|succeeded|failed|unlocked|busy|graceLocked)' \
    | sort -u | sed 's/^/    /'

section "M0.5: libnotificationmanager with the Star OS taskbar's models (S20 reproduction)"
for h in notifications.h server.h settings.h notification.h; do
    f=/usr/include/notificationmanager/$h
    printf -- '---- %s\n' "$f"
    grep -n -E 'Q_PROPERTY|Q_ENUM|Q_FLAG|Q_INVOKABLE|enum |= 1 <<|Urgency|inhibit|Inhibit|window|init\(' "$f" 2>/dev/null \
        | head -n 120 | sed 's/^/    | /' || echo "    (missing)"
done
qml_tool=$(command -v qml6 || command -v /usr/lib/qt6/bin/qml || true)
fact notify.qml_tool "$qml_tool"
cat >/tmp/notify-probe.qml <<'EOF'
import QtQuick
import org.kde.notificationmanager as NotificationManager

// The taskbar's popups and history models (main.qml), and variants with
// one filter left out, to see which keeps a notification away.
Item {
    id: root

    NotificationManager.Settings {
        id: notificationSettings
    }

    readonly property bool doNotDisturb: notificationSettings.notificationsInhibitedUntil > new Date()

    NotificationManager.Notifications {
        id: popups
        limit: 3
        showExpired: false
        showDismissed: false
        showJobs: false
        blacklistedDesktopEntries: notificationSettings.popupBlacklistedApplications
        blacklistedNotifyRcNames: notificationSettings.popupBlacklistedServices
        urgencies: root.doNotDisturb ? NotificationManager.Notifications.CriticalUrgency
            : NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.CriticalUrgency
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
        onCountChanged: console.info("PROBE popups.countChanged " + count)
    }
    NotificationManager.Notifications {
        id: history
        showExpired: true
        showDismissed: true
        showJobs: false
        blacklistedDesktopEntries: notificationSettings.historyBlacklistedApplications
        blacklistedNotifyRcNames: notificationSettings.historyBlacklistedServices
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
        onCountChanged: console.info("PROBE history.countChanged " + count)
    }
    NotificationManager.Notifications {
        id: plain
        onCountChanged: console.info("PROBE plain.countChanged " + count)
    }
    NotificationManager.Notifications {
        id: noUrgencies
        limit: 3
        showExpired: false
        showDismissed: false
        showJobs: false
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled
    }
    NotificationManager.Notifications {
        id: noLimit
        showExpired: false
        showDismissed: false
        showJobs: false
        urgencies: NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.CriticalUrgency
    }
    // The history model and variants, to find the setting that keeps
    // every notification out of it.
    NotificationManager.Notifications {
        id: h1
        showExpired: true
        showDismissed: true
    }
    NotificationManager.Notifications {
        id: h2
        showExpired: true
    }
    NotificationManager.Notifications {
        id: h3
        showDismissed: true
    }
    NotificationManager.Notifications {
        id: h4
        showExpired: true
        showDismissed: true
        showJobs: false
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
    }
    NotificationManager.Notifications {
        id: h5
        showExpired: true
        showDismissed: true
        showJobs: false
        blacklistedDesktopEntries: notificationSettings.historyBlacklistedApplications
        blacklistedNotifyRcNames: notificationSettings.historyBlacklistedServices
        urgencies: NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.CriticalUrgency
        sortMode: NotificationManager.Notifications.SortByDate
        sortOrder: Qt.DescendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
    }
    NotificationManager.Notifications {
        id: h6
        showExpired: false
        showDismissed: false
        showJobs: false
        blacklistedDesktopEntries: notificationSettings.historyBlacklistedApplications
        blacklistedNotifyRcNames: notificationSettings.historyBlacklistedServices
    }
    property bool expiredOne: false

    ListView {
        id: view
        width: 100
        height: 300
        model: popups
        delegate: Item {
            required property var model
            width: 10
            height: 10
            Component.onCompleted: console.info("PROBE delegate summary=" + model.summary + " urgency=" + model.urgency
                + " timeout=" + model.timeout + " expired=" + model.expired + " app=" + model.applicationName
                + " desktopEntry=" + model.desktopEntry)
        }
    }

    function state() {
        return "popups=" + popups.count + "/" + popups.rowCount() + " history=" + history.count + "/" + history.rowCount()
            + " plain=" + plain.count + "/" + plain.rowCount() + " noUrgencies=" + noUrgencies.rowCount()
            + " noLimit=" + noLimit.rowCount() + " view=" + view.count
            + " h1..h6=" + [h1, h2, h3, h4, h5, h6].map(m => m.rowCount()).join(",")
            + " history.active=" + history.activeNotificationsCount + " history.expired=" + history.expiredNotificationsCount
            + " blacklists=" + JSON.stringify([notificationSettings.historyBlacklistedApplications,
                                               notificationSettings.historyBlacklistedServices,
                                               notificationSettings.popupBlacklistedApplications])
            + " valid=" + NotificationManager.Server.valid
            + " inhibited=" + NotificationManager.Server.inhibited + " dnd=" + root.doNotDisturb
            + " until=" + notificationSettings.notificationsInhibitedUntil + " urgencies=" + popups.urgencies
            + " enums=" + NotificationManager.Notifications.LowUrgency + "," + NotificationManager.Notifications.NormalUrgency
            + "," + NotificationManager.Notifications.CriticalUrgency;
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            console.info("PROBE tick " + root.state());
            if (!root.expiredOne && plain.rowCount() >= 3) {
                root.expiredOne = true;
                popups.expire(popups.index(0, 0));
                console.info("PROBE expired the newest popup");
            }
        }
    }

    Component.onCompleted: {
        NotificationManager.Server.inhibited = root.doNotDisturb;
        console.info("PROBE ready " + root.state());
    }
}
EOF
cat >/tmp/notify-probe.sh <<'EOF'
#!/bin/bash
export QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1
export QT_LOGGING_RULES="org.kde.plasma.notifications*=true;org.kde.notificationmanager*=true"
"$1" /tmp/notify-probe.qml >/tmp/notify-probe.log 2>&1 &
pid=$!
sleep 5
call() { gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications \
    --method "org.freedesktop.Notifications.$1" "${@:2}" 2>&1; }
echo "PROBE-SH server: $(call GetServerInformation)"
echo "PROBE-SH plain: $(call Notify 'Star test' 0 dialog-information 'Hello from the test' 'Sent over D-Bus' '[]' '{}' 30000)"
sleep 3
echo "PROBE-SH urgency: $(call Notify 'Star test' 0 dialog-information 'With urgency' 'Normal urgency' '[]' "{'urgency': <byte 1>}" 30000)"
sleep 3
echo "PROBE-SH desktop-entry: $(call Notify 'Konsole' 0 utilities-terminal 'With a desktop entry' 'Konsole' '[]' "{'desktop-entry': <'org.kde.konsole'>}" 30000)"
sleep 6
kill "$pid"
wait "$pid" 2>/dev/null
grep -v -E 'QStandardPaths|propagateSizeHints' /tmp/notify-probe.log | head -n 160
EOF
chmod 0755 /tmp/notify-probe.sh
if [[ -n $qml_tool ]]; then
    timeout 120 runuser -u probe -- env XDG_RUNTIME_DIR="$runtime" HOME=/home/probe \
        dbus-run-session /tmp/notify-probe.sh "$qml_tool" 2>&1 | sed 's/^/    /'
    fact notify.probe_exit "${PIPESTATUS[0]}"
fi
