// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami
import StarOS.Shell
import StarOS.System

// Plasma adapter of the Star OS taskbar (M0.2, ADR-0008; M0.5 floating
// taskbar). This file and LauncherWindow.qml are the only Star OS QML in the
// taskbar that imports Plasma or KDE modules; every visible element comes
// from the Plasma-free StarOS.Shell module. StarOS.System gives the
// applications (ADR-0013) and the system status.
//
// The window list uses plasmashell's packaged window-management grant
// (org.kde.plasmashell.desktop); nothing here bypasses KWin's permission checks.
ContainmentItem {
    id: root

    // Pinned to the taskbar, in this order; ids the image lacks are left out.
    readonly property list<string> taskbarPins: [
        "org.staros.files.desktop",
        "firefox.desktop",
        "org.kde.konsole.desktop",
        "org.staros.sunstore.desktop",
        "org.staros.lens.desktop",
        "vlc.desktop",
        "org.staros.games.desktop"
    ]
    // Pinned in the start menu.
    readonly property list<string> menuPins: [
        "firefox.desktop",
        "org.staros.files.desktop",
        "org.staros.sunstore.desktop",
        "org.kde.konsole.desktop",
        "systemsettings.desktop",
        "org.staros.lens.desktop",
        "vlc.desktop",
        "org.kde.okular.desktop",
        "org.kde.gwenview.desktop",
        "org.staros.games.desktop",
        "org.staros.storage.desktop",
        "org.kde.kwrite.desktop",
        "org.kde.kcalc.desktop",
        "org.kde.ark.desktop",
        "org.staros.welcome.desktop"
    ]

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    ApplicationsModel {
        id: applications
        onCountChanged: console.info("STAROS-SHELL apps=" + totalCount)
        onLaunched: desktopId => console.info("STAROS-SHELL launch=" + desktopId)
        onLaunchFailed: (name, error) => console.warn("STAROS-SHELL launch failed: " + name + ": " + error)
    }

    SystemStatus {
        id: systemStatus
    }

    // Pinned apps and windows: a running pinned app takes its pin's place;
    // other windows follow in the order they opened.
    TaskManager.TasksModel {
        id: tasks
        launcherList: applications.revision >= 0
            ? root.taskbarPins.filter(id => Object.keys(applications.find(id)).length > 0)
                .map(id => "applications:" + id)
            : []
        separateLaunchers: false
        launchInPlace: true
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortManual
        onCountChanged: console.info("STAROS-SHELL tasks=" + count)
    }

    // An app's own theme icon, for apps without Star OS artwork.
    Component {
        id: themeIcon

        Kirigami.Icon {
            property var iconData
            source: iconData
            Accessible.ignored: true
        }
    }

    Taskbar {
        id: taskbar
        anchors.fill: parent
        focus: true
        tasksModel: tasks
        iconFallback: themeIcon
        systemStatus: systemStatus
        startMenuOpen: launcherWindow.visible
        // The panel spans the bottom edge of its screen (layout.js).
        glassOrigin: Qt.point(0, Screen.height - taskbar.height)
        glassScreenSize: Qt.size(Screen.width, Screen.height)

        onLauncherRequested: launcherWindow.toggleLauncher()
        onQuickSettingsRequested: applications.launchDesktopId("org.staros.storage.desktop")
        onActivateRequested: row => {
            const idx = tasks.makeModelIndex(row);
            if (tasks.data(idx, TaskManager.AbstractTasksModel.IsLauncher) === true) {
                tasks.requestNewInstance(idx);
            } else if (tasks.data(idx, TaskManager.AbstractTasksModel.IsActive) === true) {
                tasks.requestToggleMinimized(idx);
            } else {
                tasks.requestActivate(idx);
            }
        }
    }

    LauncherWindow {
        id: launcherWindow
        catalogue: applications
        systemStatus: systemStatus
        pinnedIds: root.menuPins
        iconFallback: themeIcon
        onLockRequested: root.callSession("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "Lock")
        onLogoutRequested: root.callSession("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptLogout")
        onRestartRequested: root.callSession("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptReboot")
        onShutdownRequested: root.callSession("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptShutDown")
    }

    function callSession(service, path, iface, member) {
        console.info("STAROS-SHELL session=" + member);
        DBus.SessionBus.asyncCall({
            service: service,
            path: path,
            iface: iface,
            member: member
        });
    }

    // Meta and Alt+F1: plasmashell activates the panel containment that
    // provides org.kde.plasma.launchermenu (see metadata.json).
    Plasmoid.onActivated: launcherWindow.toggleLauncher()

    Component.onCompleted: {
        // Reduced motion in the platform settings turns the animations off.
        Theme.animationFactor = Kirigami.Units.longDuration / 250;
        console.info("STAROS-SHELL ready shell=org.staros.shell gridUnit=" + Theme.gridUnit
            + " taskbarHeight=" + Theme.taskbarHeight + " focusRing=" + Theme.focusRingWidth
            + " animationFactor=" + Theme.animationFactor);
    }
}
