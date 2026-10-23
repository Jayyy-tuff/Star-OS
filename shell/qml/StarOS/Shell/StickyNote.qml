// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

// One sticky note on the desktop: a glass card with a strip to drag it by, the
// editable text and a Delete button. The board positions it from posX and
// posY (fractions of the free space) and saves what changes.
FocusScope {
    id: note

    required property string noteId
    required property string noteText
    required property real posX
    required property real posY
    // The board's size and its top-left in screen coordinates, for placement
    // and for the glass.
    property size boardSize: Qt.size(0, 0)
    property point boardOrigin: Qt.point(0, 0)
    property size screenSize: Qt.size(0, 0)

    signal textEdited(string noteId, string text)
    signal moved(string noteId, real posX, real posY)
    signal deleteRequested(string noteId)

    readonly property real freeWidth: Math.max(0, note.boardSize.width - note.width)
    readonly property real freeHeight: Math.max(0, note.boardSize.height - note.height)

    width: 14 * Theme.gridUnit
    height: 10 * Theme.gridUnit
    x: Math.round(Math.min(1, Math.max(0, note.posX)) * note.freeWidth)
    y: Math.round(Math.min(1, Math.max(0, note.posY)) * note.freeHeight)

    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Sticky note")

    function save() {
        saveTimer.stop();
        if (editor.text !== note.noteText) {
            note.textEdited(note.noteId, editor.text);
        }
    }

    function focusText() {
        editor.forceActiveFocus(Qt.OtherFocusReason);
        editor.cursorPosition = editor.length;
    }

    GlassSurface {
        anchors.fill: parent
        radius: Theme.controlRadius
        wallpaperOrigin: Qt.point(note.boardOrigin.x + note.x, note.boardOrigin.y + note.y)
        screenSize: note.screenSize
    }

    // The strip at the top: drag here to move the note.
    Rectangle {
        id: strip
        objectName: "dragStrip"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Theme.minTarget
        radius: Theme.controlRadius
        color: Theme.glassButtonActive

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.activeIndicatorHeight
            color: Theme.activeIndicator
        }

        MouseArea {
            anchors.fill: parent
            anchors.rightMargin: deleteButton.width + Theme.spacing
            cursorShape: Qt.SizeAllCursor
            drag.target: note
            drag.axis: Drag.XAndYAxis
            drag.minimumX: 0
            drag.minimumY: 0
            drag.maximumX: note.freeWidth
            drag.maximumY: note.freeHeight
            onReleased: {
                note.moved(note.noteId, note.freeWidth > 0 ? note.x / note.freeWidth : 0,
                           note.freeHeight > 0 ? note.y / note.freeHeight : 0);
                // Dragging replaced the position bindings; follow the model again.
                note.x = Qt.binding(() => Math.round(Math.min(1, Math.max(0, note.posX)) * note.freeWidth));
                note.y = Qt.binding(() => Math.round(Math.min(1, Math.max(0, note.posY)) * note.freeHeight));
            }
        }

        ShellButton {
            id: deleteButton
            objectName: "deleteButton"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            text: qsTr("Delete")
            description: qsTr("Delete this sticky note")
            Accessible.name: qsTr("Delete note")
            onClicked: note.deleteRequested(note.noteId)
        }
    }

    T.TextArea {
        id: editor
        objectName: "editor"
        anchors.top: strip.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        padding: Theme.spacing
        focus: true
        text: note.noteText
        color: Theme.text
        font: Theme.metrics.font
        wrapMode: TextEdit.Wrap
        placeholderText: qsTr("Write a note")
        placeholderTextColor: Theme.placeholder
        selectByMouse: true
        activeFocusOnTab: true

        Accessible.name: qsTr("Sticky note")
        Accessible.description: editor.text

        onTextChanged: {
            if (editor.activeFocus) {
                saveTimer.restart();
            }
        }
        onActiveFocusChanged: {
            if (!activeFocus) {
                note.save();
            }
        }
        // Tab moves to the next control instead of typing a tab.
        Keys.onTabPressed: event => {
            const next = editor.nextItemInFocusChain(true);
            if (next) {
                next.forceActiveFocus(Qt.TabFocusReason);
            }
            event.accepted = true;
        }
        Keys.onBacktabPressed: event => {
            const previous = editor.nextItemInFocusChain(false);
            if (previous) {
                previous.forceActiveFocus(Qt.BacktabFocusReason);
            }
            event.accepted = true;
        }
        Keys.onEscapePressed: event => {
            note.save();
            editor.focus = false;
            event.accepted = true;
        }

        FocusFrame {
            visible: editor.activeFocus
            radius: Theme.controlRadius
        }
    }

    // Saves while typing, half a second after the last key.
    Timer {
        id: saveTimer
        interval: 500
        onTriggered: note.save()
    }
}
