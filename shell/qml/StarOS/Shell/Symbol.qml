// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// A white line symbol from symbols/ (Icons.symbol), rendered at its shown
// size. Decorative: the control that shows it carries the accessible name.
Image {
    id: root

    property string name: ""

    width: Theme.symbolSize
    height: Theme.symbolSize
    source: Icons.symbol(root.name)
    sourceSize: Qt.size(Math.max(1, root.width), Math.max(1, root.height))
    fillMode: Image.PreserveAspectFit
    smooth: true
    Accessible.ignored: true
}
