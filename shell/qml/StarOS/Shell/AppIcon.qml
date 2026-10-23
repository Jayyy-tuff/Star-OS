// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// An application's icon: the Star OS artwork for appId (Icons); otherwise the
// host's fallback component showing iconData (the Plasma adapters pass a
// Kirigami.Icon and the app's theme icon); otherwise a monogram of the name.
// Decorative: the control that shows it carries the accessible name.
Item {
    id: root

    property string appId: ""
    property string name: ""
    // The host's icon for the app, given to the fallback's iconData property.
    property var iconData: undefined
    // A Component whose root item has a property iconData; null for none.
    property Component fallback: null

    readonly property bool usesFallback: fallbackLoader.status === Loader.Ready

    implicitWidth: Theme.tileIconSize
    implicitHeight: Theme.tileIconSize

    Accessible.ignored: true

    Image {
        id: artwork
        objectName: "artwork"
        anchors.fill: parent
        source: Icons.source(root.appId)
        // Rendered at the shown size (times the pixel ratio), so it stays crisp.
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectFit
        visible: artwork.status === Image.Ready
        Accessible.ignored: true
    }

    Loader {
        id: fallbackLoader
        objectName: "fallback"
        anchors.fill: parent
        active: artwork.status !== Image.Ready && root.fallback !== null
            && root.iconData !== undefined && root.iconData !== null
        sourceComponent: root.fallback
        onLoaded: item.iconData = Qt.binding(() => root.iconData)
        Accessible.ignored: true
    }

    // Inset to the size of the artwork's tile (216 of 256 units).
    Rectangle {
        objectName: "monogram"
        anchors.fill: parent
        anchors.margins: Math.round(root.width * 0.08)
        visible: artwork.status !== Image.Ready && !root.usesFallback
        radius: Math.round(width / 4)
        color: Theme.monogram

        Text {
            objectName: "monogramLetter"
            anchors.centerIn: parent
            text: root.name.length > 0 ? root.name.charAt(0).toUpperCase() : ""
            color: Theme.text
            font.pixelSize: Math.max(1, Math.round(parent.height * 0.55))
            font.bold: true
            Accessible.ignored: true
        }
    }
}
