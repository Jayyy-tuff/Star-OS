// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// One application in the launcher: a monogram (no icon themes in M0.2) and
// the application name. Screen readers get the name and the generic name.
T.AbstractButton {
    id: control

    property string appName: ""
    property string genericName: ""

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
        color: control.down ? Theme.taskbarButtonPressed : Theme.tile
    }

    contentItem: Item {
        Rectangle {
            id: monogram
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.spacing
            width: Theme.monogramSize
            height: Theme.monogramSize
            color: Theme.monogram

            Text {
                anchors.centerIn: parent
                text: control.appName.length > 0 ? control.appName.charAt(0).toUpperCase() : ""
                color: Theme.text
                font.pixelSize: Math.round(Theme.monogramSize * 0.55)
                font.bold: true
                Accessible.ignored: true
            }
        }

        Text {
            objectName: "label"
            anchors.top: monogram.bottom
            anchors.topMargin: Theme.spacing / 2
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
    }
}
