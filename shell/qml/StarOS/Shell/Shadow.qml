// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Effects

// A soft shadow under a rounded surface of the same size, drawn only with a
// GPU scene graph (the software one has no effects). The surface drawn over
// it covers the shape itself.
Item {
    id: root

    property real radius: Theme.panelRadius
    property real offsetY: Math.round(Theme.gridUnit / 3)

    readonly property bool available: !Theme.reduceTransparency
        && GraphicsInfo.api !== GraphicsInfo.Software
        && GraphicsInfo.api !== GraphicsInfo.Unknown

    Accessible.ignored: true

    Rectangle {
        id: shape
        anchors.fill: parent
        radius: root.radius
        color: Theme.shadow
        visible: false
    }

    MultiEffect {
        anchors.fill: shape
        source: shape
        visible: root.available
        shadowEnabled: true
        shadowColor: Theme.shadow
        shadowBlur: 1.0
        shadowVerticalOffset: root.offsetY
        shadowOpacity: 0.85
        blurMax: 48
    }
}
