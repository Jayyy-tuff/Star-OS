// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// A text button for the tool bar and dialogs. Space activates it through
// AbstractButton; Return and Enter are added here. With `toggle` set it is a
// check box (AbstractButton flips `checked` before emitting clicked); the
// owner binds `checked` to its state and writes the state back in onClicked.
T.AbstractButton {
    id: control

    property string description: ""
    property bool toggle: false

    implicitWidth: Math.max(Theme.minTarget, label.implicitWidth + 2 * Theme.spacing)
    implicitHeight: Theme.minTarget
    checkable: control.toggle
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: control.toggle ? Accessible.CheckBox : Accessible.Button
    Accessible.name: control.text
    Accessible.description: control.description

    Keys.onReturnPressed: event => {
        control.click();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        control.click();
        event.accepted = true;
    }

    background: Rectangle {
        radius: Math.round(Theme.spacing / 2)
        color: control.down || control.checked ? Theme.taskbarButtonPressed : Theme.taskbarButton

        Rectangle {
            visible: control.toggle && control.checked
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.activeIndicatorHeight
            color: Theme.activeIndicator
        }
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
