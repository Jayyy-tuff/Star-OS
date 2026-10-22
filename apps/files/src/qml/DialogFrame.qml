// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// Modal frame for the Files dialogs: covers the window so that nothing behind
// takes the pointer, draws a glass panel with the title and stacks the
// content below it. Escape asks to close. Each dialog keeps Tab inside itself
// with KeyNavigation.
FocusScope {
    id: frame

    property string title: ""
    // The window size, for the glass panel's wallpaper position.
    property size screenSize: Qt.size(width, height)
    default property alias content: column.data

    signal escapePressed()

    visible: false
    z: 10

    Accessible.role: Accessible.Dialog
    Accessible.name: frame.title

    Keys.onEscapePressed: event => {
        frame.escapePressed();
        event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.35
    }

    GlassSurface {
        id: panel
        anchors.centerIn: parent
        width: Math.min(frame.width - 4 * Theme.spacing, 30 * Theme.gridUnit)
        height: column.implicitHeight + 4 * Theme.spacing
        wallpaperOrigin: Qt.point(panel.x, panel.y)
        screenSize: frame.screenSize
    }

    Column {
        id: column
        anchors.centerIn: panel
        width: panel.width - 4 * Theme.spacing
        spacing: Theme.spacing

        Text {
            width: parent.width
            text: frame.title
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.pixelSize: Math.round(Theme.metrics.height * 1.25)
            font.bold: true
            wrapMode: Text.Wrap
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }
    }
}
