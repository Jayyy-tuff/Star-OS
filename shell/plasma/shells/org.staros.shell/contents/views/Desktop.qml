// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// Desktop view of the Star OS shell: hosts the desktop containment full size.
Item {
    id: root

    property Item containment

    onContainmentChanged: {
        if (!containment) {
            return;
        }
        containment.parent = root;
        containment.anchors.fill = root;
        containment.visible = true;
    }
}
