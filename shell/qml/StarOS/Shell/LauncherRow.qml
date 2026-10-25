// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// One app as a row: icon, name (with a "NEW" badge for apps installed in the
// last days that were not opened yet) and a second line. For the start menu's
// search results, "All apps" and "Recently installed".
T.AbstractButton {
    id: control

    property string appName: ""
    property string detail: ""
    property string appId: ""
    property var iconData: undefined
    property Component iconFallback: null
    property bool isNew: false

    text: control.appName
    implicitWidth: 16 * Theme.gridUnit
    implicitHeight: Theme.rowHeight
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.appName
    Accessible.description: control.isNew ? qsTr("New. %1").arg(control.detail) : control.detail

    Keys.onReturnPressed: event => {
        control.clicked();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        control.clicked();
        event.accepted = true;
    }

    background: Rectangle {
        radius: Theme.controlRadius
        color: control.down ? Theme.glassButtonPressed
            : control.hovered || control.activeFocus ? Theme.glassButton : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.durationShort
            }
        }
    }

    contentItem: Item {
        AppIcon {
            id: appIcon
            objectName: "icon"
            anchors.left: parent.left
            anchors.leftMargin: Math.round(Theme.spacing * 0.75)
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.rowIconSize
            height: Theme.rowIconSize
            appId: control.appId
            name: control.appName
            iconData: control.iconData
            fallback: control.iconFallback
        }

        Column {
            anchors.left: appIcon.right
            anchors.leftMargin: Theme.spacing
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Row {
                width: parent.width
                spacing: Math.round(Theme.spacing / 2)

                Text {
                    id: nameLabel
                    objectName: "label"
                    width: Math.min(implicitWidth, parent.width - (badge.visible ? badge.width + parent.spacing : 0))
                    text: control.appName
                    color: Theme.text
                    font: Theme.metrics.font
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }

                Rectangle {
                    id: badge
                    objectName: "newBadge"
                    visible: control.isNew
                    anchors.verticalCenter: nameLabel.verticalCenter
                    width: badgeLabel.implicitWidth + Theme.spacing
                    height: badgeLabel.implicitHeight + 2
                    radius: Math.round(height / 3)
                    color: Theme.glassButtonActive
                    border.width: 1
                    border.color: Theme.activeIndicator

                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: qsTr("NEW")
                        color: Theme.text
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Math.max(9, Theme.smallPixelSize - 2)
                        font.weight: Font.Bold
                        font.letterSpacing: 0.5
                        Accessible.ignored: true
                    }
                }
            }

            Text {
                objectName: "detail"
                width: parent.width
                visible: text !== ""
                text: control.detail
                color: Theme.textTertiary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                elide: Text.ElideRight
                Accessible.ignored: true
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
