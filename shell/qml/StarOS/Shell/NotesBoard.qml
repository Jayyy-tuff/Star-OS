// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick

// Sticky notes on the desktop. `notes` is a list model with the roles noteId,
// noteText, posX and posY, and the functions add(text) (returns the new id),
// update(id, text), move(id, posX, posY) and remove(id): StarOS.System's
// NotesStore in the session, a fake in tests. A "New note" button sits at the
// top right.
Item {
    id: board

    required property var notes
    // The board's top-left in screen coordinates and the screen size, for the
    // glass.
    property point boardOrigin: Qt.point(0, 0)
    property size screenSize: Qt.size(board.width, board.height)

    readonly property int count: notesRepeater.count

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Sticky notes")

    function noteItem(noteId) {
        for (let i = 0; i < notesRepeater.count; ++i) {
            const item = notesRepeater.itemAt(i);
            if (item && item.noteId === noteId) {
                return item;
            }
        }
        return null;
    }

    // New notes cascade from the top left.
    function addNote(text) {
        const offset = (notesRepeater.count % 8) * 0.04;
        const noteId = board.notes.add(text);
        board.notes.move(noteId, 0.04 + offset, 0.06 + offset);
        Qt.callLater(() => {
            const item = board.noteItem(noteId);
            if (item) {
                item.focusText();
            }
        });
        return noteId;
    }

    GlassSurface {
        anchors.fill: newNoteButton
        radius: Theme.controlRadius
        wallpaperOrigin: Qt.point(board.boardOrigin.x + newNoteButton.x, board.boardOrigin.y + newNoteButton.y)
        screenSize: board.screenSize
    }

    ShellButton {
        id: newNoteButton
        objectName: "newNoteButton"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Theme.spacing
        height: Theme.minTarget
        text: qsTr("New note")
        description: qsTr("Put a new sticky note on the desktop")
        onClicked: board.addNote("")
    }

    // Notes live below the button row.
    Item {
        id: area
        objectName: "notesArea"
        anchors.top: newNoteButton.bottom
        anchors.topMargin: Theme.spacing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Repeater {
            id: notesRepeater
            model: board.notes

            delegate: StickyNote {
                boardSize: Qt.size(area.width, area.height)
                boardOrigin: Qt.point(board.boardOrigin.x + area.x, board.boardOrigin.y + area.y)
                screenSize: board.screenSize
                onTextEdited: (noteId, text) => board.notes.update(noteId, text)
                onMoved: (noteId, posX, posY) => board.notes.move(noteId, posX, posY)
                onDeleteRequested: noteId => board.notes.remove(noteId)
            }
        }
    }
}
