// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Start menu (M0.5): the panel above the taskbar, pinned apps, search,
// all apps, recently installed, quick answers and notes, the power menu,
// keyboard paths, accessible names and the visible focus ring.
Item {
    id: root

    width: 1280
    height: 720

    FakeCatalogue {
        id: fakeCatalogue
    }

    StartMenu {
        id: menu
        anchors.fill: parent
        catalogue: fakeCatalogue
        pinnedIds: ["org.staros.files.desktop", "org.kde.konsole.desktop", "missing.desktop",
            "org.staros.sunstore.desktop", "systemsettings.desktop"]
        userName: "Star OS live user"
        userDetail: "Live session · changes are kept in memory"
    }

    Component {
        id: shortMenuComponent

        StartMenu {
            width: 1280
            height: 420
            pinnedIds: ["org.staros.files.desktop", "org.kde.konsole.desktop"]
        }
    }

    SignalSpy {
        id: closeSpy
        target: menu
        signalName: "closeRequested"
    }

    SignalSpy {
        id: answerSpy
        target: menu
        signalName: "answerCopied"
    }

    SignalSpy {
        id: noteSpy
        target: menu
        signalName: "noteRequested"
    }

    SignalSpy {
        id: restartSpy
        target: menu
        signalName: "restartRequested"
    }

    SignalSpy {
        id: lockSpy
        target: menu
        signalName: "lockRequested"
    }

    // Reads the clipboard back.
    TextInput {
        id: pasteTarget
        visible: false
    }

    TestCase {
        id: testCase
        name: "StartMenu"
        when: windowShown

        readonly property var defaultApps: [
            {AppName: "Konsole", GenericName: "Terminal", AppId: "org.kde.konsole.desktop"},
            {AppName: "System Settings", GenericName: "System Settings", AppId: "systemsettings.desktop"},
            {AppName: "Files", GenericName: "File Manager", AppId: "org.staros.files.desktop"},
            {AppName: "Sun Store", GenericName: "Software Store", AppId: "org.staros.sunstore.desktop"}
        ]
        readonly property var gimp: ({AppName: "GIMP", GenericName: "Image Editor", AppId: "org.gimp.GIMP.desktop",
                                      Source: "flatpak", IsNew: true})
        property Item searchField
        property GridView pinned
        property GridView recent
        property ListView results
        property ListView allApps
        property Item home
        property Item emptyState

        function initTestCase() {
            Theme.animationFactor = 0;
            searchField = findChild(menu, "searchField");
            pinned = findChild(menu, "pinned");
            recent = findChild(menu, "recent");
            results = findChild(menu, "appGrid");
            allApps = findChild(menu, "allApps");
            home = findChild(menu, "home");
            emptyState = findChild(menu, "emptyState");
            verify(searchField && pinned && recent && results && allApps && home && emptyState);
        }

        function init() {
            fakeCatalogue.entries = defaultApps;
            fakeCatalogue.recent = [];
            fakeCatalogue.launched = [];
            fakeCatalogue.launchResult = true;
            closeSpy.clear();
            answerSpy.clear();
            noteSpy.clear();
            restartSpy.clear();
            lockSpy.clear();
            menu.reset();
            tryVerify(() => searchField.activeFocus, 5000, "search field has focus");
        }

        function type(text) {
            for (const ch of text) {
                keyClick(ch);
            }
        }

        function pinnedNames() {
            const names = [];
            for (let i = 0; i < pinned.count; ++i) {
                names.push(findChild(pinned.itemAtIndex(i), "tile").Accessible.name);
            }
            return names;
        }

        function focusedTile() {
            tryVerify(() => pinned.currentItem !== null && findChild(pinned.currentItem, "tile").activeFocus, 5000,
                      "a pinned tile has focus");
            return findChild(pinned.currentItem, "tile");
        }

        function focusedTileAfterDown() {
            keyClick(Qt.Key_Down);
            return focusedTile();
        }

        // Longest horizontal run of focus-ring pixels starting at an item's
        // left edge, in device pixels. With the software scene graph,
        // grabImage() returns device pixels without a pixel ratio, cropped to
        // the item's logical size, so coordinates are scaled by the screen's
        // ratio and must stay inside that crop.
        function ringRun(item) {
            waitForRendering(menu);
            const img = grabImage(menu);
            const dpr = Screen.devicePixelRatio;
            const p = item.mapToItem(menu, 0, item.height / 2);
            const y = Math.floor(p.y * dpr);
            verify(Math.floor((p.x + 8) * dpr) < img.width && y < img.height,
                   "sample point inside the grabbed image " + img.width + "x" + img.height);
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
            verify(home.visible);
            verify(!findChild(menu, "results").visible);
            verify(!findChild(menu, "allAppsView").visible);
            compare(fakeCatalogue.filter, "");
            compare(menu.Accessible.role, Accessible.Pane);
            compare(menu.Accessible.name, "Application launcher");
            compare(searchField.Accessible.name, "Search applications");
            compare(pinned.Accessible.role, Accessible.List);
            compare(pinned.Accessible.name, "Pinned");
            compare(results.Accessible.name, "Applications");
        }

        // Pins in their order; pins that are not installed are left out.
        function test_pinned_apps() {
            tryCompare(pinned, "count", 4);
            tryVerify(() => pinned.itemAtIndex(3) !== null, 5000, "every pinned tile is created");
            compare(pinnedNames(), ["Files", "Konsole", "Sun Store", "System Settings"]);
            const tile = findChild(pinned.itemAtIndex(0), "tile");
            compare(tile.Accessible.role, Accessible.Button);
            compare(tile.Accessible.description, "File Manager");
            // An app installed later appears in its pin's place.
            fakeCatalogue.entries = defaultApps.concat([gimp]);
            menu.pinnedIds = ["org.gimp.GIMP.desktop", "org.staros.files.desktop"];
            tryCompare(pinned, "count", 2);
            tryVerify(() => pinned.itemAtIndex(1) !== null, 5000);
            compare(pinnedNames(), ["GIMP", "Files"]);
            menu.pinnedIds = ["org.staros.files.desktop", "org.kde.konsole.desktop", "missing.desktop",
                "org.staros.sunstore.desktop", "systemsettings.desktop"];
        }

        // Star OS artwork for known ids, the monogram for others.
        function test_tiles_show_app_icons() {
            tryVerify(() => pinned.itemAtIndex(3) !== null, 5000);
            for (let i = 0; i < pinned.count; ++i) {
                const icon = findChild(findChild(pinned.itemAtIndex(i), "tile"), "icon");
                verify(icon.appId.endsWith(".desktop"), "tile " + i + " has the storage id " + icon.appId);
                const artwork = findChild(icon, "artwork");
                tryCompare(artwork, "status", Image.Ready, 5000, icon.appId + " artwork loads");
                verify(artwork.visible && !findChild(icon, "monogram").visible);
            }
            fakeCatalogue.entries = defaultApps.concat([gimp]);
            menu.pinnedIds = ["org.gimp.GIMP.desktop"];
            tryVerify(() => pinned.itemAtIndex(0) !== null, 5000);
            const other = findChild(findChild(pinned.itemAtIndex(0), "tile"), "icon");
            verify(findChild(other, "monogram").visible);
            compare(findChild(other, "monogramLetter").text, "G");
            menu.pinnedIds = ["org.staros.files.desktop", "org.kde.konsole.desktop", "missing.desktop",
                "org.staros.sunstore.desktop", "systemsettings.desktop"];
        }

        // The panel sits popupGap above the taskbar's pill, centred, and its
        // glass shows the wallpaper behind it.
        function test_panel_geometry() {
            const panel = findChild(menu, "panel");
            const glass = findChild(panel, "glass");
            compare(panel.y + panel.height,
                    root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap);
            compare(panel.x, Math.round((root.width - panel.width) / 2));
            compare(panel.width, Theme.startMenuWidth);
            compare(glass.wallpaperOrigin.x, panel.x);
            compare(glass.wallpaperOrigin.y, panel.y);
            compare(glass.screenSize.width, root.width);
            compare(glass.screenSize.height, root.height);
            if (glass.blurAvailable) {
                return;
            }
            waitForRendering(menu);
            const img = grabImage(menu);
            const dpr = Screen.devicePixelRatio;
            const x = Math.floor((panel.x + 6) * dpr);
            const y = Math.floor((panel.y + panel.height / 2) * dpr);
            const ok = Math.abs(img.red(x, y) - Theme.glassFallback.r * 255) <= 2
                && Math.abs(img.green(x, y) - Theme.glassFallback.g * 255) <= 2
                && Math.abs(img.blue(x, y) - Theme.glassFallback.b * 255) <= 2;
            verify(ok, "panel " + img.pixel(x, y) + ", expected " + Theme.glassFallback);
        }

        function test_typing_filters() {
            type("kon");
            compare(searchField.text, "kon");
            compare(fakeCatalogue.filter, "kon");
            verify(findChild(menu, "results").visible);
            verify(!home.visible);
            compare(results.count, 1);
            verify(searchField.activeFocus);
        }

        function test_return_in_search_launches_first_match() {
            type("sys");
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["System Settings"]);
            compare(closeSpy.count, 1);
        }

        function test_enter_launches_first_match() {
            type("fi");
            keyClick(Qt.Key_Enter);
            compare(fakeCatalogue.launched, ["Files"]);
            compare(closeSpy.count, 1);
        }

        function test_return_without_text_does_nothing() {
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, []);
            compare(closeSpy.count, 0);
        }

        function test_refused_launch_keeps_the_menu_open() {
            fakeCatalogue.launchResult = false;
            type("fil");
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["Files"]);
            compare(closeSpy.count, 0);
        }

        function test_down_moves_to_pinned_and_up_returns() {
            focusedTileAfterDown();
            compare(pinned.currentIndex, 0);
            keyClick(Qt.Key_Up);
            verify(searchField.activeFocus);
        }

        function test_down_in_results_and_return() {
            type("s");
            keyClick(Qt.Key_Down);
            tryVerify(() => results.currentItem !== null && results.currentItem.activeFocus, 5000);
            keyClick(Qt.Key_Down);
            tryCompare(results, "currentIndex", 1);
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched.length, 1);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            verify(searchField.activeFocus);
        }

        function test_tab_moves_to_pinned() {
            keyClick(Qt.Key_Tab);
            compare(focusedTile().Accessible.name, "Files");
        }

        function test_arrows_and_return_launch_a_tile() {
            focusedTileAfterDown();
            keyClick(Qt.Key_Right);
            compare(pinned.currentIndex, 1);
            compare(focusedTile().Accessible.name, "Konsole");
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["Konsole"]);
            compare(closeSpy.count, 1);
        }

        function test_space_launches_a_tile() {
            focusedTileAfterDown();
            keyClick(Qt.Key_Space);
            compare(fakeCatalogue.launched, ["Files"]);
        }

        function test_click_launches_a_tile() {
            tryVerify(() => pinned.itemAtIndex(3) !== null, 5000);
            mouseClick(findChild(pinned.itemAtIndex(3), "tile"));
            compare(fakeCatalogue.launched, ["System Settings"]);
            compare(closeSpy.count, 1);
        }

        function test_typing_in_grid_returns_to_search() {
            focusedTileAfterDown();
            keyClick("o");
            compare(searchField.text, "o");
            verify(searchField.activeFocus);
        }

        // Escape clears the search, leaves All apps and the power menu, and
        // only then closes.
        function test_escape_steps_back() {
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 1);
            type("kon");
            keyClick(Qt.Key_Escape);
            compare(searchField.text, "");
            compare(closeSpy.count, 1);
            mouseClick(findChild(menu, "allAppsButton"));
            verify(findChild(menu, "allAppsView").visible);
            keyClick(Qt.Key_Escape);
            verify(home.visible);
            compare(closeSpy.count, 1);
            focusedTileAfterDown();
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 2);
        }

        function test_click_outside_the_panel_closes() {
            mouseClick(menu, 5, 5);
            compare(closeSpy.count, 1);
            const panel = findChild(menu, "panel");
            mouseClick(menu, panel.x + 6, panel.y + panel.height / 2);
            compare(closeSpy.count, 1);
        }

        function test_empty_state() {
            type("zz");
            compare(results.count, 0);
            verify(emptyState.visible);
            keyClick(Qt.Key_Down);
            verify(searchField.activeFocus);
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, []);
            compare(closeSpy.count, 0);
        }

        function test_reset_clears_search() {
            type("kon");
            menu.reset();
            compare(searchField.text, "");
            compare(fakeCatalogue.filter, "");
            verify(home.visible);
            verify(searchField.activeFocus);
        }

        function test_all_apps() {
            const button = findChild(menu, "allAppsButton");
            compare(button.Accessible.name, "All apps");
            mouseClick(button);
            const view = findChild(menu, "allAppsView");
            verify(view.visible && !home.visible);
            tryCompare(allApps, "count", 4);
            compare(allApps.section.property, "Section");
            tryVerify(() => allApps.currentItem !== null && allApps.currentItem.activeFocus, 5000,
                      "the first app has focus");
            compare(allApps.currentItem.Accessible.name, "Files");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["Konsole"]);
            mouseClick(findChild(menu, "backButton"));
            verify(home.visible);
        }

        function test_recently_installed() {
            const now = new Date();
            menu.now = now;
            fakeCatalogue.entries = defaultApps.concat([gimp]);
            fakeCatalogue.recent = [Object.assign({InstalledAt: new Date(now.getTime() - 5 * 60000)}, gimp)];
            tryCompare(recent, "count", 1);
            verify(recent.visible);
            verify(!findChild(menu, "recentHint").visible);
            tryVerify(() => recent.itemAtIndex(0) !== null, 5000);
            const row = recent.itemAtIndex(0);
            compare(row.Accessible.name, "GIMP");
            compare(row.Accessible.description, "New. Installed 5 min ago · Flatpak");
            verify(findChild(row, "newBadge").visible);
            mouseClick(row);
            compare(fakeCatalogue.launched, ["GIMP"]);
            compare(closeSpy.count, 1);
        }

        function test_installed_detail() {
            const now = new Date(2026, 9, 25, 12, 0, 0);
            menu.now = now;
            const ago = minutes => ({InstalledAt: new Date(now.getTime() - minutes * 60000), Source: "user"});
            compare(menu.installedDetail(ago(0)), "Installed just now · Your apps");
            compare(menu.installedDetail(ago(90)), "Installed 2 h ago · Your apps");
            compare(menu.installedDetail(ago(3 * 24 * 60)), "Installed 3 days ago · Your apps");
            compare(menu.installedDetail({InstalledAt: new Date(now.getTime() - 60000), Source: "flatpak"}),
                    "Installed 1 min ago · Flatpak");
        }

        function test_no_recent_apps_shows_a_hint() {
            compare(recent.count, 0);
            verify(!recent.visible);
            const hint = findChild(menu, "recentHint");
            verify(hint.visible);
            compare(hint.text, "Apps you install from Sun Store appear here.");
            mouseClick(findChild(menu, "storeButton"));
            compare(fakeCatalogue.launched, ["Sun Store"]);
        }

        // A short screen keeps the pinned apps and leaves out the rest.
        function test_recent_is_left_out_when_short() {
            const short = createTemporaryObject(shortMenuComponent, root, {catalogue: fakeCatalogue});
            verify(short !== null);
            const shortPinned = findChild(short, "pinned");
            tryCompare(shortPinned, "count", 2);
            verify(shortPinned.visible);
            verify(!findChild(short, "recent").visible);
            verify(!findChild(short, "recentHint").visible);
            const panel = findChild(short, "panel");
            verify(panel.y >= 0, "the panel fits: y " + panel.y);
        }

        function test_footer_and_power_menu() {
            const lock = findChild(menu, "lockButton");
            const settings = findChild(menu, "settingsButton");
            const power = findChild(menu, "powerButton");
            const powerMenu = findChild(menu, "powerMenu");
            compare(lock.Accessible.name, "Lock");
            compare(settings.Accessible.name, "Settings");
            compare(power.Accessible.name, "Power");
            verify(!powerMenu.visible);
            mouseClick(power);
            verify(powerMenu.visible);
            compare(powerMenu.Accessible.name, "Power");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(restartSpy.count, 1);
            keyClick(Qt.Key_Escape);
            verify(!powerMenu.visible);
            verify(power.activeFocus);
            mouseClick(lock);
            compare(lockSpy.count, 1);
            mouseClick(settings);
            compare(fakeCatalogue.launched, ["System Settings"]);
        }

        // Sums get an answer card; Return copies the answer and closes.
        function test_quick_answer() {
            const card = findChild(menu, "answerCard");
            const label = findChild(menu, "answerLabel");
            verify(!card.visible);
            type("12*3");
            verify(card.visible);
            compare(label.text, "= 36");
            compare(label.Accessible.name, "Answer: 36");
            compare(searchField.Accessible.description, "Answer: 36. Press Return to copy it.");
            keyClick(Qt.Key_Return);
            compare(answerSpy.count, 1);
            compare(answerSpy.signalArguments[0][0], "36");
            compare(closeSpy.count, 1);
            compare(fakeCatalogue.launched, []);
            pasteTarget.text = "";
            pasteTarget.paste();
            compare(pasteTarget.text, "36");
        }

        function test_unit_conversion_answer() {
            type("5 km in miles");
            compare(findChild(menu, "answerLabel").text, "= 3.106855961 mi");
        }

        // Text without an answer launches the first match.
        function test_no_answer_launches() {
            type("fil");
            verify(!findChild(menu, "answerCard").visible);
            keyClick(Qt.Key_Return);
            compare(fakeCatalogue.launched, ["Files"]);
            compare(answerSpy.count, 0);
        }

        // "note:" makes a sticky note on Return.
        function test_note_prefix() {
            const label = findChild(menu, "answerLabel");
            type("note:");
            verify(findChild(menu, "answerCard").visible);
            compare(label.text, "Type the note after “note:”");
            compare(fakeCatalogue.filter, "");
            keyClick(Qt.Key_Return);
            compare(noteSpy.count, 0);
            compare(closeSpy.count, 0);
            type(" buy milk");
            compare(label.text, "New sticky note: buy milk");
            keyClick(Qt.Key_Return);
            compare(noteSpy.count, 1);
            compare(noteSpy.signalArguments[0][0], "buy milk");
            compare(closeSpy.count, 1);
            compare(fakeCatalogue.launched, []);
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
