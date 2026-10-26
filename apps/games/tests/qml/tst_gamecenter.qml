// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell
import StarOS.Games

// Game Center's view with a test double for GameLibrary: tiles and their
// names, filters, search by typing, keyboard and click starts, "Continue
// playing", game mode, "Get games", Steam, the empty states and failures.
Item {
    id: root

    width: 1100
    height: 720

    ListModel {
        id: games
    }

    QtObject {
        id: fakeLibrary

        property var calls: []
        property string filter: "all"
        property string search: ""
        property int totalCount: games.count
        property int count: games.count
        property string steamDesktopId: "steam.desktop"
        property bool gameModeAvailable: true
        property bool gameMode: false
        property int running: 0

        signal launched(string gameId)
        signal launchFailed(string name)

        function get(row) {
            const g = games.get(row);
            return {name: g.name, gameId: g.gameId, source: g.source, emulator: g.emulator, icon: g.icon,
                    lastPlayed: g.lastPlayed};
        }
        function launch(row) {
            fakeLibrary.calls = fakeLibrary.calls.concat(["launch " + row]);
            if (games.get(row).name === "Broken") {
                fakeLibrary.launchFailed("Broken");
                return false;
            }
            fakeLibrary.launched(games.get(row).gameId);
            return true;
        }
        function launchGame(gameId) {
            fakeLibrary.calls = fakeLibrary.calls.concat(["game " + gameId]);
            return true;
        }
        function getGames() {
            fakeLibrary.calls = fakeLibrary.calls.concat(["getGames"]);
            return true;
        }
        function openSteam() {
            fakeLibrary.calls = fakeLibrary.calls.concat(["openSteam"]);
            return true;
        }
    }

    GameCenterView {
        id: view
        anchors.fill: parent
        focus: true
        library: fakeLibrary
        model: games
    }

    TestCase {
        name: "GameCenterView"
        when: windowShown

        property GridView grid

        function initTestCase() {
            Theme.animationFactor = 0;
            grid = findChild(view, "games");
            verify(grid);
        }

        function init() {
            games.clear();
            const never = new Date(NaN);
            games.append({name: "Asteroid Run", gameId: "org.example.Asteroids.desktop", source: "app", emulator: false,
                          icon: "", lastPlayed: never});
            games.append({name: "Half-Life 2", gameId: "steam:220", source: "steam", emulator: false, icon: "",
                          lastPlayed: new Date(2026, 9, 24, 20, 0)});
            games.append({name: "Portal", gameId: "steam:400", source: "steam", emulator: false, icon: "",
                          lastPlayed: new Date(2026, 9, 25, 9, 0)});
            games.append({name: "Retro Emulator", gameId: "org.example.Emu.desktop", source: "app", emulator: true,
                          icon: "", lastPlayed: never});
            games.append({name: "Super Kart", gameId: "org.example.Kart.desktop", source: "flatpak", emulator: false,
                          icon: "", lastPlayed: never});
            fakeLibrary.calls = [];
            fakeLibrary.filter = "all";
            fakeLibrary.search = "";
            fakeLibrary.gameMode = false;
            fakeLibrary.gameModeAvailable = true;
            fakeLibrary.steamDesktopId = "steam.desktop";
            view.status = "";
            findChild(view, "searchField").text = "";
            view.revision += 1;
            grid.currentIndex = 0;
            view.forceActiveFocus();
            tryVerify(() => grid.count === 5 && grid.itemAtIndex(4) !== null, 3000, "the tiles are laid out");
            waitForRendering(view);
        }

        function tile(row) {
            return findChild(grid.itemAtIndex(row), "tile");
        }

        function test_tiles() {
            compare(view.Accessible.name, "Game Center");
            compare(findChild(view, "title").text, "Game Center");
            compare(findChild(view, "countLabel").text, "5 games");
            compare(grid.Accessible.name, "Games");
            compare(tile(0).Accessible.name, "Asteroid Run");
            compare(tile(0).Accessible.description, "App");
            compare(tile(1).Accessible.description, "Steam");
            compare(tile(3).Accessible.description, "Emulator");
            compare(tile(4).Accessible.description, "Flatpak");
            // No icon: the first letter stands in.
            verify(findChild(tile(0), "letter").visible);
            compare(findChild(tile(0), "letter").text, "A");
            verify(!findChild(view, "emptyState").visible);
        }

        function test_continue_playing() {
            const recent = findChild(view, "recent");
            verify(recent.visible);
            compare(view.recent.length, 2);
            compare(view.recent[0].name, "Portal");
            compare(view.recent[1].name, "Half-Life 2");
            const first = findChild(recent, "recentTile");
            verify(first);
            mouseClick(first);
            compare(fakeLibrary.calls, ["game steam:400"]);
            compare(view.status, "Starting Portal…");
            fakeLibrary.search = "x";
            verify(!recent.visible, "hidden while searching");
        }

        function test_filters() {
            const steam = findChild(view, "filter-steam");
            verify(steam);
            compare(steam.Accessible.role, Accessible.RadioButton);
            verify(findChild(view, "filter-all").highlighted);
            mouseClick(steam);
            compare(fakeLibrary.filter, "steam");
            verify(steam.highlighted);
            verify(!findChild(view, "filter-all").highlighted);
            mouseClick(findChild(view, "filter-emulators"));
            compare(fakeLibrary.filter, "emulators");
        }

        function test_typing_searches() {
            keyClick("p");
            keyClick("o");
            const search = findChild(view, "searchField");
            verify(search.activeFocus);
            compare(search.text, "po");
            compare(fakeLibrary.search, "po");
            keyClick(Qt.Key_Escape);
            compare(search.text, "");
            compare(fakeLibrary.search, "");
        }

        function test_keyboard_start() {
            const search = findChild(view, "searchField");
            search.forceActiveFocus();
            keyClick(Qt.Key_Down);
            tryVerify(() => tile(0).activeFocus, 2000, "the first tile has focus");
            keyClick(Qt.Key_Right);
            tryVerify(() => tile(1).activeFocus);
            keyClick(Qt.Key_Return);
            compare(fakeLibrary.calls, ["launch 1"]);
            compare(view.status, "Starting Half-Life 2…");
            // Up from the first row goes back to the search field.
            keyClick(Qt.Key_Up);
            verify(search.activeFocus);
            // Return in the search field starts the first game.
            keyClick(Qt.Key_Return);
            compare(fakeLibrary.calls, ["launch 1", "launch 0"]);
        }

        function test_click_start_and_failure() {
            mouseClick(tile(4));
            compare(fakeLibrary.calls, ["launch 4"]);
            games.setProperty(2, "name", "Broken");
            waitForRendering(view);
            mouseClick(tile(2));
            compare(view.status, "Could not start Broken.");
        }

        function test_game_mode() {
            const toggle = findChild(view, "gameModeSwitch");
            verify(toggle.visible);
            compare(toggle.Accessible.role, Accessible.CheckBox);
            verify(toggle.Accessible.description.includes("GameMode"));
            mouseClick(toggle);
            verify(fakeLibrary.gameMode);
            fakeLibrary.gameModeAvailable = false;
            verify(!toggle.visible);
        }

        function test_get_games_and_steam() {
            mouseClick(findChild(view, "getGamesButton"));
            mouseClick(findChild(view, "steamButton"));
            compare(fakeLibrary.calls, ["getGames", "openSteam"]);
            fakeLibrary.steamDesktopId = "";
            verify(!findChild(view, "steamButton").visible);
        }

        function test_empty_library() {
            games.clear();
            tryVerify(() => findChild(view, "emptyState").visible);
            compare(findChild(view, "emptyTitle").text, "No games yet");
            compare(findChild(view, "countLabel").text, "0 games");
            const get = findChild(view, "emptyGetGamesButton");
            verify(get.visible);
            waitForRendering(view);
            mouseClick(get);
            compare(fakeLibrary.calls, ["getGames"]);
        }

        function test_no_match() {
            // The library has games, but none matches the search.
            fakeLibrary.totalCount = 5;
            games.clear();
            fakeLibrary.search = "zelda";
            tryVerify(() => findChild(view, "emptyState").visible);
            compare(findChild(view, "emptyTitle").text, "No games match “zelda”");
            verify(!findChild(view, "emptyGetGamesButton").visible);
            fakeLibrary.totalCount = Qt.binding(() => games.count);
        }
    }
}
