// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Layout invariants at the scale factor the runner sets (100, 150, 200 %) on
// an offscreen 1920x1080 screen: the window here fills the logical screen.
Item {
    id: root

    width: Screen.width
    height: Screen.height

    FakeCatalogue {
        id: fakeCatalogue
    }

    Launcher {
        id: launcher
        anchors.fill: parent
        catalogue: fakeCatalogue
    }

    ListModel {
        id: windows
    }

    Taskbar {
        id: taskbar
        x: 0
        y: 0
        width: 960
        height: Theme.taskbarHeight
        tasksModel: windows
    }

    TestCase {
        name: "Scaling"
        when: windowShown

        readonly property var apps: [
            {AppName: "Konsole", GenericName: "Terminal"},
            {AppName: "System Settings", GenericName: "Configuration Tools"},
            {AppName: "KMenuEdit", GenericName: "Menu Editor"},
            {AppName: "Accessibility Helper", GenericName: "Exactly twenty characters"},
            {AppName: "An Application With A Rather Long Descriptive Name", GenericName: "Long"},
            {AppName: "Calculator", GenericName: "Scientific Calculator"}
        ]

        function initTestCase() {
            fakeCatalogue.apps = apps;
            launcher.reset();
            windows.clear();
            for (let i = 0; i < 3; ++i) {
                windows.append({display: "Window with a long title number " + (i + 1),
                                AppName: "Konsole", IsActive: i === 0});
            }
        }

        function rectOf(item, ancestor) {
            const p = item.mapToItem(ancestor, 0, 0);
            return {x: p.x, y: p.y, w: item.width, h: item.height};
        }

        function inside(r, w, h) {
            return r.x >= 0 && r.y >= 0 && r.x + r.w <= w + 0.5 && r.y + r.h <= h + 0.5;
        }

        function overlap(a, b) {
            return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
        }

        function test_screen() {
            const dpr = Screen.devicePixelRatio;
            console.info("STAROS-TEST scaling screen=" + Screen.width + "x" + Screen.height
                + " dpr=" + dpr + " gridUnit=" + Theme.gridUnit
                + " taskbarHeight=" + Theme.taskbarHeight);
            compare(Math.round(Screen.width * dpr), 1920);
            compare(Math.round(Screen.height * dpr), 1080);
            compare(root.width, Screen.width);
        }

        function test_launcher_tiles() {
            const grid = findChild(launcher, "appGrid");
            const search = findChild(launcher, "searchField");
            tryCompare(grid, "count", apps.length);
            waitForRendering(launcher);
            verify(grid.columns >= 1);
            verify(inside(rectOf(search, launcher), launcher.width, launcher.height),
                   "search field inside the launcher");
            const rects = [];
            for (let i = 0; i < grid.count; ++i) {
                const tile = grid.itemAtIndex(i);
                verify(tile !== null, "tile " + i + " exists");
                const r = rectOf(tile, launcher);
                verify(inside(r, launcher.width, launcher.height),
                       "tile " + i + " inside the launcher: " + JSON.stringify(r));
                verify(tile.width >= Theme.minTarget && tile.height >= Theme.minTarget);
                for (const other of rects) {
                    verify(!overlap(r, other), "tile " + i + " overlaps another tile");
                }
                rects.push(r);
                const label = findChild(tile, "label");
                verify(label !== null);
                if (tile.Accessible.name.length <= 20) {
                    verify(!label.truncated, "'" + tile.Accessible.name + "' is truncated");
                }
            }
        }

        function test_taskbar_fits_at_960() {
            const applications = findChild(taskbar, "applicationsButton");
            const list = findChild(taskbar, "openWindows");
            const leave = findChild(taskbar, "leaveButton");
            tryCompare(list, "count", 3);
            waitForRendering(taskbar);
            verify(list.contentWidth <= list.width + 0.5,
                   "three task buttons fit: " + list.contentWidth + " > " + list.width);
            verify(inside(rectOf(applications, taskbar), taskbar.width, taskbar.height));
            verify(inside(rectOf(leave, taskbar), taskbar.width, taskbar.height));
            verify(applications.height >= Theme.minTarget && leave.height >= Theme.minTarget);
            const listRect = rectOf(list, taskbar);
            verify(!overlap(rectOf(applications, taskbar), listRect));
            verify(!overlap(rectOf(leave, taskbar), listRect));
            for (let i = 0; i < list.count; ++i) {
                const task = list.itemAtIndex(i);
                verify(task.width >= 2 * Theme.minTarget, "task button " + i + " is wide enough");
                verify(task.height >= Theme.minTarget, "task button " + i + " is tall enough");
                // Long titles elide; the accessible name keeps the full title.
                compare(task.Accessible.name, "Window with a long title number " + (i + 1));
            }
        }
    }
}
