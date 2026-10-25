// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// A symbol, a 0..100 slider with an accent fill, and the value in percent.
// Arrow keys move it by 5, Page Up/Down by 10, Home/End to the ends. The
// symbol is a button (for example, mute) when 'symbolClickable'.
Item {
    id: root

    property string text: ""
    property string symbol: ""
    property bool symbolClickable: false
    property string symbolText: ""
    property int value: 0
    readonly property alias slider: slider

    // The person moved the slider (not a change of 'value' from outside).
    signal moved(int value)
    signal symbolClicked()

    implicitWidth: 20 * Theme.gridUnit
    implicitHeight: Theme.minTarget

    ShellButton {
        id: symbolButton
        objectName: "symbolButton"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.minTarget
        height: Theme.minTarget
        flat: true
        iconOnly: true
        symbol: root.symbol
        text: root.symbolText !== "" ? root.symbolText : root.text
        enabled: root.symbolClickable
        focusPolicy: root.symbolClickable ? Qt.StrongFocus : Qt.NoFocus
        onClicked: root.symbolClicked()
    }

    T.Slider {
        id: slider
        objectName: "slider"
        anchors.left: symbolButton.right
        anchors.leftMargin: Theme.spacing / 2
        anchors.right: valueLabel.left
        anchors.rightMargin: Theme.spacing
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.minTarget
        from: 0
        to: 100
        stepSize: 5
        snapMode: T.Slider.SnapAlways
        value: root.value
        focusPolicy: Qt.StrongFocus
        enabled: root.enabled

        Accessible.role: Accessible.Slider
        Accessible.name: root.text

        onMoved: root.moved(Math.round(slider.value))

        Keys.onPressed: event => {
            let next = -1;
            if (event.key === Qt.Key_PageUp) {
                next = Math.min(100, slider.value + 10);
            } else if (event.key === Qt.Key_PageDown) {
                next = Math.max(0, slider.value - 10);
            } else if (event.key === Qt.Key_Home) {
                next = 0;
            } else if (event.key === Qt.Key_End) {
                next = 100;
            }
            if (next >= 0) {
                root.moved(Math.round(next));
                event.accepted = true;
            }
        }

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + (slider.availableHeight - height) / 2
            width: slider.availableWidth
            height: Math.round(Theme.gridUnit / 3)
            radius: height / 2
            color: Theme.glassButtonActive

            Rectangle {
                objectName: "fill"
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                gradient: Theme.accentGradient
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + (slider.availableHeight - height) / 2
            width: Math.round(1.1 * Theme.gridUnit)
            height: width
            radius: width / 2
            color: Theme.text
            border.width: slider.activeFocus ? Theme.focusRingWidth : 0
            border.color: Theme.focusRing
            scale: slider.pressed ? 1.15 : 1

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.durationShort
                }
            }
        }
    }

    Text {
        id: valueLabel
        objectName: "valueLabel"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(2.4 * Theme.gridUnit)
        horizontalAlignment: Text.AlignRight
        text: Math.round(slider.value) + " %"
        color: Theme.textSecondary
        font.family: Theme.metrics.font.family
        font.pixelSize: Theme.smallPixelSize
        Accessible.ignored: true
    }
}
