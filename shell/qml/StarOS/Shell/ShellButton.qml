// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// A button with a text label and/or a symbol. Filled by default; 'flat'
// buttons (the taskbar, menus) show a fill only when hovered, checked or
// pressed; 'highlighted' buttons use the accent. Space activates it through
// AbstractButton; Return and Enter are added here.
T.AbstractButton {
    id: control

    property string description: ""
    property string symbol: ""
    property bool flat: false
    property bool highlighted: false
    property bool iconOnly: false
    property real radius: Theme.controlRadius
    // Qt.AlignHCenter (default) or Qt.AlignLeft, for menu items.
    property int horizontalAlignment: Qt.AlignHCenter

    implicitWidth: Math.max(Theme.minTarget, content.implicitWidth + (content.hasText ? 2 * Theme.spacing : 0))
    implicitHeight: Theme.minTarget
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
        objectName: "background"
        radius: control.radius
        color: control.down ? Theme.glassButtonPressed
            : control.checked ? Theme.glassButtonActive
            : control.hovered ? Theme.glassButton
            : control.flat ? "transparent" : Theme.glassButton

        Behavior on color {
            ColorAnimation {
                duration: Theme.durationShort
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: control.highlighted
            opacity: control.down ? 0.85 : 1
            gradient: Theme.accentGradient
        }
    }

    // The symbol and the label are centred together; the label elides when
    // the button is narrower than both.
    contentItem: Item {
        id: content

        readonly property bool hasSymbol: control.symbol !== ""
        readonly property bool hasText: !control.iconOnly && control.text !== ""
        readonly property real gap: hasSymbol && hasText ? Math.round(Theme.spacing * 0.75) : 0
        readonly property real symbolWidth: hasSymbol ? Theme.symbolSize : 0
        readonly property real groupWidth: Math.min(implicitWidth, width - (control.horizontalAlignment === Qt.AlignLeft ? 2 * Theme.spacing : 0))
        readonly property real groupX: control.horizontalAlignment === Qt.AlignLeft ? Theme.spacing : (width - groupWidth) / 2

        implicitWidth: symbolWidth + gap + (hasText ? label.implicitWidth : 0)
        implicitHeight: Math.max(symbolWidth, hasText ? label.implicitHeight : 0)

        Symbol {
            objectName: "symbol"
            x: content.groupX
            anchors.verticalCenter: parent.verticalCenter
            name: control.symbol
            visible: content.hasSymbol
        }

        Text {
            id: label
            objectName: "label"
            x: content.groupX + content.symbolWidth + content.gap
            width: Math.max(0, content.groupWidth - content.symbolWidth - content.gap)
            anchors.verticalCenter: parent.verticalCenter
            visible: content.hasText
            text: control.text
            color: control.highlighted ? Theme.accentText : Theme.text
            font: Theme.metrics.font
            elide: Text.ElideRight
            horizontalAlignment: control.horizontalAlignment === Qt.AlignLeft ? Text.AlignLeft : Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            Accessible.ignored: true
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: control.radius
    }
}
