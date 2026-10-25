// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// A quick settings tile: a symbol in a small square, a label and the state
// under it. 'checked' tiles use the accent. The host binds 'checked' to the
// setting and acts on clicked (Space, Return or a click); the tile never
// changes 'checked' itself. Switch tiles are check boxes for screen readers.
T.AbstractButton {
    id: control

    property string symbol: ""
    property string stateText: ""
    property bool isSwitch: false

    implicitWidth: 10 * Theme.gridUnit
    implicitHeight: Math.round(3.4 * Theme.gridUnit)
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: control.isSwitch ? Accessible.CheckBox : Accessible.Button
    Accessible.name: control.text
    Accessible.description: control.stateText
    Accessible.checkable: control.isSwitch
    Accessible.checked: control.checked

    Keys.onReturnPressed: event => {
        control.clicked();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        control.clicked();
        event.accepted = true;
    }

    background: Rectangle {
        radius: Theme.controlRadius * 1.3
        color: control.down ? Theme.glassButtonPressed
            : control.hovered ? Theme.glassButton : Theme.tileGlass
        border.width: 1
        border.color: Theme.glassBorder
        opacity: control.enabled ? 1 : 0.5

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: control.checked
            opacity: control.down ? 0.85 : 1
            gradient: Theme.accentGradient
        }
    }

    contentItem: Item {
        Rectangle {
            id: symbolBox
            anchors.left: parent.left
            anchors.leftMargin: Math.round(Theme.spacing * 0.75)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(2 * Theme.gridUnit)
            height: width
            radius: Theme.controlRadius
            color: control.checked ? "#38ffffff" : Theme.glassButton

            Symbol {
                anchors.centerIn: parent
                name: control.symbol
            }
        }

        Column {
            anchors.left: symbolBox.right
            anchors.leftMargin: Math.round(Theme.spacing * 0.75)
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing / 2
            anchors.verticalCenter: parent.verticalCenter

            Text {
                objectName: "label"
                width: parent.width
                text: control.text
                color: control.checked ? Theme.accentText : Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Accessible.ignored: true
            }

            Text {
                objectName: "state"
                width: parent.width
                visible: text !== ""
                text: control.stateText
                color: control.checked ? Theme.accentText : Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                elide: Text.ElideRight
                Accessible.ignored: true
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius * 1.3
    }
}
