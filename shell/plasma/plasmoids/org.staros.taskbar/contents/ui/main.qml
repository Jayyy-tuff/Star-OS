// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager
import org.kde.notificationmanager as NotificationManager
import org.kde.kirigami as Kirigami
import StarOS.Shell
import StarOS.System

// Plasma adapter of the Star OS taskbar (M0.2, ADR-0008; M0.5 floating
// taskbar, ADR-0013, ADR-0014). This file, ShellOverlay.qml and
// ToastWindow.qml are the only Star OS QML in the taskbar that imports
// Plasma or KDE modules; every visible element comes from the Plasma-free
// StarOS.Shell module. StarOS.System gives the applications, the system
// status, sound, display, network and the clipboard history;
// libnotificationmanager makes the shell the notification server.
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
    readonly property bool doNotDisturb: notificationSettings.notificationsInhibitedUntil > new Date()

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

    AudioControl {
        id: audio
        keysEnabled: true
        onChanged: console.info("STAROS-SHELL volume=" + (available ? volume : "none") + " muted=" + muted)
    }

    DisplayControl {
        id: displayControl
        onNightLightChanged: console.info("STAROS-SHELL nightlight=" + nightLight + " available=" + nightLightAvailable)
    }

    // Meta+V opens it; copies survive the app that made them (ADR-0014).
    ClipboardHistory {
        id: clipboard
        keysEnabled: true
        onShortcutActivated: overlay.toggle("clipboard")
        onCountChanged: console.info("STAROS-SHELL clipboard=" + count)
    }

    NetworkStatus {
        id: network
        onChanged: console.info("STAROS-SHELL network=" + state + " kind=" + kind)
    }

    // Do not disturb, the apps that may not pop up, and what was read.
    NotificationManager.Settings {
        id: notificationSettings
    }

    // New notifications for the toasts.
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
        onCountChanged: console.info("STAROS-SHELL toasts=" + count)
    }

    // Every notification of this session, for the notification centre.
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
        onCountChanged: console.info("STAROS-SHELL notifications=" + count)
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
        networkSymbol: Status.networkSymbol(network)
        volumeSymbol: Status.volumeSymbol(audio)
        trayDetail: [
            qsTr("Network: %1.").arg(Status.networkText(network)),
            audio.available ? (audio.muted ? qsTr("Sound is muted.") : qsTr("Volume: %1 %.").arg(audio.volume)) : ""
        ].filter(part => part !== "").join(" ")
        unreadNotifications: history.unreadNotificationsCount
        doNotDisturb: root.doNotDisturb
        startMenuOpen: overlay.open && overlay.panel === "start"
        quickSettingsOpen: overlay.open && overlay.panel === "quick"
        calendarOpen: overlay.open && overlay.panel === "calendar"
        // The panel spans the bottom edge of its screen (layout.js).
        glassOrigin: Qt.point(0, Screen.height - taskbar.height)
        glassScreenSize: Qt.size(Screen.width, Screen.height)

        onLauncherRequested: overlay.toggle("start")
        onQuickSettingsRequested: overlay.toggle("quick")
        onCalendarRequested: overlay.toggle("calendar")
        onNotificationsRequested: overlay.toggle("calendar")
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

    ShellOverlay {
        id: overlay
        catalogue: applications
        systemStatus: systemStatus
        audio: audio
        display: displayControl
        network: network
        notifications: history
        clipboard: clipboard
        pinnedIds: root.menuPins
        iconFallback: themeIcon
        doNotDisturb: root.doNotDisturb
        anchorRight: taskbar.pillRight
        onLaunchRequested: desktopId => applications.launchDesktopId(desktopId)
        onLockRequested: root.callSession("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver", "Lock")
        onLogoutRequested: root.callSession("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptLogout")
        onRestartRequested: root.callSession("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptReboot")
        onShutdownRequested: root.callSession("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptShutDown")
        onPowerRequested: root.callSession("org.kde.LogoutPrompt", "/LogoutPrompt", "org.kde.LogoutPrompt", "promptAll")
        onDoNotDisturbToggled: root.setDoNotDisturb(!root.doNotDisturb)
        onNotificationsSeen: history.lastRead = new Date()
        onNotificationCloseRequested: row => history.close(history.index(row, 0))
        onNotificationDefaultActionRequested: row => history.invokeDefaultAction(history.index(row, 0),
                                                                                   NotificationManager.Notifications.Close)
        onNotificationActionRequested: (row, actionName) => history.invokeAction(history.index(row, 0), actionName,
                                                                                  NotificationManager.Notifications.Close)
        onClearAllRequested: {
            for (let row = history.count - 1; row >= 0; --row) {
                history.close(history.index(row, 0));
            }
            history.clear(NotificationManager.Notifications.ClearExpired);
        }
    }

    ToastWindow {
        id: toasts
        model: popups
        iconFallback: themeIcon
        onExpireRequested: row => popups.expire(popups.index(row, 0))
        onCloseRequested: row => popups.close(popups.index(row, 0))
        onDefaultActionRequested: row => popups.invokeDefaultAction(popups.index(row, 0), NotificationManager.Notifications.Close)
        onActionRequested: (row, actionName) => popups.invokeAction(popups.index(row, 0), actionName,
                                                                     NotificationManager.Notifications.Close)
    }

    // Do not disturb until switched off; apps learn of it through the
    // notification server.
    function setDoNotDisturb(on) {
        if (on) {
            notificationSettings.notificationsInhibitedUntil = new Date(Date.now() + 10 * 365 * 24 * 3600 * 1000);
        } else {
            notificationSettings.notificationsInhibitedUntil = undefined;
        }
        notificationSettings.save();
        NotificationManager.Server.inhibited = on;
        console.info("STAROS-SHELL dnd=" + on);
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
    Plasmoid.onActivated: overlay.toggle("start")

    Component.onCompleted: {
        // Reduced motion in the platform settings turns the animations off.
        Theme.animationFactor = Kirigami.Units.longDuration / 250;
        NotificationManager.Server.inhibited = root.doNotDisturb;
        console.info("STAROS-SHELL ready shell=org.staros.shell gridUnit=" + Theme.gridUnit
            + " taskbarHeight=" + Theme.taskbarHeight + " focusRing=" + Theme.focusRingWidth
            + " animationFactor=" + Theme.animationFactor
            + " notificationServer=" + NotificationManager.Server.valid);
    }
}
