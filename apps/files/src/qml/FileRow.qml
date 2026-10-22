// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// One item of the folder contents. A screen reader gets the name and the type
// (with the size for files); the row shows the same two texts.
Item {
    id: row

    required property int index
    required property string name
    required property var url
    required property bool isDir
    required property string accessibleDescription

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

        // A sheet of paper for files.
        Rectangle {
            anchors.centerIn: parent
            visible: !row.isDir
            width: Math.round(parent.width * 0.7)
            height: Math.round(parent.height * 0.9)
            radius: 2
            color: "transparent"
            border.width: 2
            border.color: Theme.text
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
