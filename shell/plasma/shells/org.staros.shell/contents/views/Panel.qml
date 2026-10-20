// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// Panel view of the Star OS shell: hosts the taskbar containment and keeps the
// PanelView's thickness equal to the font-derived Theme.taskbarHeight.
// 'panel' is the PanelView context property set by plasmashell.
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
        panel.backgroundHints = containment.plasmoid.backgroundHints;
        panel.thickness = Theme.taskbarHeight;
    }
}
