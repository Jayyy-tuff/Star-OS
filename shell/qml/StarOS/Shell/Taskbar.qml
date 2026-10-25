// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import "status.js" as Status

// The Star OS taskbar (M0.5): a glass pill centred at the bottom of its
// panel, taskbarGap above the edge, with the Star button, the apps (pinned
// and open windows, icons only), the tray, the clock and the notifications.
// It only emits requests; the host (Plasma adapter, or a test) acts on them.
// Escape is deliberately not handled, so the host panel can restore focus to
// the previous window.
FocusScope {
    id: root

    // One row per pinned app or window, with the roles 'display' (title),
    // 'AppName', 'AppId', 'decoration', 'IsActive' and 'IsWindow' (false for a
    // pinned app without a window). Roles may be missing; they are read
    // defensively.
    property var tasksModel: null
    // Where the taskbar item is on its screen, for the glass. The defaults
    // assume a full-width panel at the bottom edge.
    property point glassOrigin: Qt.point(0, Screen.height - root.height)
    property size glassScreenSize: Qt.size(Screen.width, Screen.height)
    // Shows an app's own icon when Star OS has no artwork for it (AppIcon).
    property Component iconFallback: null
    // StarOS.System's SystemStatus or a plain object: the tray's description.
    property var systemStatus: null
    // The tray's symbols, chosen by the host, and words added to its
    // description (the network and the volume).
    property string networkSymbol: "wired"
    property string volumeSymbol: "volume"
    property string trayDetail: ""
    property int unreadNotifications: 0
    property bool doNotDisturb: false
    // Which panel is open, for the buttons' checked state.
    property bool startMenuOpen: false
    property bool quickSettingsOpen: false
    property bool calendarOpen: false

    // The pill's right end in the taskbar's coordinates: the tray's panels
    // line up with it.
    readonly property real pillRight: pill.x + pill.width

    signal launcherRequested()
    signal activateRequested(int row)
    signal quickSettingsRequested()
    signal calendarRequested()
    signal notificationsRequested()

    implicitHeight: Theme.taskbarHeight
    implicitWidth: pill.width

    Accessible.role: Accessible.ToolBar
    Accessible.name: qsTr("Taskbar")

    Item {
        id: pill
        objectName: "pill"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.taskbarGap
        width: Math.min(root.width, row.width + 2 * pill.padding)
        height: Theme.taskbarPillHeight

        readonly property int padding: Math.round((Theme.taskbarPillHeight - Theme.taskbarButtonSize) / 2)

        Shadow {
            anchors.fill: parent
            radius: Theme.taskbarRadius
        }

        GlassSurface {
            objectName: "glass"
            anchors.fill: parent
            radius: Theme.taskbarRadius
            tintOpacity: Theme.taskbarTintOpacity
            wallpaperOrigin: Qt.point(root.glassOrigin.x + pill.x, root.glassOrigin.y + pill.y)
            screenSize: root.glassScreenSize
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: Math.round(Theme.spacing / 3)

            // Everything but the apps, for the apps' share of the width.
            readonly property real fixedWidth: startButton.width + trayButton.width + clockButton.width
                + notificationButton.width + 2 * separatorLeft.width + 6 * spacing

            StartButton {
                id: startButton
                objectName: "applicationsButton"
                focus: true
                checked: root.startMenuOpen
                KeyNavigation.right: apps.count > 0 ? apps : trayButton
                onClicked: root.launcherRequested()
            }

            Rectangle {
                id: separatorLeft
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: Math.round(Theme.taskbarButtonSize * 0.55)
                color: Theme.glassBorder
                visible: apps.count > 0
            }

            ListView {
                id: apps
                objectName: "openWindows"
                width: Math.min(apps.contentWidth, Math.max(0, root.width - 2 * pill.padding - row.fixedWidth))
                height: Theme.taskbarButtonSize
                orientation: ListView.Horizontal
                spacing: row.spacing
                clip: true
                model: root.tasksModel
                activeFocusOnTab: count > 0
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                visible: count > 0

                // Arrow keys move within the list first; at either end they move on.
                KeyNavigation.priority: KeyNavigation.AfterItem
                KeyNavigation.left: startButton
                KeyNavigation.right: trayButton

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Apps")

                delegate: TaskButton {
                    id: task

                    required property var model
                    required property int index

                    title: task.model.display ?? ""
                    appName: task.model.AppName ?? ""
                    appId: task.model.AppId ?? ""
                    iconData: task.model.decoration
                    iconFallback: root.iconFallback
                    isActive: task.model.IsActive === true
                    isWindow: task.model.IsWindow !== false
                    onClicked: {
                        apps.currentIndex = task.index;
                        root.activateRequested(task.index);
                    }
                }

                onCountChanged: {
                    if (count === 0 && activeFocus) {
                        startButton.forceActiveFocus(Qt.TabFocusReason);
                    }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: separatorLeft.height
                color: Theme.glassBorder
            }

            TrayButton {
                id: trayButton
                objectName: "trayButton"
                checked: root.quickSettingsOpen
                networkSymbol: root.networkSymbol
                volumeSymbol: root.volumeSymbol
                batteryPresent: root.systemStatus ? root.systemStatus.batteryPresent === true : false
                batteryPercent: Status.value(root.systemStatus, "batteryPercent")
                description: [Status.summary(root.systemStatus), root.trayDetail].filter(part => part !== "").join(" ")
                KeyNavigation.left: apps.count > 0 ? apps : startButton
                KeyNavigation.right: clockButton
                onClicked: root.quickSettingsRequested()
            }

            ClockButton {
                id: clockButton
                objectName: "clockButton"
                checked: root.calendarOpen
                KeyNavigation.left: trayButton
                KeyNavigation.right: notificationButton
                onClicked: root.calendarRequested()
            }

            NotificationButton {
                id: notificationButton
                objectName: "notificationButton"
                unreadCount: root.unreadNotifications
                doNotDisturb: root.doNotDisturb
                KeyNavigation.left: clockButton
                onClicked: root.notificationsRequested()
            }
        }
    }
}
