// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell
import StarOS.System

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

    // "starpicks", or a category given on the command line (--category).
    property string initialCategory: "starpicks"

    Store {
        id: backend
    }

    SystemStatus {
        id: systemStatus
    }

    StoreView {
        anchors.fill: parent
        focus: true
        store: backend
        status: systemStatus
        onCloseRequested: window.close()
        onStorageRequested: backend.openStarStorage()
    }

    // Discover opens on Star picks unless asked for a category.
    Component.onCompleted: {
        backend.apps.category = window.initialCategory;
        backend.start();
    }
}
