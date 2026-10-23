// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell
import "fileinfo.js" as FileInfo

// One item of the folder contents. A screen reader gets the name and the type
// (with the size for files); the row shows the same two texts, a type icon,
// and a thumbnail for small local images.
Item {
    id: row

    required property int index
    required property string name
    required property var url
    required property bool isDir
    required property string accessibleDescription
    required property string mimeType
    required property var size

    readonly property string kind: FileInfo.kindOf(row.mimeType, row.isDir)

    signal clicked()
    signal activated()

    implicitHeight: Theme.minTarget

    Accessible.role: Accessible.ListItem
    Accessible.name: row.name
    Accessible.description: row.accessibleDescription
    Accessible.selectable: true
    Accessible.selected: row.ListView.isCurrentItem

    Rectangle {
        anchors.fill: parent
        radius: Math.round(Theme.spacing / 2)
        color: row.ListView.isCurrentItem ? Theme.tile : "transparent"
    }

    Item {
        id: icon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(1.5 * Theme.gridUnit)
        height: width

        AppIcon {
            anchors.fill: parent
            visible: row.isDir
            appId: "org.staros.files"
            name: row.name
        }

        TypeIcon {
            anchors.fill: parent
            visible: !row.isDir && thumbnail.status !== Image.Ready
            kind: row.kind
        }

        Image {
            id: thumbnail
            objectName: "thumbnail"
            anchors.fill: parent
            visible: status === Image.Ready
            source: !row.isDir && FileInfo.canThumbnail(row.mimeType, row.size, row.url) ? row.url : ""
            sourceSize: Qt.size(2 * width, 2 * height)
            asynchronous: true
            cache: false
            fillMode: Image.PreserveAspectFit
            Accessible.ignored: true
        }
    }

    Text {
        anchors.left: icon.right
        anchors.leftMargin: Theme.spacing
        anchors.right: details.left
        anchors.rightMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: row.name
        color: Theme.text
        font: Theme.metrics.font
        elide: Text.ElideMiddle
        Accessible.ignored: true
    }

    Text {
        id: details
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.round(parent.width * 0.4))
        text: row.accessibleDescription
        color: Theme.text
        font: Theme.metrics.font
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        Accessible.ignored: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: row.clicked()
        onDoubleClicked: row.activated()
    }

    FocusFrame {
        objectName: "focusFrame"
        visible: row.activeFocus
    }
}
