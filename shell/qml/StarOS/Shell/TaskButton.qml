// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// One app in the taskbar: its icon only. A pinned app that is not running
// has no mark; a running one a dot below; the active window a wider bar in
// the indicator colour. The accessible name is the window title (or the app
// name), the description its state.
T.AbstractButton {
    id: control

    property string title: ""
    property string appName: ""
    property string appId: ""
    property var iconData: undefined
    property Component iconFallback: null
    property bool isActive: false
    // False for a pinned app that has no window.
    property bool isWindow: true

    text: control.title !== "" ? control.title : control.appName
    implicitWidth: Theme.taskbarButtonSize
    implicitHeight: Theme.taskbarButtonSize
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.description: !control.isWindow ? qsTr("Pinned app")
        : control.isActive ? qsTr("Active window") : qsTr("Window")

    Keys.onReturnPressed: event => {
        control.clicked();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        control.clicked();
        event.accepted = true;
    }

    background: Rectangle {
        radius: Theme.controlRadius
        color: control.down ? Theme.glassButtonPressed
            : control.isActive ? Theme.glassButtonActive
            : control.hovered ? Theme.glassButton
            : control.isWindow ? Theme.tileGlass : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.durationShort
            }
        }
    }

    contentItem: Item {
        AppIcon {
            id: appIcon
            objectName: "icon"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Math.round(Theme.activeIndicatorHeight / 2)
            width: Theme.taskIconSize
            height: Theme.taskIconSize
            appId: control.appId
            iconData: control.iconData
            fallback: control.iconFallback
            name: control.appName !== "" ? control.appName : control.title
            scale: control.down ? 0.92 : control.hovered ? 1.08 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.durationShort
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Rectangle {
        objectName: "indicator"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(Theme.activeIndicatorHeight / 2)
        visible: control.isWindow
        height: Theme.activeIndicatorHeight
        width: control.isActive ? Math.round(0.9 * Theme.gridUnit) : Theme.activeIndicatorHeight + 2
        radius: height / 2
        color: control.isActive ? Theme.activeIndicator : Theme.textTertiary

        Behavior on width {
            NumberAnimation {
                duration: Theme.durationShort
                easing.type: Easing.OutCubic
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
