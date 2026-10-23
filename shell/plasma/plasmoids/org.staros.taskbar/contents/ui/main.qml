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

// Plasma adapter of the Star OS taskbar (M0.2, ADR-0008). This file and its two
// siblings are the only Star OS QML in the taskbar that imports Plasma or KDE
// modules; every visible element comes from the Plasma-free StarOS.Shell module.
// The window rows carry libtaskmanager's AppId role, which picks the Star OS
// icons, and its decoration role, which Kirigami.Icon shows for other apps.
// StarOS.System gives the system meter its status.
//
// The window list uses plasmashell's packaged window-management grant
// (org.kde.plasmashell.desktop); nothing here bypasses KWin's permission checks.
ContainmentItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // One row per window, in creation order. Startup placeholders appear
    // briefly because plasmashell also holds activation feedback.
    TaskManager.TasksModel {
        id: windows
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        onCountChanged: console.info("STAROS-SHELL tasks=" + count)
    }

    AppCatalogue {
        id: appCatalogue
    }

    SystemStatus {
        id: systemStatus
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
        tasksModel: windows
        iconFallback: themeIcon
        systemStatus: systemStatus
        // The panel spans the bottom edge of its screen (layout.js).
        glassOrigin: Qt.point(0, Screen.height - taskbar.height)
        glassScreenSize: Qt.size(Screen.width, Screen.height)

        onLauncherRequested: launcherWindow.toggleLauncher()
        onSystemStatusRequested: appCatalogue.launchDesktopId("org.staros.storage.desktop")
        onActivateRequested: row => {
            const idx = windows.makeModelIndex(row);
            if (windows.data(idx, TaskManager.AbstractTasksModel.IsActive) === true) {
                windows.requestToggleMinimized(idx);
            } else {
                windows.requestActivate(idx);
            }
        }
        onLeaveRequested: {
            console.info("STAROS-SHELL leave");
            DBus.SessionBus.asyncCall({
                service: "org.kde.LogoutPrompt",
                path: "/LogoutPrompt",
                iface: "org.kde.LogoutPrompt",
                member: "promptAll"
            });
        }
    }

    LauncherWindow {
        id: launcherWindow
        catalogue: appCatalogue
        iconFallback: themeIcon
    }

    // Meta and Alt+F1: plasmashell activates the panel containment that
    // provides org.kde.plasma.launchermenu (see metadata.json).
    Plasmoid.onActivated: launcherWindow.toggleLauncher()

    Component.onCompleted: {
        console.info("STAROS-SHELL ready shell=org.staros.shell gridUnit=" + Theme.gridUnit
            + " taskbarHeight=" + Theme.taskbarHeight + " focusRing=" + Theme.focusRingWidth);
    }
}
