// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// The bell: opens the notification centre; a badge shows the unread count,
// a struck bell Do not disturb.
T.AbstractButton {
    id: control

    property int unreadCount: 0
    property bool doNotDisturb: false

    text: qsTr("Notifications")
    implicitWidth: Math.round(Theme.taskbarButtonSize * 0.9)
    implicitHeight: Theme.taskbarButtonSize
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.description: control.doNotDisturb ? qsTr("Do not disturb is on")
        : control.unreadCount > 0 ? qsTr("%n unread", "", control.unreadCount) : qsTr("No new notifications")

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
            : control.checked ? Theme.glassButtonActive
            : control.hovered ? Theme.glassButton : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.durationShort
            }
        }
    }

    contentItem: Item {
        Symbol {
            anchors.centerIn: parent
            name: control.doNotDisturb ? "bell-off" : "bell"
        }

        Rectangle {
            objectName: "badge"
            visible: control.unreadCount > 0 && !control.doNotDisturb
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: Math.round(Theme.spacing / 2)
            anchors.topMargin: Math.round(Theme.spacing / 2)
            height: Math.round(0.9 * Theme.gridUnit)
            width: Math.max(height, badgeText.implicitWidth + Math.round(Theme.spacing / 2))
            radius: height / 2
            gradient: Theme.accentGradient

            Text {
                id: badgeText
                anchors.centerIn: parent
                text: control.unreadCount > 99 ? "99+" : String(control.unreadCount)
                color: Theme.accentText
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.max(9, Math.round(Theme.smallPixelSize * 0.85))
                font.weight: Font.Bold
                Accessible.ignored: true
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
