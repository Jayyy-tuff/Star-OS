// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// The Star button: the Star OS logo; opens the start menu. 'checked' while
// the menu is open.
T.AbstractButton {
    id: control

    property string description: qsTr("Open the application launcher")

    text: qsTr("Applications")
    implicitWidth: Theme.taskbarButtonSize
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
        Image {
            objectName: "logo"
            anchors.centerIn: parent
            width: Theme.taskIconSize
            height: Theme.taskIconSize
            source: Icons.logo
            sourceSize: Qt.size(width, height)
            scale: control.down ? 0.92 : control.hovered ? 1.08 : 1
            Accessible.ignored: true

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.durationShort
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
