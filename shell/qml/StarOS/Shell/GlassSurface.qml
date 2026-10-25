// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// Frosted glass: the Star OS wallpaper as the desktop draws it, blurred and
// tinted. Wayland clients cannot query their position, so the host passes the
// item's top-left in screen coordinates and the screen size; the wallpaper is
// laid out at screen size and shifted by -wallpaperOrigin, so the glass shows
// the part of the wallpaper that is behind it. Without a GPU scene graph, or
// with Theme.reduceTransparency, the surface is the opaque glassFallback.
Item {
    id: root

    property point wallpaperOrigin: Qt.point(0, 0)
    property size screenSize: Qt.size(root.width, root.height)
    property real radius: Theme.glassRadius
    property real tintOpacity: Theme.glassTintOpacity

    // The API is Unknown until the item is in a window; no blur until then.
    readonly property bool blurAvailable: !Theme.reduceTransparency
        && GraphicsInfo.api !== GraphicsInfo.Software
        && GraphicsInfo.api !== GraphicsInfo.Unknown

    Accessible.ignored: true

    Rectangle {
        objectName: "glassFallback"
        anchors.fill: parent
        visible: !root.blurAvailable
        radius: root.radius
        color: Theme.glassFallback
    }

    Loader {
        anchors.fill: parent
        active: root.blurAvailable
        sourceComponent: frosted
    }

    Component {
        id: frosted

        Item {
            // A rectangular clip is enough for square corners; rounded corners
            // mask the clipped layer with a rounded rectangle.
            Item {
                anchors.fill: parent
                clip: true
                layer.enabled: root.radius > 0
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: roundedMask
                }

                // Hidden: MultiEffect renders it into its own texture.
                Image {
                    id: wallpaper
                    x: -root.wallpaperOrigin.x
                    y: -root.wallpaperOrigin.y
                    width: root.screenSize.width
                    height: root.screenSize.height
                    source: Theme.wallpaper
                    sourceSize: root.screenSize
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false
                }

                // The source never changes, so the blur is rendered once.
                // Padding would grow the effect past the screen edges.
                MultiEffect {
                    anchors.fill: wallpaper
                    source: wallpaper
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: Theme.glassBlur
                    blurMax: Theme.glassBlurMax
                    saturation: 0.2
                }
            }

            Item {
                id: roundedMask
                anchors.fill: parent
                layer.enabled: root.radius > 0
                visible: false

                Rectangle {
                    anchors.fill: parent
                    radius: root.radius
                    color: "black"
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: root.radius
                color: Theme.glassTint
                opacity: root.tintOpacity
            }
        }
    }

    // A hairline edge, a little lighter along the top, like light on glass.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.glassBorder
    }

    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(0, parent.width - 2 * root.radius)
        height: 1
        color: Theme.glassHighlight
    }
}
