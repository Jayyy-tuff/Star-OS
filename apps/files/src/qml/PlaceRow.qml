// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// One place in the sidebar (Home, Documents, Trash, ...).
Item {
    id: place

    required property int index
    required property string name
    required property var url

    signal clicked()

    implicitHeight: Theme.minTarget

    Accessible.role: Accessible.ListItem
    Accessible.name: place.name
    Accessible.selectable: true
    Accessible.selected: place.ListView.isCurrentItem

    Rectangle {
        anchors.fill: parent
        radius: Math.round(Theme.spacing / 2)
        color: place.ListView.isCurrentItem ? Theme.tile : "transparent"
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacing
        anchors.rightMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: place.name
        color: Theme.text
        font: Theme.metrics.font
        elide: Text.ElideRight
        Accessible.ignored: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: place.clicked()
    }

    FocusFrame {
        objectName: "focusFrame"
        visible: place.activeFocus
    }
}
