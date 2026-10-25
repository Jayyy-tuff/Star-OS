// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Templates as T

// The time and the date in the taskbar; opens the calendar. The time follows
// the locale's short format without seconds. 'now' is updated at every
// minute (tests may set it). 'checked' while the calendar is open.
T.AbstractButton {
    id: control

    property date now: new Date()
    readonly property string timeFormat: Qt.locale().timeFormat(Locale.ShortFormat).replace(/[:.]?s+/g, "").trim()
    readonly property string timeText: Qt.formatTime(control.now, control.timeFormat)
    readonly property string dateText: Qt.formatDate(control.now, "ddd d MMM")

    text: qsTr("Clock")
    implicitWidth: Math.max(timeLabel.implicitWidth, dateLabel.implicitWidth) + 2 * Theme.spacing
    implicitHeight: Theme.taskbarButtonSize
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.text
    Accessible.description: Qt.formatDate(control.now, "dddd d MMMM yyyy") + ", " + control.timeText

    Keys.onReturnPressed: event => {
        control.clicked();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        control.clicked();
        event.accepted = true;
    }

    // Wakes just after each minute starts.
    Timer {
        id: minuteTimer
        running: true
        repeat: false
        interval: 60000 - (control.now.getSeconds() * 1000 + control.now.getMilliseconds()) + 50
        onTriggered: {
            control.now = new Date();
            minuteTimer.restart();
        }
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
        Column {
            anchors.centerIn: parent
            spacing: 0

            Text {
                id: timeLabel
                objectName: "time"
                anchors.right: parent.right
                text: control.timeText
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize)
                font.weight: Font.DemiBold
                Accessible.ignored: true
            }

            Text {
                id: dateLabel
                objectName: "date"
                anchors.right: parent.right
                text: control.dateText
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                Accessible.ignored: true
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
