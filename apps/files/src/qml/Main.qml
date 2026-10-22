// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// The Files window. main.cpp sets initialUrl from the command line; empty
// means the home folder. The window title ("Files — <folder>") is also its
// accessible name.
Window {
    id: window

    property url initialUrl

    width: 1100
    height: 700
    minimumWidth: 820
    minimumHeight: 420
    visible: true
    title: view.title
    color: Theme.glassFallback

    FolderModel {
        id: currentFolder
    }

    PlacesModel {
        id: placeList
    }

    FileOperations {
        id: fileOperations
    }

    FilesView {
        id: view
        anchors.fill: parent
        focus: true
        folderModel: currentFolder
        places: placeList
        operations: fileOperations
    }

    Component.onCompleted: {
        currentFolder.url = String(window.initialUrl) !== "" ? window.initialUrl : placeList.homeUrl;
    }
}
