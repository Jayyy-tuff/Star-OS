// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick

// The clock's panels (M0.5): the notification centre above a month
// calendar, on glass, their right edges at 'anchorRight' (the taskbar's
// right end), in a screen-sized overlay that dims lightly. Clicking outside
// or Escape closes it.
//
// 'notifications' is libnotificationmanager's Notifications model (or a test
// double) with the roles NotificationToasts lists; the host acts on the
// close, action and clear-all requests by row.
FocusScope {
    id: root

    property var notifications: null
    property Component iconFallback: null
    property bool doNotDisturb: false
    property date now: new Date()
    property real anchorRight: root.width - Theme.spacing
    property bool shown: true
    property int criticalUrgency: 4
    // The first day of the month on show.
    property date shownMonth: new Date(root.now.getFullYear(), root.now.getMonth(), 1)

    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek
    // 42 days from the start of the week that holds the 1st.
    readonly property var days: {
        const first = new Date(root.shownMonth.getFullYear(), root.shownMonth.getMonth(), 1);
        const lead = (first.getDay() - root.firstDayOfWeek + 7) % 7;
        const list = [];
        for (let i = 0; i < 42; ++i) {
            list.push(new Date(first.getFullYear(), first.getMonth(), 1 - lead + i));
        }
        return list;
    }

    signal closeRequested()
    signal notificationCloseRequested(int row)
    signal notificationDefaultActionRequested(int row)
    signal notificationActionRequested(int row, string actionName)
    signal clearAllRequested()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Calendar and notifications")

    // Called by the host every time the panels are shown.
    function reset() {
        root.now = new Date();
        root.shownMonth = new Date(root.now.getFullYear(), root.now.getMonth(), 1);
        list.currentIndex = 0;
        if (list.count > 0) {
            list.forceActiveFocus(Qt.OtherFocusReason);
        } else {
            nextButton.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    function showMonth(offset) {
        root.shownMonth = new Date(root.shownMonth.getFullYear(), root.shownMonth.getMonth() + offset, 1);
    }

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    Keys.onEscapePressed: event => {
        root.closeRequested();
        event.accepted = true;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp) {
            root.showMonth(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            root.showMonth(1);
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.shown ? 1 : 0
        Accessible.ignored: true

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durationMedium
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    // The month.
    GlassPanel {
        id: calendar
        objectName: "calendar"
        width: Math.min(Theme.trayPanelWidth, root.width - 2 * Theme.spacing)
        height: calendarColumn.implicitHeight + 2 * Theme.panelPadding
        x: Math.max(Theme.spacing, Math.min(root.width - Theme.spacing, root.anchorRight) - calendar.width)
        y: Math.round(root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap - calendar.height)
        shown: root.shown
        wallpaperOrigin: Qt.point(calendar.x, calendar.y)
        screenSize: Qt.size(root.width, root.height)

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: calendarColumn
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: calendar.width - 2 * Theme.panelPadding
            spacing: Theme.spacing

            Item {
                width: parent.width
                height: Math.max(heading.implicitHeight, nextButton.height)

                Column {
                    id: heading
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        objectName: "today"
                        text: Qt.formatDate(root.now, "dddd, d MMMM")
                        color: Theme.text
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Theme.headingPixelSize
                        font.weight: Font.DemiBold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Text {
                        objectName: "month"
                        text: Qt.formatDate(root.shownMonth, "MMMM yyyy")
                        color: Theme.textSecondary
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Theme.smallPixelSize
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacing / 2

                    ShellButton {
                        objectName: "previousMonthButton"
                        width: Theme.minTarget
                        iconOnly: true
                        symbol: "chevron-left"
                        text: qsTr("Previous month")
                        onClicked: root.showMonth(-1)
                    }

                    ShellButton {
                        id: nextButton
                        objectName: "nextMonthButton"
                        width: Theme.minTarget
                        iconOnly: true
                        symbol: "chevron-right"
                        text: qsTr("Next month")
                        onClicked: root.showMonth(1)
                    }
                }
            }

            Grid {
                id: grid
                objectName: "days"
                columns: 7
                width: parent.width

                readonly property real cellWidth: width / 7
                readonly property real cellHeight: Math.round(2.1 * Theme.gridUnit)

                Accessible.role: Accessible.Table
                Accessible.name: Qt.formatDate(root.shownMonth, "MMMM yyyy")

                Repeater {
                    model: 7

                    Text {
                        required property int index

                        width: grid.cellWidth
                        height: Math.round(1.5 * Theme.gridUnit)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Qt.locale().dayName((root.firstDayOfWeek + index) % 7, Locale.NarrowFormat)
                        color: Theme.textSecondary
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Theme.smallPixelSize
                        Accessible.ignored: true
                    }
                }

                Repeater {
                    model: root.days

                    Item {
                        id: cell

                        required property var modelData
                        required property int index

                        readonly property bool today: root.sameDay(cell.modelData, root.now)
                        readonly property bool inMonth: cell.modelData.getMonth() === root.shownMonth.getMonth()

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
                            font.pixelSize: Math.round(Theme.fontSize)
                            font.weight: cell.today ? Font.Bold : Font.Normal
                            Accessible.ignored: true
                        }
                    }
                }
            }
        }
    }

    // The notification centre, above the month.
    GlassPanel {
        id: centre
        objectName: "notificationCentre"
        width: calendar.width
        height: Math.min(centreColumn.implicitHeight + 2 * Theme.panelPadding,
                         Math.max(8 * Theme.gridUnit, calendar.y - Theme.popupGap - Theme.spacing))
        x: calendar.x
        y: calendar.y - Theme.spacing - centre.height
        shown: root.shown
        wallpaperOrigin: Qt.point(centre.x, centre.y)
        screenSize: Qt.size(root.width, root.height)

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: centreColumn
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: centre.width - 2 * Theme.panelPadding
            spacing: Theme.spacing

            Item {
                width: parent.width
                height: Math.max(centreHeading.implicitHeight, clearButton.height)

                Text {
                    id: centreHeading
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Notifications")
                    color: Theme.text
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.headingPixelSize
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                ShellButton {
                    id: clearButton
                    objectName: "clearAllButton"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(1.7 * Theme.gridUnit)
                    radius: height / 2
                    visible: list.count > 0
                    text: qsTr("Clear all")
                    onClicked: root.clearAllRequested()
                }
            }

            Text {
                objectName: "noNotifications"
                width: parent.width
                visible: list.count === 0
                text: root.doNotDisturb ? qsTr("No new notifications. Do not disturb is on.") : qsTr("No new notifications.")
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            ListView {
                id: list
                objectName: "notificationList"
                width: parent.width
                height: Math.min(contentHeight, Math.max(0, centre.height - 2 * Theme.panelPadding - clearButton.height - Theme.spacing))
                visible: count > 0
                clip: true
                spacing: Theme.spacing
                model: root.notifications
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                activeFocusOnTab: count > 0
                boundsBehavior: Flickable.StopAtBounds

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Notifications")

                delegate: NotificationCard {
                    id: card

                    required property var model
                    required property int index

                    width: list.width
                    focus: card.ListView.isCurrentItem
                    now: root.now
                    appName: card.model.applicationName ?? ""
                    appId: card.model.desktopEntry ?? ""
                    iconData: card.model.applicationIconName
                    iconFallback: root.iconFallback
                    summary: card.model.summary ?? ""
                    body: card.model.body ?? ""
                    created: card.model.created ?? new Date()
                    actionNames: card.model.expired === true ? [] : (card.model.actionNames ?? [])
                    actionLabels: card.model.actionLabels ?? []
                    hasDefaultAction: card.model.hasDefaultAction === true && card.model.expired !== true
                    closable: card.model.closable !== false
                    critical: card.model.urgency === root.criticalUrgency
                    onClicked: {
                        list.currentIndex = card.index;
                        if (card.hasDefaultAction) {
                            root.notificationDefaultActionRequested(card.index);
                        }
                    }
                    onCloseRequested: root.notificationCloseRequested(card.index)
                    onActionRequested: actionName => root.notificationActionRequested(card.index, actionName)
                }
            }
        }
    }
}
