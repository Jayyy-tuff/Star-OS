// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// A text button. Space activates it through AbstractButton; Return and Enter
// are added here. As a page tab (accessibleRole PageTab) the owner binds
// `checked` to the selected section; the indicator line shows it.
T.AbstractButton {
    id: control

    property string description: ""
    property string accessibleName: control.text
    property int accessibleRole: Accessible.Button
    // Draws the button as the main action.
    property bool primary: false

    implicitWidth: Math.max(Theme.minTarget, label.implicitWidth + 2 * Theme.spacing)
    implicitHeight: Theme.minTarget
    focusPolicy: Qt.StrongFocus
    opacity: enabled ? 1 : 0.5

    Accessible.role: control.accessibleRole
    Accessible.name: control.accessibleName
    Accessible.description: control.description
    Accessible.selectable: control.accessibleRole === Accessible.PageTab
    Accessible.selected: control.accessibleRole === Accessible.PageTab && control.checked

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
        border.width: control.primary ? 1 : 0
        border.color: Theme.activeIndicator

        Rectangle {
            visible: control.checked
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
