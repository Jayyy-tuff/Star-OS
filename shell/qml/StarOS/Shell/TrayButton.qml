// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// The tray: network, volume and battery symbols in one button that opens
// quick settings. The host picks the symbols; the description says the
// state in words. 'checked' while quick settings is open.
T.AbstractButton {
    id: control

    property string networkSymbol: "wired"
    property string volumeSymbol: "volume"
    property bool batteryPresent: false
    property int batteryPercent: 0
    property string description: ""

    text: qsTr("Quick settings")
    implicitWidth: symbols.implicitWidth + 2 * Theme.spacing
    implicitHeight: Theme.taskbarButtonSize
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.description: control.description

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
            : control.checked ? Theme.glassButtonActive
            : control.hovered ? Theme.glassButton : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: Theme.durationShort
            }
        }
    }

    contentItem: Item {
        Row {
            id: symbols
            anchors.centerIn: parent
            spacing: Math.round(0.6 * Theme.spacing)

            Symbol {
                objectName: "networkSymbol"
                name: control.networkSymbol
                visible: control.networkSymbol !== ""
            }

            Symbol {
                objectName: "volumeSymbol"
                name: control.volumeSymbol
                visible: control.volumeSymbol !== ""
            }

            Symbol {
                objectName: "batterySymbol"
                name: "battery"
                visible: control.batteryPresent
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
