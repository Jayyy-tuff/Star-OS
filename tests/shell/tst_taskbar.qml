// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Taskbar: window buttons from a model with libtaskmanager's role names,
// keyboard order, signals, the empty list, Escape left to the host, and the
// visible focus ring.
Item {
    id: root

    width: 1280
    height: 200

    property int escapeCount: 0

    ListModel {
        id: windows
    }

    ListModel {
        id: sparseWindows

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
            tasksModel: windows
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
        id: leaveSpy
        target: taskbar
        signalName: "leaveRequested"
    }

    TestCase {
        name: "Taskbar"
        when: windowShown

        property Item applications
        property ListView list
        property Item leave

        function initTestCase() {
            applications = findChild(taskbar, "applicationsButton");
            list = findChild(taskbar, "openWindows");
            leave = findChild(taskbar, "leaveButton");
            verify(applications !== null && list !== null && leave !== null);
        }

        function init() {
            taskbar.tasksModel = windows;
            windows.clear();
            windows.append({display: "Konsole - ~", AppName: "Konsole", IsActive: true});
            windows.append({display: "", AppName: "System Settings", IsActive: false});
            list.currentIndex = 0;
            launcherSpy.clear();
            activateSpy.clear();
            leaveSpy.clear();
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
            compare(list.Accessible.name, "Open windows");
            compare(list.Accessible.description, "");
            compare(leave.Accessible.name, "Leave");
            compare(leave.Accessible.description, "Log out, restart or shut down");
        }

        function test_one_button_per_window() {
            compare(list.count, 2);
            compare(taskAt(0).Accessible.name, "Konsole - ~");
            compare(taskAt(0).Accessible.description, "Active window");
            // An empty title falls back to the application name.
            compare(taskAt(1).Accessible.name, "System Settings");
            compare(taskAt(1).Accessible.description, "Window");
            windows.append({display: "Third", AppName: "Konsole", IsActive: false});
            compare(list.count, 3);
        }

        // A model without the AppName and IsActive roles. The view applies
        // model changes when it lays out, so delegates are awaited.
        function test_missing_roles_are_tolerated() {
            taskbar.tasksModel = sparseWindows;
            tryVerify(() => taskAt(0) !== null && taskAt(0).Accessible.name === "Only a title",
                      5000, "the delegate shows the title");
            compare(taskAt(0).Accessible.description, "Window");
            taskbar.tasksModel = windows;
        }

        function test_arrow_order() {
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(0), "first task");
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(1), "second task");
            keyClick(Qt.Key_Right);
            expectFocus(leave, "Leave");
            keyClick(Qt.Key_Left);
            expectFocus(taskAt(1), "second task");
            keyClick(Qt.Key_Left);
            expectFocus(taskAt(0), "first task");
            keyClick(Qt.Key_Left);
            expectFocus(applications, "Applications");
        }

        function test_tab_order_reaches_every_button() {
            const seen = [];
            for (let i = 0; i < 4; ++i) {
                keyClick(Qt.Key_Tab);
                const item = focused();
                verify(item !== null && item.visible, "focus is on a visible item");
                seen.push(item.Accessible.name);
            }
            verify(seen.indexOf("Konsole - ~") >= 0, "Tab reaches the first task: " + seen);
            verify(seen.indexOf("System Settings") >= 0, "Tab reaches the second task: " + seen);
            verify(seen.indexOf("Leave") >= 0, "Tab reaches Leave: " + seen);
        }

        function test_return_and_space_activate_tasks() {
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(1), "second task");
            keyClick(Qt.Key_Return);
            compare(activateSpy.count, 1);
            compare(activateSpy.signalArguments[0][0], 1);
            keyClick(Qt.Key_Space);
            compare(activateSpy.count, 2);
            compare(activateSpy.signalArguments[1][0], 1);
        }

        function test_click_activates_task() {
            mouseClick(taskAt(1));
            compare(activateSpy.count, 1);
            compare(activateSpy.signalArguments[0][0], 1);
        }

        function test_applications_and_leave() {
            keyClick(Qt.Key_Return);
            compare(launcherSpy.count, 1);
            leave.forceActiveFocus(Qt.TabFocusReason);
            keyClick(Qt.Key_Space);
            compare(leaveSpy.count, 1);
            mouseClick(applications);
            compare(launcherSpy.count, 2);
        }

        function test_empty_list_is_never_focused() {
            windows.clear();
            compare(list.count, 0);
            tryCompare(list.Accessible, "description", "No open windows");
            keyClick(Qt.Key_Right);
            expectFocus(leave, "Leave");
            keyClick(Qt.Key_Left);
            expectFocus(applications, "Applications");
            keyClick(Qt.Key_Tab);
            expectFocus(leave, "Leave");
        }

        function test_focus_returns_when_last_window_closes() {
            keyClick(Qt.Key_Right);
            expectFocus(taskAt(0), "first task");
            windows.clear();
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
            // Device pixels without a pixel ratio; see tst_launcher.qml.
            const img = grabImage(host);
            const dpr = Screen.devicePixelRatio;
            const p = applications.mapToItem(host, 0, applications.height / 2);
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
