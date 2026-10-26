// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// A desktop widget's glass card: a small heading with a symbol, then the
// widget's content (children go into a column under the heading). The host
// passes the card's top-left in screen coordinates for the glass.
Item {
    id: root

    property string title: ""
    property string symbol: ""
    property point wallpaperOrigin: Qt.point(0, 0)
    property size screenSize: Qt.size(root.width, root.height)

    default property alias content: body.data

    implicitWidth: Math.round(15 * Theme.gridUnit)
    implicitHeight: column.implicitHeight + 2 * Theme.panelPadding * 0.8

    Accessible.role: Accessible.Grouping
    Accessible.name: root.title

    Shadow {
        anchors.fill: parent
        radius: Theme.panelRadius
    }

    GlassSurface {
        objectName: "glass"
        anchors.fill: parent
        radius: Theme.panelRadius
        tintOpacity: Theme.glassTintOpacity
        wallpaperOrigin: root.wallpaperOrigin
        screenSize: root.screenSize
    }

    Column {
        id: column
        x: Math.round(Theme.panelPadding * 0.8)
        y: Math.round(Theme.panelPadding * 0.8)
        width: root.width - 2 * x
        spacing: Math.round(Theme.spacing * 0.75)

        Row {
            spacing: Math.round(Theme.spacing / 2)

            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(Theme.symbolSize * 0.8)
                height: width
                name: root.symbol
                opacity: 0.8
            }

            Text {
                objectName: "title"
                anchors.verticalCenter: parent.verticalCenter
                text: root.title.toUpperCase()
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                Accessible.ignored: true
            }
        }

        Column {
            id: body
            width: parent.width
            spacing: Math.round(Theme.spacing / 2)
        }
    }
}
