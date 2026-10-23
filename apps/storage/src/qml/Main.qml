// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell
import StarOS.System

// The Star Storage window; its title is also its accessible name.
Window {
    id: window

    width: 820
    height: 680
    minimumWidth: 480
    minimumHeight: 400
    visible: true
    title: qsTr("Star Storage")
    color: Theme.glassFallback

    SystemStatus {
        id: systemStatus
    }

    StorageBackend {
        id: storageBackend
    }

    StorageView {
        anchors.fill: parent
        focus: true
        backend: storageBackend
        status: systemStatus
    }

    Component.onCompleted: storageBackend.refresh()
}
