// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

// Full-screen launcher content: search field and application grid.
//
// The catalogue is any object with: model (rows with the roles 'AppName',
// 'GenericName', 'display'), count, a writable string 'filter', and
// launch(row) returning true when the launch was requested. The host decides
// where the catalogue comes from (Plasma adapter, or FakeCatalogue in tests).
FocusScope {
    id: root

    required property var catalogue

    signal closeRequested()

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

    Rectangle {
        anchors.fill: parent
        color: Theme.launcherBackdrop
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

        background: Rectangle {
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
            root.launchRow(0);
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            root.launchRow(0);
            event.accepted = true;
        }
        Keys.onEscapePressed: event => {
            root.closeRequested();
            event.accepted = true;
        }

        FocusFrame {
            visible: searchField.activeFocus
        }
    }

    Text {
        objectName: "emptyState"
        anchors.top: searchField.bottom
        anchors.topMargin: Theme.launcherMargin
        anchors.horizontalCenter: parent.horizontalCenter
        visible: grid.count === 0
        text: qsTr("No applications match")
        color: Theme.text
        font: Theme.metrics.font
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    GridView {
        id: grid
        objectName: "appGrid"
        anchors.top: searchField.bottom
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
