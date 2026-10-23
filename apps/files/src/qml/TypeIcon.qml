// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// A sheet of paper with a coloured band naming the kind of file (fileinfo.js
// kindOf): IMG, AUD, VID, TXT, DOC or ZIP; plain for anything else.
Item {
    id: icon

    property string kind: "other"

    readonly property var bands: ({
        image: {label: "IMG", color: "#3f8f6e"},
        audio: {label: "AUD", color: "#8f5aa8"},
        video: {label: "VID", color: "#b5563f"},
        text: {label: "TXT", color: "#5a6f8f"},
        document: {label: "DOC", color: "#2f6fb3"},
        archive: {label: "ZIP", color: "#9a7a2c"}
    })
    readonly property var band: icon.bands[icon.kind] ?? null

    Accessible.ignored: true

    Rectangle {
        id: page
        anchors.centerIn: parent
        width: Math.round(icon.width * 0.72)
        height: Math.round(icon.height * 0.92)
        radius: 2
        color: "transparent"
        border.width: 2
        border.color: Theme.text
    }

    Rectangle {
        anchors.left: page.left
        anchors.right: page.right
        anchors.bottom: page.bottom
        anchors.margins: 2
        height: Math.round(page.height * 0.42)
        visible: icon.band !== null
        color: icon.band ? icon.band.color : "transparent"

        Text {
            anchors.centerIn: parent
            text: icon.band ? icon.band.label : ""
            color: "#ffffff"
            font.family: Theme.metrics.font.family
            font.bold: true
            font.pixelSize: Math.max(6, Math.round(parent.height * 0.62))
        }
    }
}
