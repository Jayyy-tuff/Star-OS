// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// Game Center's page (M0.5, ADR-0017): a header with search, the filters,
// game mode, "Get games" and Steam; "Continue playing" with the games played
// last; every game as a tile. Keyboard: typing searches, Down and Tab enter
// the grid, arrows move, Return starts a game, Escape clears the search.
//
// 'library' is GameLibrary (or a test double): a list model with the roles
// name, gameId, source, emulator, icon and lastPlayed; the properties
// filter, search, totalCount, steamDesktopId, gameModeAvailable, gameMode
// and running; the functions launch(row), launchGame(gameId), getGames() and
// openSteam(); and the signals launched(gameId) and launchFailed(name).
FocusScope {
    id: root

    property var library: null
    // The games list; tests pass a ListModel here and the functions apart.
    property var model: root.library
    property string status: ""

    readonly property var filters: [
        {key: "all", name: qsTr("All")},
        {key: "steam", name: qsTr("Steam")},
        {key: "apps", name: qsTr("Apps")},
        {key: "emulators", name: qsTr("Emulators")}
    ]
    // The four games played last, newest first.
    readonly property var recent: {
        const list = [];
        if (!root.library) {
            return list;
        }
        void root.revision; // launches change lastPlayed in place
        for (let i = 0; i < root.library.count; ++i) {
            const game = root.library.get(i);
            if (game.lastPlayed && !isNaN(new Date(game.lastPlayed).getTime()) && new Date(game.lastPlayed).getTime() > 0) {
                list.push(game);
            }
        }
        list.sort((a, b) => new Date(b.lastPlayed).getTime() - new Date(a.lastPlayed).getTime());
        return list.slice(0, 4);
    }
    property int revision: 0

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Game Center")

    function startRow(row) {
        const game = root.library.get(row);
        if (root.library.launch(row)) {
            root.status = qsTr("Starting %1…").arg(game.name);
        }
    }

    function startGame(gameId, name) {
        if (root.library.launchGame(gameId)) {
            root.status = qsTr("Starting %1…").arg(name);
        }
    }

    function enterGrid() {
        if (grid.count > 0) {
            grid.currentIndex = Math.max(0, grid.currentIndex);
            grid.forceActiveFocus(Qt.TabFocusReason);
            return true;
        }
        return false;
    }

    Connections {
        target: root.library
        ignoreUnknownSignals: true

        function onLaunchFailed(name) {
            root.status = qsTr("Could not start %1.").arg(name);
        }
        function onLaunched(gameId) {
            root.revision += 1;
        }
        function onCountChanged() {
            root.revision += 1;
        }
    }

    // Typing anywhere searches.
    Keys.onPressed: event => {
        if (event.text.length === 1 && event.text.charCodeAt(0) > 32 && !search.activeFocus
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            search.forceActiveFocus(Qt.ShortcutFocusReason);
            search.text += event.text;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "#171a4a"
            }
            GradientStop {
                position: 0.55
                color: Theme.desktop
            }
            GradientStop {
                position: 1
                color: Theme.launcherBackdrop
            }
        }
        Accessible.ignored: true
    }

    Flickable {
        id: page
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 2 * Theme.panelPadding
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: content
            x: Theme.panelPadding * 1.5
            y: Theme.panelPadding
            width: page.width - 2 * x
            spacing: Theme.spacing * 1.5

            // Title, count and search.
            Item {
                width: parent.width
                height: Math.max(titleColumn.implicitHeight, search.height)

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacing

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(2.6 * Theme.gridUnit)
                        height: width
                        radius: Theme.controlRadius * 1.5
                        gradient: Theme.accentGradient

                        Symbol {
                            anchors.centerIn: parent
                            width: Math.round(parent.width * 0.6)
                            height: width
                            name: "gamepad"
                        }
                    }

                    Column {
                        id: titleColumn
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            objectName: "title"
                            text: qsTr("Game Center")
                            color: Theme.text
                            font.family: Theme.metrics.font.family
                            font.pixelSize: Theme.titlePixelSize
                            font.weight: Font.DemiBold
                            Accessible.role: Accessible.Heading
                            Accessible.name: text
                        }

                        Text {
                            objectName: "countLabel"
                            text: !root.library ? ""
                                : root.library.totalCount === 1 ? qsTr("1 game") : qsTr("%1 games").arg(root.library.totalCount)
                            color: Theme.textSecondary
                            font.family: Theme.metrics.font.family
                            font.pixelSize: Theme.smallPixelSize
                            Accessible.ignored: true
                        }
                    }
                }

                T.TextField {
                    id: search
                    objectName: "searchField"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(Math.round(20 * Theme.gridUnit), parent.width / 2)
                    height: Theme.searchHeight
                    leftPadding: Theme.spacing + Theme.symbolSize + Theme.spacing / 2
                    rightPadding: Theme.spacing
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    placeholderText: qsTr("Search games")
                    placeholderTextColor: Theme.placeholder
                    font: Theme.metrics.font
                    Accessible.name: qsTr("Search games")

                    onTextChanged: {
                        if (root.library) {
                            root.library.search = search.text;
                        }
                    }

                    background: Rectangle {
                        radius: height / 2
                        color: Theme.searchField
                        border.width: 1
                        border.color: search.activeFocus ? Theme.searchBorder : Theme.glassBorder

                        Symbol {
                            x: Theme.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            name: "search"
                            opacity: 0.8
                        }
                    }

                    Keys.onDownPressed: event => {
                        event.accepted = root.enterGrid();
                    }
                    Keys.onReturnPressed: event => {
                        if (grid.count > 0) {
                            root.startRow(0);
                        }
                        event.accepted = true;
                    }
                    Keys.onEscapePressed: event => {
                        event.accepted = search.text !== "";
                        search.text = "";
                    }

                    FocusFrame {
                        visible: search.activeFocus
                        radius: height / 2
                    }
                }
            }

            // Filters, game mode and where games come from.
            Flow {
                width: parent.width
                spacing: Theme.spacing

                Repeater {
                    model: root.filters

                    ShellButton {
                        id: chip

                        required property var modelData

                        objectName: "filter-" + chip.modelData.key
                        height: Math.round(1.9 * Theme.gridUnit)
                        radius: height / 2
                        text: chip.modelData.name
                        highlighted: root.library !== null && root.library.filter === chip.modelData.key
                        Accessible.role: Accessible.RadioButton
                        Accessible.checkable: true
                        Accessible.checked: chip.highlighted
                        onClicked: root.library.filter = chip.modelData.key
                    }
                }

                Item {
                    width: Theme.spacing
                    height: 1
                }

                T.Switch {
                    id: gameModeSwitch
                    objectName: "gameModeSwitch"
                    visible: root.library !== null && root.library.gameModeAvailable
                    implicitWidth: switchTrack.width + switchLabel.implicitWidth + Theme.spacing
                    implicitHeight: Math.round(1.9 * Theme.gridUnit)
                    checked: root.library !== null && root.library.gameMode
                    text: qsTr("Game mode")
                    focusPolicy: Qt.StrongFocus

                    Accessible.role: Accessible.CheckBox
                    Accessible.name: text
                    Accessible.checked: gameModeSwitch.checked
                    Accessible.description: qsTr("Games started here run with GameMode and hold notifications back. Steam and Flatpak games turn it on themselves.")

                    onToggled: root.library.gameMode = gameModeSwitch.checked

                    indicator: Rectangle {
                        id: switchTrack
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(2.2 * Theme.gridUnit)
                        height: Math.round(1.2 * Theme.gridUnit)
                        radius: height / 2
                        color: gameModeSwitch.checked ? Theme.accent : Theme.glassButtonActive
                        border.width: gameModeSwitch.activeFocus ? Theme.focusRingWidth : 0
                        border.color: Theme.focusRing

                        Rectangle {
                            x: gameModeSwitch.checked ? parent.width - width - 3 : 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.height - 6
                            height: width
                            radius: width / 2
                            color: Theme.text
                        }
                    }

                    contentItem: Text {
                        id: switchLabel
                        leftPadding: switchTrack.width + Theme.spacing
                        text: gameModeSwitch.text
                        color: Theme.text
                        font: Theme.metrics.font
                        verticalAlignment: Text.AlignVCenter
                        Accessible.ignored: true
                    }
                }

                ShellButton {
                    objectName: "getGamesButton"
                    height: Math.round(1.9 * Theme.gridUnit)
                    radius: height / 2
                    symbol: "plus"
                    text: qsTr("Get games")
                    description: qsTr("Open Sun Store's games")
                    onClicked: root.library.getGames()
                }

                ShellButton {
                    objectName: "steamButton"
                    height: Math.round(1.9 * Theme.gridUnit)
                    radius: height / 2
                    visible: root.library !== null && root.library.steamDesktopId !== ""
                    text: qsTr("Open Steam")
                    onClicked: root.library.openSteam()
                }
            }

            Text {
                objectName: "status"
                width: parent.width
                visible: root.status !== ""
                text: root.status
                color: Theme.activeIndicator
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            // Continue playing.
            Column {
                objectName: "recent"
                width: parent.width
                spacing: Theme.spacing
                visible: root.recent.length > 0 && root.library.search === "" && root.library.filter === "all"

                Text {
                    text: qsTr("Continue playing")
                    color: Theme.text
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.headingPixelSize
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                Row {
                    id: recentRow
                    spacing: Theme.spacing

                    readonly property real cardWidth: Math.min(Math.round(16 * Theme.gridUnit),
                                                               (content.width - 3 * Theme.spacing) / 4)

                    Repeater {
                        model: root.recent

                        GameTile {
                            id: recentTile

                            required property var modelData

                            objectName: "recentTile"
                            width: recentRow.cardWidth
                            height: Math.round(recentRow.cardWidth * 0.5)
                            wide: true
                            name: recentTile.modelData.name
                            iconName: recentTile.modelData.icon
                            source: recentTile.modelData.source
                            emulator: recentTile.modelData.emulator
                            onClicked: root.startGame(recentTile.modelData.gameId, recentTile.modelData.name)
                        }
                    }
                }
            }

            Text {
                text: qsTr("Library")
                visible: grid.count > 0
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.headingPixelSize
                font.weight: Font.DemiBold
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            GridView {
                id: grid
                objectName: "games"
                width: parent.width
                height: contentHeight
                interactive: false
                visible: count > 0
                model: root.model
                cellWidth: width / Math.max(2, Math.floor(width / Math.round(10 * Theme.gridUnit)))
                cellHeight: Math.round(cellWidth * 0.75) + Math.round(2.6 * Theme.gridUnit)
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                activeFocusOnTab: count > 0
                currentIndex: 0

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Games")

                // Keep the focused tile on screen.
                onCurrentItemChanged: {
                    if (grid.currentItem && grid.activeFocus) {
                        const p = grid.currentItem.mapToItem(content, 0, 0);
                        page.contentY = Math.max(0, Math.min(page.contentHeight - page.height,
                            Math.min(page.contentY, p.y) + Math.max(0, p.y + grid.currentItem.height - page.contentY - page.height)));
                    }
                }

                Keys.onUpPressed: event => {
                    if (grid.currentIndex < Math.floor(grid.width / grid.cellWidth)) {
                        search.forceActiveFocus(Qt.BacktabFocusReason);
                        event.accepted = true;
                    } else {
                        event.accepted = false;
                    }
                }

                delegate: Item {
                    id: cell

                    required property int index
                    required property string name
                    required property string icon
                    required property string source
                    required property bool emulator

                    width: grid.cellWidth
                    height: grid.cellHeight

                    GameTile {
                        objectName: "tile"
                        anchors.fill: parent
                        anchors.margins: Theme.spacing / 2
                        focus: cell.GridView.isCurrentItem
                        name: cell.name
                        iconName: cell.icon
                        source: cell.source
                        emulator: cell.emulator
                        onClicked: {
                            grid.currentIndex = cell.index;
                            root.startRow(cell.index);
                        }
                    }
                }
            }

            // No games, or none matching.
            Column {
                objectName: "emptyState"
                width: parent.width
                visible: grid.count === 0
                spacing: Theme.spacing
                topPadding: Theme.panelPadding * 2

                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.round(4 * Theme.gridUnit)
                    height: width
                    name: "gamepad"
                    opacity: 0.6
                }

                Text {
                    objectName: "emptyTitle"
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.library && root.library.totalCount === 0 ? qsTr("No games yet")
                        : root.library && root.library.search !== "" ? qsTr("No games match “%1”").arg(root.library.search)
                        : qsTr("No games here")
                    color: Theme.text
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.headingPixelSize
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: qsTr("Games you install from Sun Store or Steam appear here.")
                    color: Theme.textSecondary
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Math.round(Theme.fontSize)
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                ShellButton {
                    objectName: "emptyGetGamesButton"
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.library !== null && root.library.totalCount === 0
                    highlighted: true
                    symbol: "plus"
                    text: qsTr("Get games")
                    onClicked: root.library.getGames()
                }
            }
        }
    }
}
