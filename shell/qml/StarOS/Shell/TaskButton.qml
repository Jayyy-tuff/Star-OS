// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// One open window in the taskbar. The label elides; the full title stays in
// the accessible name.
T.AbstractButton {
    id: control

    property string title: ""
    property string appName: ""
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
        color: control.down ? Theme.taskbarButtonPressed : Theme.taskbarButton

        Rectangle {
            visible: control.isActive
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.activeIndicatorHeight
            color: Theme.activeIndicator
        }
    }

    contentItem: Text {
        objectName: "label"
        text: control.text
        color: Theme.text
        font: Theme.metrics.font
        elide: Text.ElideRight
        leftPadding: Theme.spacing
        rightPadding: Theme.spacing
        verticalAlignment: Text.AlignVCenter
        Accessible.ignored: true
    }

    FocusFrame {
        visible: control.activeFocus
    }
}
