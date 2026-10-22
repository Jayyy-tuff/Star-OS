// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// One app in the list: icon, name, summary and its state. A screen reader gets
// the name, and the summary with the state as the description.
Item {
    id: row

    required property int index
    required property string appId
    required property string name
    required property string summary
    required property url iconUrl
    required property bool installed
    required property bool updateAvailable

    readonly property string stateText: row.updateAvailable ? qsTr("Update available")
                                                            : row.installed ? qsTr("Installed") : ""

    signal clicked()
    signal activated()

    implicitHeight: Math.max(Theme.minTarget, Math.round(3 * Theme.gridUnit))

    Accessible.role: Accessible.ListItem
    Accessible.name: row.name
    Accessible.description: row.stateText !== "" ? qsTr("%1. %2").arg(row.summary).arg(row.stateText) : row.summary
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
        width: Math.round(2 * Theme.gridUnit)
        height: width

        Image {
            id: picture
            objectName: "picture"
            anchors.fill: parent
            source: row.iconUrl
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            visible: picture.status === Image.Ready
            Accessible.ignored: true
        }

        AppIcon {
            anchors.fill: parent
            visible: picture.status !== Image.Ready
            name: row.name
        }
    }

    Column {
        anchors.left: icon.right
        anchors.leftMargin: Theme.spacing
        anchors.right: stateLabel.left
        anchors.rightMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: row.name
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.bold: true
            elide: Text.ElideRight
            Accessible.ignored: true
        }

        Text {
            width: parent.width
            text: row.summary
            color: Theme.placeholder
            font: Theme.metrics.font
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }

    Text {
        id: stateLabel
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        text: row.stateText
        color: row.updateAvailable ? Theme.activeIndicator : Theme.text
        font: Theme.metrics.font
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
