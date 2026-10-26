// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick

// A month as six weeks from the locale's first day of the week, today in
// the accent. Used by the clock's calendar and the desktop's Calendar
// widget. Each day is a static text for screen readers, today's ending in
// ", today".
Grid {
    id: grid

    property date now: new Date()
    // The first day of the month on show.
    property date shownMonth: new Date(grid.now.getFullYear(), grid.now.getMonth(), 1)
    property real cellHeight: Math.round(2.1 * Theme.gridUnit)

    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek
    // 42 days from the start of the week that holds the 1st.
    readonly property var days: {
        const first = new Date(grid.shownMonth.getFullYear(), grid.shownMonth.getMonth(), 1);
        const lead = (first.getDay() - grid.firstDayOfWeek + 7) % 7;
        const list = [];
        for (let i = 0; i < 42; ++i) {
            list.push(new Date(first.getFullYear(), first.getMonth(), 1 - lead + i));
        }
        return list;
    }
    readonly property real cellWidth: grid.width / 7

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    columns: 7

    Accessible.role: Accessible.Table
    Accessible.name: Qt.formatDate(grid.shownMonth, "MMMM yyyy")

    Repeater {
        model: 7

        Text {
            required property int index

            width: grid.cellWidth
            height: Math.round(grid.cellHeight * 0.7)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: Qt.locale().dayName((grid.firstDayOfWeek + index) % 7, Locale.NarrowFormat)
            color: Theme.textSecondary
            font.family: Theme.metrics.font.family
            font.pixelSize: Theme.smallPixelSize
            Accessible.ignored: true
        }
    }

    Repeater {
        model: grid.days

        Item {
            id: cell

            required property var modelData
            required property int index

            readonly property bool today: grid.sameDay(cell.modelData, grid.now)
            readonly property bool inMonth: cell.modelData.getMonth() === grid.shownMonth.getMonth()

            width: grid.cellWidth
            height: grid.cellHeight
            objectName: cell.today ? "todayCell" : ""

            Accessible.role: Accessible.StaticText
            Accessible.name: Qt.formatDate(cell.modelData, "dddd d MMMM yyyy") + (cell.today ? ", " + qsTr("today") : "")

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) - 2
                height: width
                radius: width / 2
                visible: cell.today
                gradient: Theme.accentGradient
            }

            Text {
                anchors.centerIn: parent
                text: String(cell.modelData.getDate())
                color: cell.today ? Theme.accentText : cell.inMonth ? Theme.text : Theme.textSecondary
                opacity: cell.inMonth || cell.today ? 1 : 0.55
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Math.min(Theme.fontSize, grid.cellHeight * 0.55))
                font.weight: cell.today ? Font.Bold : Font.Normal
                Accessible.ignored: true
            }
        }
    }
}
