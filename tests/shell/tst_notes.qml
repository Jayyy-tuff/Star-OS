// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// NotesBoard and StickyNote with a fake notes model: adding, editing (saved
// after a pause and when leaving the note), moving by position, deleting,
// keyboard focus and accessible names.
Item {
    id: root

    width: 1280
    height: 720

    ListModel {
        id: fakeNotes

        property int nextId: 1
        property var calls: []

        function record(call) {
            fakeNotes.calls = fakeNotes.calls.concat([call]);
        }
        function indexOf(noteId) {
            for (let i = 0; i < fakeNotes.count; ++i) {
                if (fakeNotes.get(i).noteId === noteId) {
                    return i;
                }
            }
            return -1;
        }
        function add(text) {
            const noteId = "n" + fakeNotes.nextId;
            fakeNotes.nextId += 1;
            fakeNotes.append({noteId: noteId, noteText: text, posX: 0, posY: 0});
            fakeNotes.record("add:" + text);
            return noteId;
        }
        function update(noteId, text) {
            fakeNotes.setProperty(fakeNotes.indexOf(noteId), "noteText", text);
            fakeNotes.record("update:" + noteId + ":" + text);
        }
        function move(noteId, posX, posY) {
            const row = fakeNotes.indexOf(noteId);
            fakeNotes.setProperty(row, "posX", posX);
            fakeNotes.setProperty(row, "posY", posY);
            fakeNotes.record("move:" + noteId);
        }
        function remove(noteId) {
            fakeNotes.remove(fakeNotes.indexOf(noteId));
            fakeNotes.record("remove:" + noteId);
        }
    }

    NotesBoard {
        id: board
        anchors.fill: parent
        notes: fakeNotes
    }

    TestCase {
        name: "Notes"
        when: windowShown

        function init() {
            fakeNotes.clear();
            fakeNotes.calls = [];
            board.forceActiveFocus();
        }

        function noteAt(row) {
            const area = findChild(board, "notesArea");
            for (const child of area.children) {
                if (child.noteId === fakeNotes.get(row).noteId) {
                    return child;
                }
            }
            return null;
        }

        function test_accessible_names() {
            compare(board.Accessible.role, Accessible.Pane);
            compare(board.Accessible.name, "Sticky notes");
            const button = findChild(board, "newNoteButton");
            compare(button.Accessible.role, Accessible.Button);
            compare(button.Accessible.name, "New note");
        }

        function test_new_note_gets_focus() {
            mouseClick(findChild(board, "newNoteButton"));
            compare(fakeNotes.count, 1);
            compare(fakeNotes.calls, ["add:", "move:n1"]);
            tryVerify(() => noteAt(0) !== null, 5000, "the note is shown");
            const note = noteAt(0);
            const editor = findChild(note, "editor");
            tryVerify(() => editor.activeFocus, 5000, "the new note has focus");
            compare(editor.Accessible.name, "Sticky note");
            compare(findChild(note, "deleteButton").Accessible.name, "Delete note");
        }

        function test_typing_is_saved() {
            fakeNotes.add("");
            tryVerify(() => noteAt(0) !== null, 5000);
            const editor = findChild(noteAt(0), "editor");
            editor.forceActiveFocus();
            keyClick("h");
            keyClick("i");
            compare(editor.text, "hi");
            tryVerify(() => fakeNotes.calls.indexOf("update:n1:hi") >= 0, 5000, "saved after a pause");
            compare(editor.Accessible.description, "hi");
        }

        function test_leaving_saves_at_once() {
            fakeNotes.add("old");
            tryVerify(() => noteAt(0) !== null, 5000);
            const editor = findChild(noteAt(0), "editor");
            editor.forceActiveFocus();
            keyClick(Qt.Key_End);
            keyClick("!");
            keyClick(Qt.Key_Escape);
            verify(!editor.activeFocus);
            compare(fakeNotes.calls[fakeNotes.calls.length - 1], "update:n1:old!");
        }

        function test_position_follows_the_model() {
            fakeNotes.add("a");
            tryVerify(() => noteAt(0) !== null, 5000);
            const note = noteAt(0);
            const area = findChild(board, "notesArea");
            fakeNotes.move("n1", 1, 0.5);
            compare(note.x, Math.round(area.width - note.width));
            compare(note.y, Math.round(0.5 * (area.height - note.height)));
            // Out-of-range positions stay on the board.
            fakeNotes.move("n1", 2, -1);
            compare(note.x, Math.round(area.width - note.width));
            compare(note.y, 0);
        }

        function test_delete() {
            fakeNotes.add("a");
            fakeNotes.add("b");
            tryVerify(() => noteAt(1) !== null, 5000);
            mouseClick(findChild(noteAt(0), "deleteButton"));
            compare(fakeNotes.count, 1);
            compare(fakeNotes.get(0).noteText, "b");
            compare(fakeNotes.calls[fakeNotes.calls.length - 1], "remove:n1");
        }

        function test_tab_moves_between_notes() {
            fakeNotes.add("a");
            fakeNotes.add("b");
            tryVerify(() => noteAt(1) !== null, 5000);
            const first = findChild(noteAt(0), "editor");
            first.forceActiveFocus();
            keyClick(Qt.Key_Tab);
            verify(!first.activeFocus, "Tab leaves the first note");
        }
    }
}
