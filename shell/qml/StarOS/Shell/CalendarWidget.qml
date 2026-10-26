// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// The desktop's Calendar widget: this month, today in the accent.
WidgetCard {
    id: root

    property date now: new Date()

    title: qsTr("Calendar")
    symbol: "calendar"

    Text {
        objectName: "month"
        text: Qt.formatDate(root.now, "MMMM yyyy")
        color: Theme.text
        font.family: Theme.metrics.font.family
        font.pixelSize: Math.round(Theme.fontSize)
        font.weight: Font.DemiBold
        Accessible.role: Accessible.Heading
        Accessible.name: text
    }

    MonthGrid {
        objectName: "days"
        width: parent.width
        now: root.now
        cellHeight: Math.round(1.6 * Theme.gridUnit)
    }
}
