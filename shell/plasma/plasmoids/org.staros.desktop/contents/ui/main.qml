// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import org.kde.plasma.plasmoid
import StarOS.Shell
import StarOS.System

// Star OS desktop containment: draws the Star OS wallpaper, the sticky
// notes (StarOS.System's NotesStore, M0.4) and the widgets (M0.5: Clock,
// Weather, System and Calendar, saved by WidgetStore). libplasma's colour wallpaper
// (org.kde.color in Theme.desktop, set by layout.js) shows until the SVG is
// rendered. Glass surfaces lay out the same image at screen size, so they line
// up with this one. No icons, no context menu, no toolbox.
ContainmentItem {
    id: root

    Image {
        anchors.fill: parent
        source: Theme.wallpaper
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        Accessible.ignored: true
    }

    SystemStatus {
        id: systemStatus
    }

    WidgetStore {
        id: widgetStore
    }

    // Above the taskbar, which the panel draws over the desktop's bottom edge.
    NotesBoard {
        id: notesBoard
        anchors.fill: parent
        anchors.bottomMargin: Theme.taskbarHeight
        notes: NotesStore
        boardOrigin: Qt.point(0, 0)
        screenSize: Qt.size(root.width, root.height)
        onCountChanged: console.info("STAROS-SHELL notes=" + count)
    }

    DesktopWidgets {
        anchors.fill: parent
        anchors.bottomMargin: Theme.taskbarHeight
        store: widgetStore
        status: systemStatus
        toolbarRight: 2 * Theme.spacing + notesBoard.toolbarWidth
        screenSize: Qt.size(root.width, root.height)
        Component.onCompleted: console.info("STAROS-SHELL widgets=" + widgetStore.filePath)
    }
}
