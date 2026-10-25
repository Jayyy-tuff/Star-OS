// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// A glass panel with a soft shadow, for the start menu and the tray's
// panels. While 'shown' changes it fades and slides by half a grid unit over
// Theme.durationMedium; with Theme.animationFactor 0 it changes at once.
// Children go into the panel's content item, which fills it.
Item {
    id: root

    property point wallpaperOrigin: Qt.point(0, 0)
    property size screenSize: Qt.size(root.width, root.height)
    property real radius: Theme.panelRadius
    property real tintOpacity: Theme.glassTintOpacity
    property bool shown: true

    default property alias content: contentItem.data

    visible: opacity > 0
    opacity: root.shown ? 1 : 0
    transform: Translate {
        y: root.shown ? 0 : Math.round(Theme.gridUnit / 2)

        Behavior on y {
            NumberAnimation {
                duration: Theme.durationMedium
                easing.type: Easing.OutCubic
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.durationMedium
            easing.type: Easing.OutCubic
        }
    }

    Shadow {
        anchors.fill: parent
        radius: root.radius
    }

    GlassSurface {
        objectName: "glass"
        anchors.fill: parent
        radius: root.radius
        tintOpacity: root.tintOpacity
        wallpaperOrigin: root.wallpaperOrigin
        screenSize: root.screenSize
    }

    Item {
        id: contentItem
        anchors.fill: parent
    }
}
