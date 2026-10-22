// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick

// The Star OS taskbar: Applications button, open windows, Leave button.
// It only emits requests; the host (Plasma adapter, or a test) acts on them.
// Escape is deliberately not handled, so the host panel can restore focus to
// the previous window.
FocusScope {
    id: root

    // A model with one row per window and the roles 'display' (title),
    // 'AppName', 'AppId' and 'IsActive'. Roles may be missing; they are read
    // defensively.
    property var tasksModel: null
    // Where the taskbar is on its screen, for the glass. The defaults assume a
    // full-width taskbar at the bottom edge.
    property point glassOrigin: Qt.point(0, Screen.height - root.height)
    property size glassScreenSize: Qt.size(Screen.width, Screen.height)

    signal launcherRequested()
    signal activateRequested(int row)
    signal leaveRequested()

    implicitHeight: Theme.taskbarHeight
    implicitWidth: 3 * Theme.startButtonWidth

    Accessible.role: Accessible.ToolBar
    Accessible.name: qsTr("Taskbar")

    // One pixel wider on each side and taller at the bottom, so that at the
    // screen edges only the top edge line of the glass shows.
    GlassSurface {
        objectName: "glass"
        x: -1
        y: 0
        width: root.width + 2
        height: root.height + 1
        radius: 0
        wallpaperOrigin: Qt.point(root.glassOrigin.x - 1, root.glassOrigin.y)
        screenSize: root.glassScreenSize
    }

    ShellButton {
        id: applicationsButton
        objectName: "applicationsButton"
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.startButtonWidth
        height: root.height - Theme.spacing
        focus: true
        text: qsTr("Applications")
        description: qsTr("Open the application launcher")
        KeyNavigation.right: openWindows.count > 0 ? openWindows : leaveButton
        onClicked: root.launcherRequested()
    }

    ListView {
        id: openWindows
        objectName: "openWindows"
        anchors.left: applicationsButton.right
        anchors.right: leaveButton.left
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        orientation: ListView.Horizontal
        spacing: Theme.spacing / 2
        clip: true
        model: root.tasksModel
        activeFocusOnTab: count > 0
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentWidth > width

        // Arrow keys move within the list first; at either end they move on.
        KeyNavigation.priority: KeyNavigation.AfterItem
        KeyNavigation.left: applicationsButton
        KeyNavigation.right: leaveButton

        Accessible.role: Accessible.List
        Accessible.name: qsTr("Open windows")
        Accessible.description: count === 0 ? qsTr("No open windows") : ""

        // Buttons shrink to share the space, down to two target sizes, and the
        // list scrolls beyond that.
        readonly property real buttonWidth: count === 0 ? Theme.taskButtonWidth
            : Math.max(2 * Theme.minTarget,
                       Math.min(Theme.taskButtonWidth, (width - (count - 1) * spacing) / count))

        delegate: TaskButton {
            id: task

            required property var model
            required property int index

            width: openWindows.buttonWidth
            height: openWindows.height - Theme.spacing
            y: Theme.spacing / 2
            title: task.model.display ?? ""
            appName: task.model.AppName ?? ""
            appId: task.model.AppId ?? ""
            isActive: task.model.IsActive === true
            onClicked: {
                openWindows.currentIndex = task.index;
                root.activateRequested(task.index);
            }
        }

        onCountChanged: {
            if (count === 0 && activeFocus) {
                applicationsButton.forceActiveFocus(Qt.TabFocusReason);
            }
        }
    }

    ShellButton {
        id: leaveButton
        objectName: "leaveButton"
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing / 2
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Theme.minTarget * 2, implicitWidth)
        height: root.height - Theme.spacing
        text: qsTr("Leave")
        description: qsTr("Log out, restart or shut down")
        KeyNavigation.left: openWindows.count > 0 ? openWindows : applicationsButton
        onClicked: root.leaveRequested()
    }
}
