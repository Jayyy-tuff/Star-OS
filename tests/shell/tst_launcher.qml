// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Launcher: search, keyboard path between search and grid, launching, empty
// state, accessible names and the visible focus ring.
Item {
    id: root

    width: 1280
    height: 720

    FakeCatalogue {
        id: fakeCatalogue
    }

    Launcher {
        id: launcher
        anchors.fill: parent
        catalogue: fakeCatalogue
    }

    SignalSpy {
        id: closeSpy
        target: launcher
        signalName: "closeRequested"
    }

    TestCase {
        id: testCase
        name: "Launcher"
        when: windowShown

        // Sorted by name in the catalogue: KMenuEdit, Konsole, System Settings.
        readonly property var defaultApps: [
            {AppName: "Konsole", GenericName: "Terminal"},
            {AppName: "System Settings", GenericName: "Configuration Tools"},
            {AppName: "KMenuEdit", GenericName: "Menu Editor"}
        ]
        property Item searchField
        property GridView grid
        property Item emptyState

        function initTestCase() {
            searchField = findChild(launcher, "searchField");
            grid = findChild(launcher, "appGrid");
            emptyState = findChild(launcher, "emptyState");
            verify(searchField !== null && grid !== null && emptyState !== null);
        }

        function init() {
            fakeCatalogue.apps = defaultApps;
            fakeCatalogue.launched = [];
            fakeCatalogue.launchResult = true;
            closeSpy.clear();
            launcher.reset();
            tryVerify(() => searchField.activeFocus, 5000, "search field has focus");
        }

        function type(text) {
            for (const ch of text) {
                keyClick(ch);
            }
        }

        function focusedTile() {
            tryVerify(() => grid.currentItem !== null && grid.currentItem.activeFocus, 5000,
                      "a tile has focus");
            return grid.currentItem;
        }

        // Longest horizontal run of focus-ring pixels starting at an item's
        // left edge, in device pixels.
        function ringRun(item) {
            waitForRendering(launcher);
            const img = grabImage(launcher);
            const dpr = img.width / launcher.width;
            const p = item.mapToItem(launcher, 0, item.height / 2);
            const y = Math.floor(p.y * dpr);
            const ring = [Theme.focusRing.r * 255, Theme.focusRing.g * 255, Theme.focusRing.b * 255];
            let best = 0;
            let run = 0;
            for (let x = Math.max(0, Math.floor(p.x * dpr) - 1); x < Math.floor((p.x + 8) * dpr); ++x) {
                const hit = Math.abs(img.red(x, y) - ring[0]) <= 8
                    && Math.abs(img.green(x, y) - ring[1]) <= 8
                    && Math.abs(img.blue(x, y) - ring[2]) <= 8;
                run = hit ? run + 1 : 0;
                best = Math.max(best, run);
            }
            return {run: best, dpr: dpr};
        }

        function expectRing(item) {
            const result = ringRun(item);
            const minimum = Math.max(Theme.focusRingWidth, Math.floor(Theme.focusRingWidth * result.dpr) - 1);
            verify(result.run >= minimum, "focus ring " + result.run + " px at dpr " + result.dpr
                   + ", expected at least " + minimum);
        }

        function test_initial_state() {
            compare(grid.count, 3);
            compare(fakeCatalogue.filter, "");
            verify(!emptyState.visible);
            compare(launcher.Accessible.role, Accessible.Pane);
            compare(launcher.Accessible.name, "Application launcher");
            compare(searchField.Accessible.name, "Search applications");
            compare(grid.Accessible.role, Accessible.List);
            compare(grid.Accessible.name, "Applications");
        }

        function test_tiles_have_accessible_names() {
            const tile = focusedTileAfterDown();
            compare(tile.Accessible.role, Accessible.Button);
            compare(tile.Accessible.name, "KMenuEdit");
            compare(tile.Accessible.description, "Menu Editor");
        }

        function focusedTileAfterDown() {
            keyClick(Qt.Key_Down);
            return focusedTile();
        }

        function test_typing_filters() {
            type("kon");
            compare(searchField.text, "kon");
            compare(fakeCatalogue.filter, "kon");
            compare(grid.count, 1);
            verify(searchField.activeFocus);
        }

        function test_return_in_search_launches_first_match() {
            type("sys");
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["System Settings"]);
            compare(closeSpy.count, 1);
        }

        function test_enter_in_search_launches_first_match() {
            keyClick(Qt.Key_Enter);
            compare(fakeCatalogue.launched, ["KMenuEdit"]);
            compare(closeSpy.count, 1);
        }

        function test_refused_launch_keeps_launcher_open() {
            fakeCatalogue.launchResult = false;
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["KMenuEdit"]);
            compare(closeSpy.count, 0);
        }

        function test_down_moves_to_grid_and_up_returns() {
            focusedTileAfterDown();
            compare(grid.currentIndex, 0);
            keyClick(Qt.Key_Up);
            verify(searchField.activeFocus);
        }

        function test_tab_moves_to_grid() {
            keyClick(Qt.Key_Tab);
            compare(focusedTile().Accessible.name, "KMenuEdit");
        }

        function test_arrows_and_return_launch_a_tile() {
            focusedTileAfterDown();
            keyClick(Qt.Key_Right);
            compare(grid.currentIndex, 1);
            compare(focusedTile().Accessible.name, "Konsole");
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["Konsole"]);
            compare(closeSpy.count, 1);
        }

        function test_space_launches_a_tile() {
            focusedTileAfterDown();
            keyClick(Qt.Key_Space);
            compare(fakeCatalogue.launched, ["KMenuEdit"]);
        }

        function test_click_launches_a_tile() {
            mouseClick(grid.itemAtIndex(2));
            compare(fakeCatalogue.launched, ["System Settings"]);
            compare(closeSpy.count, 1);
        }

        function test_typing_in_grid_returns_to_search() {
            focusedTileAfterDown();
            keyClick("o");
            compare(searchField.text, "o");
            verify(searchField.activeFocus);
        }

        function test_escape_closes_from_search_and_grid() {
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 1);
            launcher.reset();
            focusedTileAfterDown();
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 2);
        }

        function test_empty_state() {
            type("zz");
            compare(grid.count, 0);
            verify(emptyState.visible);
            keyClick(Qt.Key_Down);
            verify(searchField.activeFocus);
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, []);
            compare(closeSpy.count, 0);
        }

        function test_reset_clears_search() {
            type("kon");
            focusedTileAfterDown();
            launcher.reset();
            compare(searchField.text, "");
            compare(fakeCatalogue.filter, "");
            compare(grid.count, 3);
            compare(grid.currentIndex, 0);
            verify(searchField.activeFocus);
        }

        function test_focus_ring_on_search_field() {
            expectRing(searchField);
        }

        function test_focus_ring_on_tile() {
            expectRing(focusedTileAfterDown());
        }

        function test_no_focus_ring_without_focus() {
            focusedTileAfterDown();
            verify(ringRun(searchField).run === 0, "the search field shows no ring without focus");
        }
    }
}
