// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Notifications (M0.5, ADR-0014): a card's words, age, actions and keys;
// toasts that go after their timeout unless the pointer rests on them; the
// clock's panels with the month and the notification centre. The models are
// ListModels with libnotificationmanager's role names.
Item {
    id: root

    width: 1280
    height: 720

    readonly property date fixedNow: new Date(2026, 9, 25, 14, 30)

    NotificationCard {
        id: card
        x: 20
        y: 20
        width: 380
        appName: "Sun Store"
        summary: "Updates installed"
        body: "<b>3</b> apps were updated."
        now: root.fixedNow
        created: root.fixedNow
    }

    SignalSpy {
        id: cardCloseSpy
        target: card
        signalName: "closeRequested"
    }

    SignalSpy {
        id: cardActionSpy
        target: card
        signalName: "actionRequested"
    }

    SignalSpy {
        id: cardClickSpy
        target: card
        signalName: "clicked"
    }

    ListModel {
        id: toastModel
    }

    NotificationToasts {
        id: toasts
        x: 860
        y: 20
        width: 400
        height: 400
        model: toastModel
    }

    SignalSpy {
        id: expireSpy
        target: toasts
        signalName: "expireRequested"
    }

    SignalSpy {
        id: toastCloseSpy
        target: toasts
        signalName: "closeRequested"
    }

    SignalSpy {
        id: toastDefaultSpy
        target: toasts
        signalName: "defaultActionRequested"
    }

    ListModel {
        id: historyModel
    }

    CalendarPanel {
        id: calendar
        anchors.fill: parent
        visible: false
        notifications: historyModel
        anchorRight: 1100
    }

    SignalSpy {
        id: calendarCloseSpy
        target: calendar
        signalName: "closeRequested"
    }

    SignalSpy {
        id: centreCloseSpy
        target: calendar
        signalName: "notificationCloseRequested"
    }

    SignalSpy {
        id: centreDefaultSpy
        target: calendar
        signalName: "notificationDefaultActionRequested"
    }

    SignalSpy {
        id: clearAllSpy
        target: calendar
        signalName: "clearAllRequested"
    }

    TestCase {
        name: "Notifications"
        when: windowShown

        function initTestCase() {
            Theme.animationFactor = 0;
        }

        function init() {
            card.closable = true;
            card.critical = false;
            card.actionNames = [];
            card.actionLabels = [];
            card.created = root.fixedNow;
            toastModel.clear();
            historyModel.clear();
            calendar.visible = false;
            calendar.doNotDisturb = false;
            for (const spy of [cardCloseSpy, cardActionSpy, cardClickSpy, expireSpy, toastCloseSpy, toastDefaultSpy,
                               calendarCloseSpy, centreCloseSpy, centreDefaultSpy, clearAllSpy]) {
                spy.clear();
            }
        }

        function notification(summary, extra) {
            const n = {summary: summary, body: "", applicationName: "Star test", applicationIconName: "",
                       desktopEntry: "", created: new Date(), hasDefaultAction: false, closable: true, urgency: 2,
                       timeout: -1};
            return Object.assign(n, extra || {});
        }

        function toastItem(row) {
            const list = findChild(toasts, "toasts");
            tryVerify(() => list.itemAtIndex(row) !== null, 2000, "toast " + row + " is laid out");
            return list.itemAtIndex(row);
        }

        function showCalendar() {
            calendar.visible = true;
            calendar.reset();
            waitForRendering(calendar);
        }

        // --- the card -------------------------------------------------------

        function test_card_words() {
            compare(card.Accessible.role, Accessible.Button);
            compare(card.Accessible.name, "Sun Store: Updates installed");
            compare(card.Accessible.description, "3 apps were updated.");
            compare(findChild(card, "summary").text, "Updates installed");
            card.appName = "";
            compare(card.Accessible.name, "Updates installed");
            card.appName = "Sun Store";
        }

        function test_card_age_data() {
            return [
                {tag: "now", minutes: 0, age: "now"},
                {tag: "minutes", minutes: 5, age: "5 min"},
                {tag: "hours", minutes: 180, age: "3 h"},
                {tag: "days", minutes: 3 * 24 * 60, age: Qt.formatDate(new Date(2026, 9, 22, 14, 30), "d MMM")}
            ];
        }

        function test_card_age(data) {
            card.created = new Date(root.fixedNow.getTime() - data.minutes * 60000);
            compare(findChild(card, "age").text, data.age);
        }

        function test_card_actions() {
            verify(!findChild(card, "actions").visible);
            card.actionNames = ["open", "later"];
            card.actionLabels = ["Open Sun Store", "Later"];
            const actions = findChild(card, "actions");
            verify(actions.visible);
            tryVerify(() => actions.children.length >= 3, 2000, "two action buttons and the repeater");
            let open = null;
            for (const child of actions.children) {
                if (child.text === "Open Sun Store") {
                    open = child;
                }
            }
            verify(open, "a button for the first action");
            verify(open.highlighted);
            // The row and the card lay out before the click.
            waitForRendering(card);
            mouseClick(open);
            compare(cardActionSpy.count, 1);
            compare(cardActionSpy.signalArguments[0][0], "open");
        }

        function test_card_keys() {
            card.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(cardClickSpy.count, 1);
            keyClick(Qt.Key_Delete);
            compare(cardCloseSpy.count, 1);
            card.closable = false;
            verify(!findChild(card, "closeButton").visible);
            keyClick(Qt.Key_Delete);
            compare(cardCloseSpy.count, 1, "a card that cannot close stays");
        }

        function test_card_close_button() {
            const button = findChild(card, "closeButton");
            compare(button.text, "Close");
            mouseClick(button);
            compare(cardCloseSpy.count, 1);
            compare(cardClickSpy.count, 0);
        }

        // --- toasts ---------------------------------------------------------

        function test_toast_expires() {
            toastModel.append(notification("Short", {timeout: 300}));
            // A list view counts its rows when it lays them out.
            tryCompare(toasts, "count", 1);
            verify(findChild(toastItem(0), "timeLeft").visible, "the time bar shows");
            tryVerify(() => expireSpy.count === 1, 3000, "the toast expires");
            compare(expireSpy.signalArguments[0][0], 0);
        }

        function test_critical_and_persistent_toasts_stay() {
            toastModel.append(notification("Critical", {timeout: 200, urgency: 4}));
            toastModel.append(notification("Persistent", {timeout: 0}));
            wait(800);
            compare(expireSpy.count, 0);
            verify(!findChild(toastItem(0), "timeLeft").visible);
        }

        function test_hover_pauses_the_toast() {
            toastModel.append(notification("Hover me", {timeout: 400}));
            const item = toastItem(0);
            mouseMove(item, item.width / 2, item.height / 2);
            wait(900);
            compare(expireSpy.count, 0, "the toast stays while the pointer rests on it");
            mouseMove(root, 10, root.height - 10);
            tryVerify(() => expireSpy.count === 1, 3000, "it goes once the pointer leaves");
        }

        function test_toast_click() {
            toastModel.append(notification("Plain", {timeout: 0}));
            toastModel.append(notification("With action", {timeout: 0, hasDefaultAction: true}));
            mouseClick(toastItem(1));
            compare(toastDefaultSpy.count, 1);
            compare(toastDefaultSpy.signalArguments[0][0], 1);
            mouseClick(toastItem(0));
            compare(expireSpy.count, 1, "a click on a plain toast dismisses it");
            mouseClick(findChild(toastItem(0), "closeButton"));
            compare(toastCloseSpy.count, 1);
        }

        function test_toast_list_name() {
            compare(toasts.Accessible.name, "New notifications");
        }

        // --- calendar and notification centre -------------------------------

        function test_month_grid() {
            showCalendar();
            compare(calendar.days.length, 42);
            const first = calendar.days[0];
            compare(first.getDay(), calendar.firstDayOfWeek);
            verify(first.getTime() <= new Date(calendar.shownMonth).getTime());
            const today = findChild(calendar, "todayCell");
            verify(today, "today has a cell");
            verify(today.Accessible.name.endsWith(", today"), today.Accessible.name);
            compare(findChild(calendar, "month").text, Qt.formatDate(new Date(), "MMMM yyyy"));
        }

        function test_month_navigation() {
            showCalendar();
            const now = new Date();
            keyClick(Qt.Key_PageDown);
            compare(calendar.shownMonth.getMonth(), (now.getMonth() + 1) % 12);
            compare(findChild(calendar, "month").text, Qt.formatDate(calendar.shownMonth, "MMMM yyyy"));
            mouseClick(findChild(calendar, "previousMonthButton"));
            mouseClick(findChild(calendar, "previousMonthButton"));
            compare(calendar.shownMonth.getMonth(), (now.getMonth() + 11) % 12);
            mouseClick(findChild(calendar, "nextMonthButton"));
            keyClick(Qt.Key_PageUp);
            keyClick(Qt.Key_PageDown);
            compare(calendar.shownMonth.getMonth(), now.getMonth());
            calendar.showMonth(5);
            calendar.reset();
            compare(calendar.shownMonth.getMonth(), now.getMonth(), "reset() returns to this month");
        }

        function test_panels_sit_above_the_clock() {
            showCalendar();
            const month = findChild(calendar, "calendar");
            const centre = findChild(calendar, "notificationCentre");
            compare(Math.round(month.x + month.width), 1100);
            const bottom = root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap;
            fuzzyCompare(month.y + month.height, bottom, 1);
            compare(centre.x, month.x);
            verify(centre.y + centre.height <= month.y, "the centre is above the month");
            verify(centre.y >= 0);
        }

        function test_empty_centre() {
            showCalendar();
            verify(findChild(calendar, "noNotifications").visible);
            verify(!findChild(calendar, "clearAllButton").visible);
            compare(findChild(calendar, "noNotifications").text, "No new notifications.");
            calendar.doNotDisturb = true;
            compare(findChild(calendar, "noNotifications").text, "No new notifications. Do not disturb is on.");
            tryVerify(() => findChild(calendar, "nextMonthButton").activeFocus, 2000, "focus on the month");
        }

        function test_centre_lists_notifications() {
            historyModel.append(notification("Newest", {hasDefaultAction: true}));
            historyModel.append(notification("Older", {applicationName: "Files"}));
            showCalendar();
            const list = findChild(calendar, "notificationList");
            compare(list.count, 2);
            compare(list.Accessible.name, "Notifications");
            compare(list.itemAtIndex(0).Accessible.name, "Star test: Newest");
            compare(list.itemAtIndex(1).Accessible.name, "Files: Older");
            verify(findChild(calendar, "clearAllButton").visible);
            verify(!findChild(calendar, "noNotifications").visible);
            tryVerify(() => list.itemAtIndex(0).activeFocus, 2000, "the newest card has focus");
            keyClick(Qt.Key_Return);
            compare(centreDefaultSpy.count, 1);
            compare(centreDefaultSpy.signalArguments[0][0], 0);
            keyClick(Qt.Key_Down);
            tryVerify(() => list.itemAtIndex(1).activeFocus);
            keyClick(Qt.Key_Return);
            compare(centreDefaultSpy.count, 1, "no default action, nothing to run");
            keyClick(Qt.Key_Delete);
            compare(centreCloseSpy.count, 1);
            compare(centreCloseSpy.signalArguments[0][0], 1);
            mouseClick(findChild(calendar, "clearAllButton"));
            compare(clearAllSpy.count, 1);
        }

        function test_escape_and_click_outside() {
            showCalendar();
            keyClick(Qt.Key_Escape);
            compare(calendarCloseSpy.count, 1);
            mouseClick(calendar, 20, 20);
            compare(calendarCloseSpy.count, 2);
            const month = findChild(calendar, "calendar");
            mouseClick(month, 4, month.height - 4);
            compare(calendarCloseSpy.count, 2, "a click on the month keeps it open");
        }
    }
}
