// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// Visible keyboard focus. The parent binds `visible` to its own activeFocus (not
// visualFocus: item views focus their current item without a Tab reason).
Rectangle {
    anchors.fill: parent
    color: "transparent"
    border.width: Theme.focusRingWidth
    border.color: Theme.focusRing
    radius: 0
    z: 100
}
