// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import "quickanswers.js" as QuickAnswers

// Full-screen launcher content: search field and application grid.
//
// The catalogue is any object with: model (rows with the roles 'AppName',
// 'GenericName', 'AppId', 'display' and optionally 'decoration'), count, a
// writable string 'filter', and launch(row) returning true when the launch was
// requested. The host decides where the catalogue comes from (Plasma adapter,
// or FakeCatalogue in tests). The launcher covers the whole screen, so its
// glass starts at (0, 0).
//
// The search field also answers sums, percentages and unit conversions
// (quickanswers.js; Return copies the answer) and makes sticky notes from text
// that starts with "note:" (Return emits noteRequested).
FocusScope {
    id: root

    required property var catalogue
    // Shows an app's own icon when Star OS has no artwork for it (AppIcon).
    property Component iconFallback: null

    readonly property var answer: QuickAnswers.evaluate(searchField.text)
    readonly property string noteText: {
        const match = searchField.text.match(/^\s*note:\s*(.*)$/i);
        return match ? match[1].trim() : "";
    }
    readonly property bool isNote: /^\s*note:/i.test(searchField.text)
    readonly property string answerText: root.answer ? root.answer.text : ""

    signal closeRequested()
    signal answerCopied(string text)
    signal noteRequested(string text)

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Application launcher")

    // Called by the host every time the launcher is shown.
    function reset() {
        searchField.text = "";
        if (root.catalogue) {
            root.catalogue.filter = "";
        }
        grid.currentIndex = 0;
        searchField.forceActiveFocus(Qt.OtherFocusReason);
    }

    // Return in the search field: a note, an answer, or the first app.
    function accept() {
        if (root.isNote) {
            if (root.noteText !== "") {
                root.noteRequested(root.noteText);
                root.closeRequested();
            }
            return;
        }
        if (root.answer) {
            clipboard.text = root.answer.text;
            clipboard.selectAll();
            clipboard.copy();
            root.answerCopied(root.answer.text);
            root.closeRequested();
            return;
        }
        root.launchRow(0);
    }

    function launchRow(row) {
        if (!root.catalogue || row < 0 || row >= root.catalogue.count) {
            return false;
        }
        if (root.catalogue.launch(row)) {
            root.closeRequested();
            return true;
        }
        return false;
    }

    function isPrintable(event) {
        const blocked = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
        return event.text.length > 0 && event.text.charCodeAt(0) >= 0x20
            && event.text.charCodeAt(0) !== 0x7f && (event.modifiers & blocked) === 0;
    }

    GlassSurface {
        objectName: "glass"
        anchors.fill: parent
        radius: 0
        wallpaperOrigin: Qt.point(0, 0)
        screenSize: Qt.size(root.width, root.height)
    }

    T.TextField {
        id: searchField
        objectName: "searchField"
        anchors.top: parent.top
        anchors.topMargin: Theme.launcherMargin
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(root.width - 2 * Theme.launcherMargin, Theme.searchMaxWidth)
        height: Theme.searchHeight
        focus: true
        leftPadding: Theme.spacing
        rightPadding: Theme.spacing
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        font: Theme.metrics.font
        placeholderText: qsTr("Search applications")
        placeholderTextColor: Theme.placeholder
        selectByMouse: true

        Accessible.name: qsTr("Search applications")
        Accessible.description: root.answer ? qsTr("Answer: %1. Press Return to copy it.").arg(root.answerText)
                                            : root.isNote ? qsTr("Press Return to put this on a sticky note.")
                                                          : ""

        background: Rectangle {
            radius: Theme.controlRadius
            color: Theme.searchField
            border.width: 1
            border.color: Theme.searchBorder
        }

        onTextChanged: {
            if (root.catalogue) {
                root.catalogue.filter = text;
            }
            grid.currentIndex = 0;
        }

        Keys.onDownPressed: event => {
            if (grid.count > 0) {
                grid.forceActiveFocus(Qt.TabFocusReason);
            }
            event.accepted = true;
        }
        Keys.onTabPressed: event => {
            if (grid.count > 0) {
                grid.forceActiveFocus(Qt.TabFocusReason);
            }
            event.accepted = true;
        }
        Keys.onReturnPressed: event => {
            root.accept();
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            root.accept();
            event.accepted = true;
        }
        Keys.onEscapePressed: event => {
            root.closeRequested();
            event.accepted = true;
        }

        FocusFrame {
            visible: searchField.activeFocus
            radius: Theme.controlRadius
        }
    }

    // Copies answers to the clipboard; never shown.
    TextInput {
        id: clipboard
        visible: false
        Accessible.ignored: true
    }

    // The answer or the note to be, between the search field and the grid.
    Rectangle {
        id: answerCard
        objectName: "answerCard"
        anchors.top: searchField.bottom
        anchors.topMargin: Theme.spacing
        anchors.horizontalCenter: parent.horizontalCenter
        width: searchField.width
        height: visible ? answerLabel.implicitHeight + 2 * Theme.spacing : 0
        visible: root.answer !== null || root.isNote
        radius: Theme.controlRadius
        color: Theme.tileGlass

        Text {
            id: answerLabel
            objectName: "answerLabel"
            anchors.fill: parent
            anchors.margins: Theme.spacing
            text: root.answer ? "= " + root.answerText
                              : root.noteText !== "" ? qsTr("New sticky note: %1").arg(root.noteText)
                                                     : qsTr("Type the note after “note:”")
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.pixelSize: Math.round(Theme.metrics.height * (root.answer ? 1.5 : 1))
            font.bold: root.answer !== null
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            Accessible.role: Accessible.StaticText
            Accessible.name: root.answer ? qsTr("Answer: %1").arg(root.answerText) : text
        }
    }

    Text {
        objectName: "emptyState"
        anchors.top: answerCard.bottom
        anchors.topMargin: Theme.launcherMargin
        anchors.horizontalCenter: parent.horizontalCenter
        visible: grid.count === 0 && !answerCard.visible
        text: qsTr("No applications match")
        color: Theme.text
        font: Theme.metrics.font
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    GridView {
        id: grid
        objectName: "appGrid"
        anchors.top: answerCard.visible ? answerCard.bottom : searchField.bottom
        anchors.topMargin: Theme.launcherMargin
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.launcherMargin
        anchors.rightMargin: Theme.launcherMargin
        anchors.bottomMargin: Theme.launcherMargin
        cellWidth: Theme.tileWidth + Theme.spacing
        cellHeight: Theme.tileHeight + Theme.spacing
        clip: true
        model: root.catalogue ? root.catalogue.model : null
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        activeFocusOnTab: count > 0
        boundsBehavior: Flickable.StopAtBounds

        readonly property int columns: Math.max(1, Math.floor(width / cellWidth))

        Accessible.role: Accessible.List
        Accessible.name: qsTr("Applications")

        delegate: LauncherTile {
            id: tile

            required property var model
            required property int index

            width: Theme.tileWidth
            height: Theme.tileHeight
            appName: tile.model.AppName ?? (tile.model.display ?? "")
            genericName: tile.model.GenericName ?? ""
            appId: tile.model.AppId ?? ""
            iconData: tile.model.decoration
            iconFallback: root.iconFallback
            onClicked: {
                grid.currentIndex = tile.index;
                root.launchRow(tile.index);
            }
        }

        Keys.onUpPressed: event => {
            if (currentIndex < columns) {
                searchField.forceActiveFocus(Qt.BacktabFocusReason);
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }
        Keys.onEscapePressed: event => {
            root.closeRequested();
            event.accepted = true;
        }
        // Typing anywhere in the grid continues the search.
        Keys.onPressed: event => {
            if (root.isPrintable(event)) {
                searchField.text += event.text;
                searchField.forceActiveFocus(Qt.OtherFocusReason);
                event.accepted = true;
            }
        }
    }
}
