// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// The Game Center window. The title is also its accessible name.
Window {
    id: window

    width: 1100
    height: 720
    minimumWidth: 640
    minimumHeight: 420
    visible: true
    title: qsTr("Game Center")
    color: Theme.desktop

    GameLibrary {
        id: gameLibrary
        onLaunched: gameId => console.info("STAROS-GAMES launched " + gameId)
        onLaunchFailed: name => console.warn("STAROS-GAMES could not start " + name)
    }

    GameCenterView {
        anchors.fill: parent
        focus: true
        library: gameLibrary
    }

    Component.onCompleted: console.info("STAROS-GAMES ready games=" + gameLibrary.totalCount
        + " steam=" + (gameLibrary.steamDesktopId !== "") + " gamemode=" + gameLibrary.gameModeAvailable)
}
