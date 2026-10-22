// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// A single-line text field. The owner sets Accessible.name; the placeholder
// is only a visual hint.
T.TextField {
    id: control

    implicitWidth: 10 * Theme.gridUnit
    implicitHeight: Theme.minTarget
    leftPadding: Theme.spacing
    rightPadding: Theme.spacing
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.text
    font: Theme.metrics.font
    placeholderTextColor: Theme.placeholder
    selectByMouse: true

    background: Rectangle {
        radius: Math.round(Theme.spacing / 2)
        color: Theme.searchField
        border.width: 1
        border.color: Theme.searchBorder
    }

    FocusFrame {
        visible: control.activeFocus
    }
}
