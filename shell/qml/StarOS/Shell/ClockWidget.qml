// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// The desktop's Clock widget: the time, large, and the date.
WidgetCard {
    id: root

    property date now: new Date()
    readonly property string timeFormat: Qt.locale().timeFormat(Locale.ShortFormat).replace(/:ss/, "")

    title: qsTr("Clock")
    symbol: "calendar"
    Accessible.description: Qt.formatTime(root.now, root.timeFormat) + ", " + Qt.formatDate(root.now, "dddd d MMMM yyyy")

    Text {
        objectName: "time"
        text: Qt.formatTime(root.now, root.timeFormat)
        color: Theme.text
        font.family: Theme.metrics.font.family
        font.pixelSize: Math.round(3.2 * Theme.gridUnit)
        font.weight: Font.Light
        Accessible.ignored: true
    }

    Text {
        objectName: "date"
        width: parent.width
        text: Qt.formatDate(root.now, "dddd, d MMMM")
        color: Theme.textSecondary
        font.family: Theme.metrics.font.family
        font.pixelSize: Math.round(Theme.fontSize)
        elide: Text.ElideRight
        Accessible.ignored: true
    }
}
