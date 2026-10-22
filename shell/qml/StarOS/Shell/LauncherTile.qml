// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// One application in the launcher: its icon (AppIcon) and name on a glass
// tile. Screen readers get the name and the generic name.
T.AbstractButton {
    id: control

    property string appName: ""
    property string genericName: ""
    property string appId: ""

    text: control.appName
    implicitWidth: Theme.tileWidth
    implicitHeight: Theme.tileHeight
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: control.appName
    Accessible.description: control.genericName

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
        color: control.down ? Theme.glassButtonPressed : Theme.tileGlass
    }

    contentItem: Item {
        AppIcon {
            id: appIcon
            objectName: "icon"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.spacing
            width: Theme.tileIconSize
            height: Theme.tileIconSize
            appId: control.appId
            name: control.appName
        }

        Text {
            objectName: "label"
            anchors.top: appIcon.bottom
            anchors.topMargin: Theme.spacing / 4
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            leftPadding: Theme.spacing / 2
            rightPadding: Theme.spacing / 2
            text: control.appName
            color: Theme.text
            font: Theme.metrics.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
