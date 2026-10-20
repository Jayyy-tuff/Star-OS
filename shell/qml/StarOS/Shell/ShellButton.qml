// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// A taskbar button with a text label ("Applications", "Leave"). Space activates
// it through AbstractButton; Return and Enter are added here.
T.AbstractButton {
    id: control

    property string description: ""

    implicitWidth: Math.max(Theme.minTarget, label.implicitWidth + 2 * Theme.spacing)
    implicitHeight: Theme.minTarget
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.description: control.description

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
    }

    contentItem: Text {
        id: label
        text: control.text
        color: Theme.text
        font: Theme.metrics.font
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        Accessible.ignored: true
    }

    FocusFrame {
        visible: control.activeFocus
    }
}
