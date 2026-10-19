#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Prints facts about the KWin/Plasma packages in the package baseline, for
# designing milestone M0.2 (ADR-0004). Runs in a throwaway Arch container
# already prepared by prepare-arch-build-host.sh with the packages below.
# Read-only apart from /tmp; every probe is allowed to fail.

set -uo pipefail

section() { printf '\n######## %s\n' "$*"; }
show() { printf '\n---- %s\n' "$1"; head -n "${2:-120}" -- "$1" 2>&1; }

section "Package versions in the baseline"
for p in kwin plasma-workspace plasma-desktop plasma-mobile plasma-bigscreen \
    layer-shell-qt qt6-base qt6-declarative qt6-wayland qt6-tools kservice kio \
    kwindowsystem kwayland libplasma orca speech-dispatcher sddm plasma-login-manager \
    greetd xorg-xwayland mesa noto-fonts ttf-dejavu pipewire wireplumber konsole \
    kwrite spectacle kscreen kscreenlocker polkit-kde-agent xdg-desktop-portal-kde \
    kpmcore snapper snap-pac limine grub-btrfs calamares; do
    if info=$(pacman -Si "$p" 2>/dev/null); then
        printf '%-26s %s  (%s)\n' "$p" \
            "$(awk -F': ' '/^Version/{print $2}' <<<"$info")" \
            "$(awk -F': ' '/^Repository/{print $2}' <<<"$info")"
    else
        printf '%-26s NOT IN BASELINE REPOSITORIES\n' "$p"
    fi
done

section "Plasma shell packages"
find /usr/share/plasma/shells -maxdepth 4 | sort
for f in /usr/share/plasma/shells/org.kde.plasma.desktop/metadata.json \
    /usr/share/plasma/shells/org.kde.plasma.desktop/contents/defaults \
    /usr/share/plasma/shells/org.kde.plasma.desktop/contents/layout.js \
    /usr/share/plasma/shells/org.kde.plasma.desktop/contents/views/Desktop.qml \
    /usr/share/plasma/shells/org.kde.plasma.desktop/contents/views/Panel.qml; do
    show "$f" 200
done

section "How plasmashell picks its shell package"
grep -l -r --binary-files=text -e PLASMA_DEFAULT_SHELL /usr/bin /usr/lib 2>/dev/null | head
strings /usr/bin/plasmashell 2>/dev/null | grep -i -E 'shell|PLASMA_' | head -40
plasmashell --help 2>&1 | head -40

section "Session entry points"
ls -l /usr/share/wayland-sessions/ /usr/bin/startplasma* 2>&1
for f in /usr/share/wayland-sessions/*.desktop; do show "$f" 40; done
strings /usr/bin/startplasma-wayland 2>/dev/null | grep -E '^[A-Z_]+=|PLASMA|KWIN|systemd' | head -40
find /usr/lib/systemd/user -maxdepth 1 \( -iname '*plasma*' -o -iname '*kwin*' \) | sort

section "KWin"
kwin_wayland --help 2>&1 | head -80
grep -r -l --binary-files=text 'X-KDE-Wayland-Interfaces' /usr/share/applications 2>/dev/null | head -20
grep -r -h 'X-KDE-Wayland-Interfaces\|X-KDE-DBUS-Restricted-Interfaces' /usr/share/applications 2>/dev/null | sort -u

section "QML modules"
ls /usr/lib/qt6/qml/org/kde/ 2>&1
ls /usr/lib/qt6/qml/org/kde/plasma/private 2>&1 | head -60
for m in taskmanager layershell plasma/private/kicker; do
    show "/usr/lib/qt6/qml/org/kde/$m/qmldir" 30
done
for t in /usr/lib/qt6/qml/org/kde/taskmanager/*.qmltypes /usr/lib/qt6/qml/org/kde/layershell/*.qmltypes; do
    [[ -f $t ]] || continue
    printf '\n---- %s (components, properties, methods)\n' "$t"
    grep -E '^\s*(Component|name:|Property|Method|Signal|exports:)' "$t" | head -400
done

section "Qt tools"
pacman -Ql qt6-declarative qt6-tools 2>/dev/null | grep -E '/bin/|/lib/qt6/bin/' | head -40

section "Smoke: Qt Quick Test, offscreen"
mkdir -p /tmp/qt && cat >/tmp/qt/tst_probe.qml <<'EOF'
import QtQuick
import QtTest
TestCase {
    name: "Probe"
    Item { id: box; width: 100; height: 50; focus: true }
    function test_size() { compare(box.width, 100) }
    function test_key() { keyClick(Qt.Key_Tab); verify(true) }
}
EOF
QT_QPA_PLATFORM=offscreen timeout 60 /usr/lib/qt6/bin/qmltestrunner -input /tmp/qt 2>&1 | tail -20

section "Smoke: KWin virtual backend with a screenshot"
export XDG_RUNTIME_DIR=/tmp/xdg && mkdir -p -m 0700 "$XDG_RUNTIME_DIR"
cat >/tmp/kwin-session.sh <<'EOF'
#!/bin/bash
sleep 8
spectacle --background --fullscreen --nonotify --output /tmp/shot.png >/tmp/spectacle.log 2>&1
echo "spectacle exit $?" >>/tmp/spectacle.log
sleep 2
EOF
chmod +x /tmp/kwin-session.sh
timeout 60 dbus-run-session kwin_wayland --virtual --no-lockscreen --xwayland --width 1280 --height 800 \
    --exit-with-session /tmp/kwin-session.sh >/tmp/kwin.log 2>&1
echo "kwin exit $?"
tail -n 60 /tmp/kwin.log
cat /tmp/spectacle.log 2>&1
file /tmp/shot.png 2>&1 || ls -l /tmp/shot.png 2>&1
