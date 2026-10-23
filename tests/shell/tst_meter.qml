// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// SystemMeter: what it says for each storage mode, the bars, and its place in
// the taskbar's keyboard order.
Item {
    id: root

    width: 1280
    height: 200

    readonly property var liveStatus: ({storageMode: "live", storageTotal: 2e9, storageFree: 1.5e9,
                                        memoryTotal: 4e9, memoryAvailable: 3e9, batteryPresent: false,
                                        batteryPercent: 0, charging: false})
    readonly property var diskStatus: ({storageMode: "star-storage", storageTotal: 16e9, storageFree: 9.8e9,
                                        memoryTotal: 4e9, memoryAvailable: 1e9, batteryPresent: true,
                                        batteryPercent: 80, charging: true})

    SystemMeter {
        id: meter
        x: 10
        y: 10
        height: 40
    }

    Taskbar {
        id: taskbar
        y: 100
        width: root.width
        height: Theme.taskbarHeight
        tasksModel: ListModel {}
    }

    SignalSpy {
        id: requestSpy
        target: taskbar
        signalName: "systemStatusRequested"
    }

    TestCase {
        name: "SystemMeter"
        when: windowShown

        function init() {
            meter.status = root.liveStatus;
            taskbar.systemStatus = null;
            requestSpy.clear();
        }

        function test_live_session() {
            compare(meter.Accessible.role, Accessible.Button);
            compare(meter.Accessible.name, "System status");
            compare(meter.Accessible.description,
                    "Live session: changes are lost at shutdown. 1.5 GB free of 2 GB. "
                    + "Memory: 1 GB of 4 GB in use.");
            compare(findChild(meter, "label").text, "Live · 1.5 GB free");
        }

        function test_star_storage_with_battery() {
            meter.status = root.diskStatus;
            compare(meter.Accessible.description,
                    "Star Storage: 9.8 GB free of 16 GB. Memory: 3 GB of 4 GB in use. "
                    + "Battery: 80 %, charging.");
            compare(findChild(meter, "label").text, "9.8 GB free");
            verify(Math.abs(meter.storageUsed - 6.2 / 16) < 1e-9);
            compare(meter.memoryUsed, 0.75);
        }

        function test_bars_show_the_share_in_use() {
            meter.status = root.diskStatus;
            const bar = findChild(meter, "memoryBar");
            verify(bar !== null);
            const fill = bar.children[0];
            compare(fill.height, Math.round((bar.height - 2) * 0.75));
        }

        function test_formatting() {
            compare(meter.formatBytes(0), "0 B");
            compare(meter.formatBytes(999), "999 B");
            compare(meter.formatBytes(1500), "1.5 kB");
            compare(meter.formatBytes(512e6), "512 MB");
            compare(meter.formatBytes(16e9), "16 GB");
            compare(meter.formatBytes(1.05e9), "1.1 GB");
            compare(meter.formatBytes(250e9), "250 GB");
            compare(meter.formatBytes(-5), "0 B");
        }

        function test_no_status() {
            meter.status = null;
            compare(meter.Accessible.description, "Storage: 0 B free of 0 B. Memory: 0 B of 0 B in use.");
            compare(meter.storageUsed, 0);
        }

        // Hidden without a status; then between the windows and Leave.
        function test_taskbar_keyboard_order() {
            const metered = findChild(taskbar, "systemMeter");
            const apps = findChild(taskbar, "applicationsButton");
            const leave = findChild(taskbar, "leaveButton");
            verify(!metered.visible);
            taskbar.systemStatus = root.liveStatus;
            verify(metered.visible);
            apps.forceActiveFocus();
            keyClick(Qt.Key_Right);
            verify(metered.activeFocus, "Right from Applications reaches the meter");
            keyClick(Qt.Key_Right);
            verify(leave.activeFocus, "then Leave");
            keyClick(Qt.Key_Left);
            verify(metered.activeFocus, "Left from Leave returns to the meter");
            keyClick(Qt.Key_Return);
            compare(requestSpy.count, 1);
            verify(metered.x + metered.width <= leave.x, "the meter is left of Leave");
        }
    }
}
