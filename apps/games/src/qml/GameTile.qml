// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// One game: artwork made from the name (a deep-space gradient picked by the
// name, the game's icon, or its first letter), the name and where it comes
// from. Return, Space or a click starts it.
T.AbstractButton {
    id: control

    property string name: ""
    property string iconName: ""
    property string source: "app"
    property bool emulator: false
    property bool wide: false

    readonly property string kindText: control.source === "steam" ? qsTr("Steam")
        : control.emulator ? qsTr("Emulator")
        : control.source === "flatpak" ? qsTr("Flatpak") : qsTr("App")
    // A hue from the name, so each game keeps its colours.
    readonly property real hue: {
        let h = 0;
        for (let i = 0; i < control.name.length; ++i) {
            h = (h * 31 + control.name.charCodeAt(i)) % 360;
        }
        return h / 360;
    }

    text: control.name
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.name
    Accessible.description: control.kindText

    Keys.onReturnPressed: event => {
        control.clicked();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        control.clicked();
        event.accepted = true;
    }

    background: Item {
        Rectangle {
            id: art
            objectName: "art"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: control.wide ? parent.height : parent.height - label.height - Theme.spacing / 2
            radius: Theme.panelRadius
            scale: control.down ? 0.98 : control.hovered || control.activeFocus ? 1.02 : 1
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0
                    color: Qt.hsla(control.hue, 0.55, 0.42, 1)
                }
                GradientStop {
                    position: 1
                    color: Qt.hsla((control.hue + 0.12) % 1, 0.6, 0.16, 1)
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.durationShort
                    easing.type: Easing.OutCubic
                }
            }

            // A faint star field over the gradient.
            Repeater {
                model: 6

                Rectangle {
                    required property int index

                    x: (art.width * ((index * 37 + Math.round(control.hue * 100)) % 100)) / 100
                    y: (art.height * ((index * 53 + 17) % 100)) / 100
                    width: index % 3 === 0 ? 3 : 2
                    height: width
                    radius: width / 2
                    color: "#ffffff"
                    opacity: 0.35
                }
            }

            Image {
                id: iconImage
                objectName: "icon"
                anchors.centerIn: parent
                width: Math.round(Math.min(parent.width, parent.height) * 0.42)
                height: width
                sourceSize: Qt.size(width, height)
                source: control.iconName === "" ? ""
                    : control.iconName.startsWith("/") ? "file://" + control.iconName : "image://icon/" + control.iconName
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready && implicitWidth > 0
                Accessible.ignored: true
            }

            Text {
                objectName: "letter"
                anchors.centerIn: parent
                visible: !iconImage.visible
                text: control.name.length > 0 ? control.name.charAt(0).toUpperCase() : ""
                color: "#f4f3ff"
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Math.min(art.width, art.height) * 0.38)
                font.weight: Font.Light
                Accessible.ignored: true
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 1
                border.color: Theme.glassBorder
            }

            FocusFrame {
                visible: control.activeFocus
                radius: Theme.panelRadius
            }
        }
    }

    contentItem: Item {
        Column {
            id: label
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: control.wide ? Theme.spacing : 2
            anchors.bottomMargin: control.wide ? Theme.spacing : 0
            spacing: 2

            Text {
                objectName: "name"
                width: parent.width
                text: control.name
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize)
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                style: control.wide ? Text.Raised : Text.Normal
                styleColor: "#80000000"
                Accessible.ignored: true
            }

            Text {
                objectName: "kind"
                width: parent.width
                text: control.kindText
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                elide: Text.ElideRight
                Accessible.ignored: true
            }
        }
    }
}
