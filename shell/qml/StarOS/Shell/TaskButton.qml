// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// One open window in the taskbar: a small application icon and the title. The
// label elides; the full title stays in the accessible name.
T.AbstractButton {
    id: control

    property string title: ""
    property string appName: ""
    property string appId: ""
    property var iconData: undefined
    property Component iconFallback: null
    property bool isActive: false

    text: control.title !== "" ? control.title : control.appName
    implicitWidth: Theme.taskButtonWidth
    implicitHeight: Theme.minTarget
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.description: control.isActive ? qsTr("Active window") : qsTr("Window")

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
            : control.isActive ? Theme.glassButtonActive : Theme.glassButton

        Rectangle {
            visible: control.isActive
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: parent.width - 2 * Theme.controlRadius
            height: Theme.activeIndicatorHeight
            radius: height / 2
            color: Theme.activeIndicator
        }
    }

    contentItem: Item {
        AppIcon {
            id: appIcon
            objectName: "icon"
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.taskIconSize
            height: Theme.taskIconSize
            appId: control.appId
            iconData: control.iconData
            fallback: control.iconFallback
            name: control.appName !== "" ? control.appName : control.title
        }

        Text {
            objectName: "label"
            anchors.left: appIcon.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            leftPadding: Theme.spacing / 2
            rightPadding: Theme.spacing
            text: control.text
            color: Theme.text
            font: Theme.metrics.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            Accessible.ignored: true
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
