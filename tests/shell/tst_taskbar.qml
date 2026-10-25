// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Taskbar (M0.5 floating pill): pinned apps and windows from a model with
// libtaskmanager's role names, app icons and their marks, the tray, clock and
// notification buttons, keyboard order, signals, Escape left to the host, and
// the visible focus ring.
Item {
    id: root

    width: 1280
    height: 200

    property int escapeCount: 0

    readonly property var liveStatus: ({storageMode: "live", storageTotal: 2e9, storageFree: 1.5e9,
                                        memoryTotal: 4e9, memoryAvailable: 3e9, batteryPresent: false,
                                        batteryPercent: 0, charging: false})

    ListModel {
        id: tasks
    }

    ListModel {
        id: sparseTasks

        ListElement {
            display: "Only a title"
        }
    }

    // Stands in for the host panel: it sees the keys the taskbar leaves alone.
    FocusScope {
        id: host
        x: 0
        y: 0
        width: root.width
        height: Theme.taskbarHeight
        focus: true

        Keys.onEscapePressed: root.escapeCount += 1

        Taskbar {
            id: taskbar
            anchors.fill: parent
            focus: true
            tasksModel: tasks
        }
    }

    SignalSpy {
        id: launcherSpy
        target: taskbar
        signalName: "launcherRequested"
    }

    SignalSpy {
        id: activateSpy
        target: taskbar
        signalName: "activateRequested"
    }

    SignalSpy {
        id: quickSettingsSpy
        target: taskbar
        signalName: "quickSettingsRequested"
    }

    SignalSpy {
        id: calendarSpy
        target: taskbar
        signalName: "calendarRequested"
    }

    SignalSpy {
        id: notificationsSpy
        target: taskbar
        signalName: "notificationsRequested"
    }

    TestCase {
        name: "Taskbar"
        when: windowShown

        property Item applications
        property ListView list
        property Item tray
        property Item clock
        property Item bell
        property Item pill

        function initTestCase() {
            Theme.animationFactor = 0;
            applications = findChild(taskbar, "applicationsButton");
            list = findChild(taskbar, "openWindows");
            tray = findChild(taskbar, "trayButton");
            clock = findChild(taskbar, "clockButton");
            bell = findChild(taskbar, "notificationButton");
            pill = findChild(taskbar, "pill");
            verify(applications && list && tray && clock && bell && pill);
        }

        function init() {
            taskbar.tasksModel = tasks;
            taskbar.systemStatus = null;
            taskbar.unreadNotifications = 0;
            taskbar.doNotDisturb = false;
            tasks.clear();
            // A pinned app without a window, then two windows.
            tasks.append({display: "Files", AppName: "Files", AppId: "org.staros.files.desktop",
                          IsActive: false, IsWindow: false});
            tasks.append({display: "Konsole - ~", AppName: "Konsole", AppId: "org.kde.konsole",
                          IsActive: true, IsWindow: true});
            tasks.append({display: "", AppName: "System Settings", AppId: "systemsettings",
                          IsActive: false, IsWindow: true});
            list.currentIndex = 0;
            launcherSpy.clear();
            activateSpy.clear();
            quickSettingsSpy.clear();
            calendarSpy.clear();
            notificationsSpy.clear();
            root.escapeCount = 0;
            applications.forceActiveFocus(Qt.TabFocusReason);
            tryVerify(() => applications.activeFocus, 5000, "Applications has focus");
        }

        function focused() {
            return root.Window.window ? root.Window.window.activeFocusItem : null;
        }

        function taskAt(row) {
            return list.itemAtIndex(row);
        }

        function expectFocus(item, what) {
            tryVerify(() => item !== null && item.activeFocus, 5000, what + " has focus");
        }

        function test_structure_and_names() {
            compare(taskbar.Accessible.role, Accessible.ToolBar);
            compare(taskbar.Accessible.name, "Taskbar");
            compare(applications.Accessible.role, Accessible.Button);
            compare(applications.Accessible.name, "Applications");
            compare(applications.Accessible.description, "Open the application launcher");
            compare(list.Accessible.role, Accessible.List);
            compare(list.Accessible.name, "Apps");
            compare(tray.Accessible.name, "Quick settings");
            compare(clock.Accessible.name, "Clock");
            compare(bell.Accessible.name, "Notifications");
            compare(bell.Accessible.description, "No new notifications");
        }

        // The pill is centred, taskbarGap above the bottom, and its glass
        // follows its place on the screen.
        function test_floating_pill() {
            compare(pill.height, Theme.taskbarPillHeight);
            compare(pill.y + pill.height, taskbar.height - Theme.taskbarGap);
            verify(Math.abs(pill.x - (taskbar.width - pill.width) / 2) <= 0.5, "centred: " + pill.x);
            verify(pill.width < taskbar.width, "the pill floats: " + pill.width);
            const glass = findChild(pill, "glass");
            compare(glass.radius, Theme.taskbarRadius);
            compare(glass.tintOpacity, Theme.taskbarTintOpacity);
            compare(glass.wallpaperOrigin.x, taskbar.glassOrigin.x + pill.x);
            compare(glass.wallpaperOrigin.y, taskbar.glassOrigin.y + pill.y);
            compare(Theme.taskbarHeight, Theme.taskbarPillHeight + Theme.taskbarGap + Theme.taskbarShadowRoom);
            verify(Theme.taskbarButtonSize >= Theme.minTarget);
        }

        function test_one_button_per_app_and_window() {
            compare(list.count, 3);
            compare(taskAt(0).Accessible.name, "Files");
            compare(taskAt(0).Accessible.description, "Pinned app");
            compare(taskAt(1).Accessible.name, "Konsole - ~");
            compare(taskAt(1).Accessible.description, "Active window");
            // An empty title falls back to the application name.
            compare(taskAt(2).Accessible.name, "System Settings");
            compare(taskAt(2).Accessible.description, "Window");
            tasks.append({display: "Third", AppName: "Konsole", AppId: "org.kde.konsole",
                          IsActive: false, IsWindow: true});
            compare(list.count, 4);
        }

        // No mark for a pinned app, a dot for a window, a bar for the active one.
        function test_marks() {
            const pinnedMark = findChild(taskAt(0), "indicator");
            const activeMark = findChild(taskAt(1), "indicator");
            const windowMark = findChild(taskAt(2), "indicator");
            verify(!pinnedMark.visible);
            verify(activeMark.visible && windowMark.visible);
            verify(activeMark.width > windowMark.width);
            verify(Qt.colorEqual(activeMark.color, Theme.activeIndicator));
        }

        // A model without the AppName, IsActive and IsWindow roles.
        function test_missing_roles_are_tolerated() {
            taskbar.tasksModel = sparseTasks;
            tryVerify(() => taskAt(0) !== null && taskAt(0).Accessible.name === "Only a title",
                      5000, "the delegate shows the title");
            compare(taskAt(0).Accessible.description, "Window");
            const icon = findChild(taskAt(0), "icon");
            compare(icon.appId, "");
            verify(findChild(icon, "monogram").visible, "no AppId: the monogram shows");
            compare(findChild(icon, "monogramLetter").text, "O");
            taskbar.tasksModel = tasks;
        }

        function test_task_buttons_show_app_icons() {
            tasks.append({display: "Example - a window", AppName: "Example", AppId: "org.example.app",
                          IsActive: false, IsWindow: true});
            tryVerify(() => taskAt(3) !== null, 5000, "the fourth task button exists");
            const ids = ["org.staros.files.desktop", "org.kde.konsole", "systemsettings", "org.example.app"];
            for (let row = 0; row < ids.length; ++row) {
                const icon = findChild(taskAt(row), "icon");
                compare(icon.appId, ids[row]);
                compare(icon.width, Theme.taskIconSize);
                verify(icon.height <= taskAt(row).height, "the icon fits the button");
            }
            const artwork = findChild(findChild(taskAt(1), "icon"), "artwork");
            tryCompare(artwork, "status", Image.Ready, 5000, "Konsole artwork loads");
            const other = findChild(taskAt(3), "icon");
            verify(findChild(other, "monogram").visible && !findChild(other, "artwork").visible);
            compare(findChild(other, "monogramLetter").text, "E");
        }

        function test_arrow_order() {
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(0), "first app");
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(1), "second app");
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(2), "third app");
            keyClick(Qt.Key_Right);
            expectFocus(tray, "Quick settings");
            keyClick(Qt.Key_Right);
            expectFocus(clock, "Clock");
            keyClick(Qt.Key_Right);
            expectFocus(bell, "Notifications");
            keyClick(Qt.Key_Left);
            expectFocus(clock, "Clock");
            keyClick(Qt.Key_Left);
            expectFocus(tray, "Quick settings");
            keyClick(Qt.Key_Left);
            expectFocus(taskAt(2), "third app");
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Left);
            expectFocus(applications, "Applications");
        }

        function test_tab_order_reaches_every_button() {
            const seen = [];
            for (let i = 0; i < 6; ++i) {
                keyClick(Qt.Key_Tab);
                const item = focused();
                verify(item !== null && item.visible, "focus is on a visible item");
                seen.push(item.Accessible.name);
            }
            for (const name of ["Files", "Quick settings", "Clock", "Notifications"]) {
                verify(seen.indexOf(name) >= 0, "Tab reaches " + name + ": " + seen);
            }
        }

        function test_return_and_space_activate_apps() {
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(2), "third app");
            keyClick(Qt.Key_Return);
            compare(activateSpy.count, 1);
            compare(activateSpy.signalArguments[0][0], 2);
            keyClick(Qt.Key_Space);
            compare(activateSpy.count, 2);
            compare(activateSpy.signalArguments[1][0], 2);
        }

        function test_click_activates_an_app() {
            mouseClick(taskAt(0));
            compare(activateSpy.count, 1);
            compare(activateSpy.signalArguments[0][0], 0);
        }

        function test_buttons_emit_their_requests() {
            keyClick(Qt.Key_Return);
            compare(launcherSpy.count, 1);
            mouseClick(applications);
            compare(launcherSpy.count, 2);
            mouseClick(tray);
            compare(quickSettingsSpy.count, 1);
            mouseClick(clock);
            compare(calendarSpy.count, 1);
            bell.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(notificationsSpy.count, 1);
        }

        function test_open_panels_check_their_buttons() {
            verify(!applications.checked && !tray.checked && !clock.checked);
            taskbar.startMenuOpen = true;
            taskbar.quickSettingsOpen = true;
            taskbar.calendarOpen = true;
            verify(applications.checked && tray.checked && clock.checked);
            taskbar.startMenuOpen = false;
            taskbar.quickSettingsOpen = false;
            taskbar.calendarOpen = false;
        }

        // The tray describes the session in words.
        function test_tray_description() {
            compare(tray.Accessible.description, "");
            taskbar.systemStatus = root.liveStatus;
            compare(tray.Accessible.description,
                    "Live session: changes are lost at shutdown. 1.5 GB free of 2 GB. "
                    + "Memory: 1 GB of 4 GB in use.");
            verify(findChild(tray, "networkSymbol").visible);
            verify(findChild(tray, "volumeSymbol").visible);
            verify(!findChild(tray, "batterySymbol").visible);
            taskbar.systemStatus = Object.assign({}, root.liveStatus, {batteryPresent: true, batteryPercent: 64});
            verify(findChild(tray, "batterySymbol").visible);
            verify(tray.Accessible.description.endsWith("Battery: 64 %."));
        }

        function test_clock() {
            clock.now = new Date(2026, 9, 25, 14, 32, 10);
            const time = findChild(clock, "time");
            const date = findChild(clock, "date");
            verify(time.text.indexOf("32") >= 0, "minutes shown: " + time.text);
            verify(time.text.indexOf("10") < 0, "no seconds: " + time.text);
            verify(date.text.indexOf("25") >= 0, "the day: " + date.text);
            verify(clock.Accessible.description.indexOf("2026") >= 0, clock.Accessible.description);
            verify(clock.width >= Math.max(time.implicitWidth, date.implicitWidth));
        }

        function test_notification_badge() {
            const badge = findChild(bell, "badge");
            verify(!badge.visible);
            taskbar.unreadNotifications = 3;
            verify(badge.visible);
            compare(bell.Accessible.description, "3 unread");
            taskbar.doNotDisturb = true;
            verify(!badge.visible);
            compare(bell.Accessible.description, "Do not disturb is on");
        }

        function test_empty_list_is_never_focused() {
            tasks.clear();
            compare(list.count, 0);
            keyClick(Qt.Key_Right);
            expectFocus(tray, "Quick settings");
            keyClick(Qt.Key_Left);
            expectFocus(applications, "Applications");
        }

        function test_focus_returns_when_the_last_app_goes() {
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(0), "first app");
            tasks.clear();
            expectFocus(applications, "Applications");
        }

        function test_escape_is_left_to_the_host() {
            keyClick(Qt.Key_Escape);
            compare(root.escapeCount, 1);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Escape);
            compare(root.escapeCount, 2);
        }

        function test_focus_ring_visible() {
            waitForRendering(host);
            // Device pixels without a pixel ratio, cropped to the grabbed
            // item's logical size (see tst_startmenu.qml), so the taller root
            // item is grabbed to keep the taskbar inside the crop at 200 %.
            const img = grabImage(root);
            const dpr = Screen.devicePixelRatio;
            const p = applications.mapToItem(root, 0, applications.height / 2);
            verify(Math.floor((p.x + 8) * dpr) < img.width && Math.floor(p.y * dpr) < img.height);
            let best = 0;
            let run = 0;
            for (let x = Math.max(0, Math.floor(p.x * dpr) - 1); x < Math.floor((p.x + 8) * dpr); ++x) {
                const y = Math.floor(p.y * dpr);
                const hit = Math.abs(img.red(x, y) - Theme.focusRing.r * 255) <= 8
                    && Math.abs(img.green(x, y) - Theme.focusRing.g * 255) <= 8
                    && Math.abs(img.blue(x, y) - Theme.focusRing.b * 255) <= 8;
                run = hit ? run + 1 : 0;
                best = Math.max(best, run);
            }
            const minimum = Math.max(Theme.focusRingWidth, Math.floor(Theme.focusRingWidth * dpr) - 1);
            verify(best >= minimum, "focus ring " + best + " px at dpr " + dpr);
        }
    }
}
