// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import org.kde.plasma.plasmoid
import StarOS.Shell
import StarOS.System

// Star OS desktop containment: draws the Star OS wallpaper and the sticky
// notes (StarOS.System's NotesStore, M0.4). libplasma's colour wallpaper
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

    // Above the taskbar, which the panel draws over the desktop's bottom edge.
    NotesBoard {
        anchors.fill: parent
        anchors.bottomMargin: Theme.taskbarHeight
        notes: NotesStore
        boardOrigin: Qt.point(0, 0)
        screenSize: Qt.size(root.width, root.height)
        onCountChanged: console.info("STAROS-SHELL notes=" + count)
    }
}
