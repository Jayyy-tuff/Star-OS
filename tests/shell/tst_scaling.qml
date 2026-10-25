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

    StartMenu {
        id: launcher
        anchors.fill: parent
        catalogue: fakeCatalogue
        pinnedIds: ["org.kde.konsole.desktop", "systemsettings.desktop", "org.staros.sunstore.desktop",
            "helper.desktop", "long.desktop", "calculator.desktop"]
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
            {AppName: "Konsole", GenericName: "Terminal", AppId: "org.kde.konsole.desktop"},
            {AppName: "System Settings", GenericName: "System Settings", AppId: "systemsettings.desktop"},
            {AppName: "Sun Store", GenericName: "Software Store", AppId: "org.staros.sunstore.desktop"},
            {AppName: "Access Helper", GenericName: "Twelve chars", AppId: "helper.desktop"},
            {AppName: "An Application With A Rather Long Descriptive Name", GenericName: "Long", AppId: "long.desktop"},
            {AppName: "Calculator", GenericName: "Scientific Calculator", AppId: "calculator.desktop"}
        ]

        function initTestCase() {
            Theme.animationFactor = 0;
            fakeCatalogue.entries = apps;
            launcher.reset();
            windows.clear();
            for (let i = 0; i < 3; ++i) {
                windows.append({display: "Window with a long title number " + (i + 1),
                                AppName: "Konsole", AppId: "org.kde.konsole", IsActive: i === 0, IsWindow: true});
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

        // The start menu's panel fits the screen above the taskbar, and its
        // pinned tiles fit the panel without overlapping.
        function test_start_menu_tiles() {
            const grid = findChild(launcher, "pinned");
            const search = findChild(launcher, "searchField");
            const panel = findChild(launcher, "panel");
            tryCompare(grid, "count", apps.length);
            waitForRendering(launcher);
            verify(grid.columns >= 1);
            verify(inside(rectOf(panel, launcher), launcher.width, launcher.height), "the panel is on the screen");
            verify(rectOf(panel, launcher).y + panel.height <= launcher.height - Theme.taskbarPillHeight - Theme.taskbarGap,
                   "the panel is above the taskbar");
            verify(inside(rectOf(search, panel), panel.width, panel.height), "search field inside the panel");
            const rects = [];
            for (let i = 0; i < grid.count; ++i) {
                verify(grid.itemAtIndex(i) !== null, "tile " + i + " exists");
                const tile = findChild(grid.itemAtIndex(i), "tile");
                const r = rectOf(tile, panel);
                verify(inside(r, panel.width, panel.height), "tile " + i + " inside the panel: " + JSON.stringify(r));
                verify(tile.width >= Theme.minTarget && tile.height >= Theme.minTarget);
                for (const other of rects) {
                    verify(!overlap(r, other), "tile " + i + " overlaps another tile");
                }
                rects.push(r);
                const icon = findChild(tile, "icon");
                const label = findChild(tile, "label");
                verify(icon !== null && label !== null);
                const iconRect = rectOf(icon, tile);
                verify(inside(iconRect, tile.width, tile.height), "tile " + i + " icon inside the tile");
                verify(rectOf(label, tile).y >= iconRect.y + iconRect.h - 0.5, "tile " + i + " label below the icon");
                if (tile.Accessible.name.length <= 13) {
                    verify(!label.truncated, "'" + tile.Accessible.name + "' is truncated");
                }
            }
        }

        // Three long-titled windows fit in a 960 wide taskbar; the pill stays
        // inside it.
        function test_taskbar_fits_at_960() {
            const applications = findChild(taskbar, "applicationsButton");
            const list = findChild(taskbar, "openWindows");
            const bell = findChild(taskbar, "notificationButton");
            const pill = findChild(taskbar, "pill");
            tryCompare(list, "count", 3);
            waitForRendering(taskbar);
            verify(list.contentWidth <= list.width + 0.5,
                   "three task buttons fit: " + list.contentWidth + " > " + list.width);
            verify(inside(rectOf(pill, taskbar), taskbar.width, taskbar.height), "the pill is inside the taskbar");
            verify(inside(rectOf(applications, pill), pill.width, pill.height));
            verify(inside(rectOf(bell, pill), pill.width, pill.height));
            verify(applications.height >= Theme.minTarget && bell.height >= Theme.minTarget);
            for (let i = 0; i < list.count; ++i) {
                const task = list.itemAtIndex(i);
                verify(task.width >= Theme.minTarget, "task button " + i + " is wide enough");
                verify(task.height >= Theme.minTarget, "task button " + i + " is tall enough");
                verify(inside(rectOf(findChild(task, "icon"), task), task.width, task.height),
                       "task button " + i + " icon inside the button");
                // The accessible name keeps the full title.
                compare(task.Accessible.name, "Window with a long title number " + (i + 1));
            }
        }
    }
}
