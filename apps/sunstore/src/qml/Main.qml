// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// The Sun Store window. The title is also its accessible name.
Window {
    id: window

    width: 1100
    height: 720
    minimumWidth: 760
    minimumHeight: 460
    visible: true
    title: qsTr("Sun Store")
    color: Theme.glassFallback

    Store {
        id: backend
    }

    StoreView {
        anchors.fill: parent
        focus: true
        store: backend
        onCloseRequested: window.close()
    }

    Component.onCompleted: backend.start()
}
