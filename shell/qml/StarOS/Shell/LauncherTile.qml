// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// One app in the start menu's grid: its icon over its name, a soft fill on
// hover and when it is the current item. Screen readers get the name and the
// generic name.
T.AbstractButton {
    id: control

    property string appName: ""
    property string genericName: ""
    property string appId: ""
    property var iconData: undefined
    property Component iconFallback: null
    property bool current: false

    text: control.appName
    implicitWidth: Theme.tileWidth
    implicitHeight: Theme.tileHeight
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.appName
    Accessible.description: control.genericName

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
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Math.round(Theme.spacing * 1.25)
            width: Theme.tileIconSize
            height: Theme.tileIconSize
            appId: control.appId
            name: control.appName
            iconData: control.iconData
            fallback: control.iconFallback
            scale: control.down ? 0.94 : control.hovered ? 1.06 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.durationShort
                    easing.type: Easing.OutCubic
                }
            }
        }

        Text {
            objectName: "label"
            anchors.top: appIcon.bottom
            anchors.topMargin: Math.round(Theme.spacing * 0.6)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            leftPadding: Theme.spacing / 2
            rightPadding: Theme.spacing / 2
            text: control.appName
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.pixelSize: Theme.smallPixelSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignTop
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
