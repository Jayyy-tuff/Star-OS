// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// The Welcome window. The title is also its accessible name.
Window {
    id: window

    width: 960
    height: 640
    minimumWidth: 560
    minimumHeight: 480
    visible: true
    title: qsTr("Welcome to Star OS")
    color: Theme.desktop

    WelcomeState {
        id: welcomeState
        onOpened: desktopId => console.info("STAROS-WELCOME opened " + desktopId)
    }

    WelcomeView {
        anchors.fill: parent
        focus: true
        welcome: welcomeState
        onDone: {
            console.info("STAROS-WELCOME done");
            window.close();
        }
    }
}
