// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import StarOS.Shell

// The Files window content: tool bar, places, folder contents, status line and
// dialogs, all on frosted glass. It only talks to the three objects below, so
// tests pass doubles:
//   folderModel  FolderModel: rows with the roles name, url, isDir and
//                accessibleDescription; url (writable), location, parentUrl,
//                isTrash, nameFilter, showHidden, count, loading, errorString;
//                refresh(), indexOfUrl(url), urlFromLocation(text).
//   places       PlacesModel: rows with name and url; indexOfUrl(url),
//                nameForUrl(url).
//   operations   FileOperations: the operations, nameError(name), busy,
//                progress, statusText, and the signals finished(operation,
//                urls) and failed(operation, message).
// URLs kept here (history, selection) are strings: a url value read from a
// property can be a live reference to that property.
FocusScope {
    id: root

    required property var folderModel
    required property var places
    required property var operations

    readonly property string folderName: root.places.nameForUrl(root.folderModel.url)
    readonly property string title: qsTr("Files — %1").arg(root.folderName)
    readonly property bool dialogOpen: nameDialog.visible || confirmDialog.visible
    readonly property bool canGoBack: root.backStack.length > 0
    readonly property bool canGoForward: root.forwardStack.length > 0
    readonly property bool canGoUp: String(root.folderModel.parentUrl) !== ""
    readonly property size windowSize: Qt.size(root.width, root.height)
    readonly property int margin: Theme.spacing

    property var backStack: []
    property var forwardStack: []
    // Shown in the status line until the next folder or action.
    property string message: ""
    property bool messageIsError: false
    // The item to make current once it is listed (string URL).
    property string pendingSelection: ""
    // What the open dialog acts on.
    property string dialogAction: ""
    property var dialogUrl: null

    readonly property string emptyText: {
        if (root.folderModel.errorString !== "") {
            return root.folderModel.errorString;
        }
        if (root.folderModel.loading) {
            return qsTr("Loading…");
        }
        if (root.folderModel.nameFilter !== "") {
            return qsTr("No items match “%1”.").arg(root.folderModel.nameFilter);
        }
        return root.folderModel.isTrash ? qsTr("The Trash is empty.") : qsTr("This folder is empty.");
    }

    readonly property string statusLine: {
        if (root.operations.busy) {
            const percent = root.operations.progress;
            return percent >= 0 ? qsTr("%1 %2%").arg(root.operations.statusText).arg(percent)
                                : root.operations.statusText;
        }
        if (root.folderModel.loading) {
            return qsTr("Loading…");
        }
        return root.folderModel.count === 1 ? qsTr("1 item") : qsTr("%1 items").arg(root.folderModel.count);
    }

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Files")

    function sameUrl(a, b) {
        return String(a) === String(b);
    }

    function showMessage(text, isError) {
        root.message = text;
        root.messageIsError = isError;
        messageLabel.Accessible.announce(text);
    }

    function clearMessage() {
        if (dismissButton.activeFocus) {
            contents.forceActiveFocus(Qt.OtherFocusReason);
        }
        root.message = "";
        root.messageIsError = false;
    }

    // Shows `url` without touching the history; `select` is the item to make
    // current afterwards (the folder we came from, when going up or back).
    function showFolder(url, select) {
        root.clearMessage();
        root.pendingSelection = select ? String(select) : "";
        filterField.text = "";
        root.folderModel.url = url;
    }

    function navigate(url, select) {
        if (String(url) === "" || root.sameUrl(url, root.folderModel.url)) {
            return;
        }
        root.backStack = root.backStack.concat([String(root.folderModel.url)]);
        root.forwardStack = [];
        root.showFolder(url, select);
    }

    function goBack() {
        if (!root.canGoBack) {
            return;
        }
        const from = String(root.folderModel.url);
        const target = root.backStack[root.backStack.length - 1];
        root.backStack = root.backStack.slice(0, -1);
        root.forwardStack = root.forwardStack.concat([from]);
        root.showFolder(target, from);
    }

    function goForward() {
        if (!root.canGoForward) {
            return;
        }
        const from = String(root.folderModel.url);
        const target = root.forwardStack[root.forwardStack.length - 1];
        root.forwardStack = root.forwardStack.slice(0, -1);
        root.backStack = root.backStack.concat([from]);
        root.showFolder(target, "");
    }

    function goUp() {
        if (root.canGoUp) {
            root.navigate(root.folderModel.parentUrl, root.folderModel.url);
        }
    }

    function applySelection() {
        if (root.pendingSelection !== "") {
            const row = root.folderModel.indexOfUrl(root.pendingSelection);
            if (row >= 0) {
                contents.currentIndex = row;
                contents.positionViewAtIndex(row, ListView.Contain);
                root.pendingSelection = "";
                return;
            }
        }
        if (contents.count > 0 && contents.currentIndex < 0) {
            contents.currentIndex = 0;
        }
    }

    function syncLocation() {
        locationField.text = root.folderModel.location;
    }

    function openLocation() {
        const url = root.folderModel.urlFromLocation(locationField.text);
        if (String(url) === "") {
            root.showMessage(qsTr("“%1” is not a folder Files can show.").arg(locationField.text), true);
            return;
        }
        root.navigate(url);
        contents.forceActiveFocus(Qt.OtherFocusReason);
    }

    function openPlace() {
        if (placesList.currentItem) {
            root.navigate(placesList.currentItem.url);
        }
    }

    // Return or a double click on an item: folders open in place, files in
    // their application (FileOperations refuses programs).
    function activate(item) {
        if (!item) {
            return;
        }
        if (item.isDir) {
            root.navigate(item.url);
        } else {
            root.operations.open(item.url);
        }
    }

    function askRename() {
        const item = contents.currentItem;
        if (!item || root.folderModel.isTrash) {
            return;
        }
        root.dialogAction = "rename";
        root.dialogUrl = item.url;
        nameDialog.title = qsTr("Rename “%1”").arg(item.name);
        nameDialog.fieldName = qsTr("New name");
        nameDialog.acceptText = qsTr("Rename");
        const dot = item.isDir ? -1 : item.name.lastIndexOf(".");
        nameDialog.open(item.name, dot > 0 ? dot : -1);
    }

    function askNewFolder() {
        if (root.folderModel.isTrash) {
            root.showMessage(qsTr("Folders cannot be created in the Trash."), true);
            return;
        }
        root.dialogAction = "newFolder";
        nameDialog.title = qsTr("New folder");
        nameDialog.fieldName = qsTr("Folder name");
        nameDialog.acceptText = qsTr("Create");
        nameDialog.open(qsTr("New Folder"), -1);
    }

    function askDelete() {
        const item = contents.currentItem;
        if (!item) {
            return;
        }
        root.dialogAction = "delete";
        root.dialogUrl = item.url;
        confirmDialog.title = qsTr("Delete “%1” permanently?").arg(item.name);
        confirmDialog.message = qsTr("It will be deleted now, not moved to the Trash. This cannot be undone.");
        confirmDialog.confirmText = qsTr("Delete");
        confirmDialog.open();
    }

    function askEmptyTrash() {
        root.dialogAction = "emptyTrash";
        confirmDialog.title = qsTr("Empty the Trash?");
        confirmDialog.message = qsTr("Everything in the Trash will be deleted permanently. This cannot be undone.");
        confirmDialog.confirmText = qsTr("Empty Trash");
        confirmDialog.open();
    }

    function trashCurrent() {
        const item = contents.currentItem;
        if (item) {
            root.operations.moveToTrash([item.url]);
        }
    }

    function restoreCurrent() {
        const item = contents.currentItem;
        if (item && root.folderModel.isTrash) {
            root.operations.restoreFromTrash([item.url]);
        }
    }

    function copyCurrent(cut) {
        const item = contents.currentItem;
        if (!item) {
            return;
        }
        if (cut) {
            root.operations.cutToClipboard([item.url]);
            root.showMessage(qsTr("Cut “%1”. Paste it in another folder to move it.").arg(item.name), false);
        } else {
            root.operations.copyToClipboard([item.url]);
            root.showMessage(qsTr("Copied “%1”.").arg(item.name), false);
        }
    }

    function pasteHere() {
        if (root.folderModel.isTrash) {
            root.showMessage(qsTr("Items cannot be pasted into the Trash."), true);
            return;
        }
        root.operations.paste(root.folderModel.url);
    }

    function handleContentKey(event) {
        const modifiers = event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        const key = event.key;
        if ((key === Qt.Key_Return || key === Qt.Key_Enter) && modifiers === 0) {
            root.activate(contents.currentItem);
        } else if (key === Qt.Key_Backspace && modifiers === 0) {
            root.goUp();
        } else if (key === Qt.Key_Home && modifiers === 0 && contents.count > 0) {
            contents.currentIndex = 0;
        } else if (key === Qt.Key_End && modifiers === 0 && contents.count > 0) {
            contents.currentIndex = contents.count - 1;
        } else if (key === Qt.Key_F2 && modifiers === 0) {
            root.askRename();
        } else if (key === Qt.Key_Delete && modifiers === Qt.ShiftModifier) {
            root.askDelete();
        } else if (key === Qt.Key_Delete && modifiers === 0) {
            // Items in the Trash can only be deleted for good.
            if (root.folderModel.isTrash) {
                root.askDelete();
            } else {
                root.trashCurrent();
            }
        } else if (key === Qt.Key_C && modifiers === Qt.ControlModifier) {
            root.copyCurrent(false);
        } else if (key === Qt.Key_X && modifiers === Qt.ControlModifier) {
            root.copyCurrent(true);
        } else if (key === Qt.Key_V && modifiers === Qt.ControlModifier) {
            root.pasteHere();
        } else {
            return;
        }
        event.accepted = true;
    }

    Connections {
        target: root.folderModel

        function onUrlChanged() {
            root.syncLocation();
            placesList.currentIndex = root.places.indexOfUrl(root.folderModel.url);
        }

        // The view applies model changes when it is polished, so the current
        // item is chosen afterwards.
        function onCountChanged() {
            Qt.callLater(root.applySelection);
        }

        function onLoadingChanged() {
            if (!root.folderModel.loading) {
                Qt.callLater(root.applySelection);
            }
        }
    }

    Connections {
        target: root.operations

        function onFinished(operation, urls) {
            if (operation === "open") {
                return;
            }
            if (operation !== "trash" && urls && urls.length > 0) {
                root.pendingSelection = String(urls[0]);
            }
            root.folderModel.refresh();
        }

        function onFailed(operation, message) {
            root.showMessage(message, true);
        }
    }

    Shortcut {
        sequence: "Alt+Left"
        enabled: !root.dialogOpen
        onActivated: root.goBack()
    }
    Shortcut {
        sequence: "Alt+Right"
        enabled: !root.dialogOpen
        onActivated: root.goForward()
    }
    Shortcut {
        sequence: "Alt+Up"
        enabled: !root.dialogOpen
        onActivated: root.goUp()
    }
    Shortcut {
        sequence: "Ctrl+L"
        enabled: !root.dialogOpen
        onActivated: {
            locationField.forceActiveFocus(Qt.ShortcutFocusReason);
            locationField.selectAll();
        }
    }
    Shortcut {
        sequence: "Ctrl+F"
        enabled: !root.dialogOpen
        onActivated: {
            filterField.forceActiveFocus(Qt.ShortcutFocusReason);
            filterField.selectAll();
        }
    }
    Shortcut {
        sequence: "Ctrl+H"
        enabled: !root.dialogOpen
        onActivated: root.folderModel.showHidden = !root.folderModel.showHidden
    }
    Shortcut {
        sequence: "Ctrl+Shift+N"
        enabled: !root.dialogOpen
        onActivated: root.askNewFolder()
    }
    Shortcut {
        sequence: "F5"
        enabled: !root.dialogOpen
        onActivated: root.folderModel.refresh()
    }

    // The window background: the wallpaper, frosted.
    GlassSurface {
        anchors.fill: parent
        radius: 0
        wallpaperOrigin: Qt.point(0, 0)
        screenSize: root.windowSize
    }

    GlassSurface {
        id: toolbarGlass
        x: root.margin
        y: root.margin
        width: root.width - 2 * root.margin
        height: Theme.minTarget + root.margin
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    Item {
        id: toolbar
        objectName: "toolbar"
        anchors.fill: toolbarGlass
        anchors.margins: root.margin / 2

        Accessible.role: Accessible.ToolBar
        Accessible.name: qsTr("Files toolbar")

        FilesButton {
            id: backButton
            objectName: "backButton"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Back")
            description: qsTr("Go to the previous folder (Alt+Left)")
            enabled: root.canGoBack
            onClicked: root.goBack()
        }

        FilesButton {
            id: forwardButton
            objectName: "forwardButton"
            anchors.left: backButton.right
            anchors.leftMargin: root.margin / 2
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Forward")
            description: qsTr("Go to the next folder (Alt+Right)")
            enabled: root.canGoForward
            onClicked: root.goForward()
        }

        FilesButton {
            id: upButton
            objectName: "upButton"
            anchors.left: forwardButton.right
            anchors.leftMargin: root.margin / 2
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Up")
            description: qsTr("Go to the parent folder (Alt+Up)")
            enabled: root.canGoUp
            onClicked: root.goUp()
        }

        FilesTextField {
            id: locationField
            objectName: "locationField"
            anchors.left: upButton.right
            anchors.right: filterField.left
            anchors.leftMargin: root.margin
            anchors.rightMargin: root.margin
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: qsTr("Location")
            Accessible.name: qsTr("Location")
            Accessible.description: qsTr("Type a folder path and press Return (Ctrl+L)")
            Keys.onReturnPressed: event => {
                root.openLocation();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.openLocation();
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                root.syncLocation();
                contents.forceActiveFocus(Qt.OtherFocusReason);
                event.accepted = true;
            }
        }

        FilesTextField {
            id: filterField
            objectName: "filterField"
            anchors.right: actions.left
            anchors.rightMargin: root.margin
            anchors.verticalCenter: parent.verticalCenter
            width: 9 * Theme.gridUnit
            placeholderText: qsTr("Filter")
            Accessible.name: qsTr("Filter")
            Accessible.description: qsTr("Show only items whose name contains this text (Ctrl+F)")
            Accessible.searchEdit: true
            onTextChanged: root.folderModel.nameFilter = text
            Keys.onReturnPressed: event => {
                contents.forceActiveFocus(Qt.OtherFocusReason);
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                contents.forceActiveFocus(Qt.OtherFocusReason);
                event.accepted = true;
            }
            Keys.onDownPressed: event => {
                contents.forceActiveFocus(Qt.OtherFocusReason);
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                if (text !== "") {
                    text = "";
                } else {
                    contents.forceActiveFocus(Qt.OtherFocusReason);
                }
                event.accepted = true;
            }
        }

        Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.margin / 2

            FilesButton {
                id: hiddenButton
                objectName: "hiddenButton"
                toggle: true
                checked: root.folderModel.showHidden
                text: qsTr("Hidden files")
                Accessible.name: qsTr("Show hidden files")
                description: qsTr("Ctrl+H")
                onClicked: root.folderModel.showHidden = checked
            }

            FilesButton {
                id: newFolderButton
                objectName: "newFolderButton"
                visible: !root.folderModel.isTrash
                text: qsTr("New folder")
                description: qsTr("Ctrl+Shift+N")
                onClicked: root.askNewFolder()
            }

            FilesButton {
                id: restoreButton
                objectName: "restoreButton"
                visible: root.folderModel.isTrash
                enabled: contents.currentItem !== null
                text: qsTr("Restore")
                description: qsTr("Put the selected item back where it was")
                onClicked: root.restoreCurrent()
            }

            FilesButton {
                id: emptyTrashButton
                objectName: "emptyTrashButton"
                visible: root.folderModel.isTrash
                enabled: contents.count > 0
                text: qsTr("Empty Trash")
                description: qsTr("Delete everything in the Trash permanently")
                onClicked: root.askEmptyTrash()
            }
        }
    }

    GlassSurface {
        id: statusGlass
        x: root.margin
        y: root.height - height - root.margin
        width: root.width - 2 * root.margin
        height: Theme.minTarget
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    GlassSurface {
        id: sidebarGlass
        x: root.margin
        y: toolbarGlass.y + toolbarGlass.height + root.margin
        width: Math.round(Math.min(12 * Theme.gridUnit, root.width / 4))
        height: statusGlass.y - y - root.margin
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    ListView {
        id: placesList
        objectName: "places"
        anchors.fill: sidebarGlass
        anchors.margins: root.margin / 2
        model: root.places
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true

        Accessible.role: Accessible.List
        Accessible.name: qsTr("Places")

        delegate: PlaceRow {
            id: placeRow
            width: placesList.width
            onClicked: {
                placesList.currentIndex = placeRow.index;
                placesList.forceActiveFocus(Qt.MouseFocusReason);
                root.openPlace();
            }
        }

        Keys.onReturnPressed: event => {
            root.openPlace();
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            root.openPlace();
            event.accepted = true;
        }

        onActiveFocusChanged: {
            if (activeFocus && currentIndex < 0 && count > 0) {
                currentIndex = 0;
            }
        }
    }

    GlassSurface {
        id: contentGlass
        x: sidebarGlass.x + sidebarGlass.width + root.margin
        y: sidebarGlass.y
        width: root.width - x - root.margin
        height: sidebarGlass.height
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    ListView {
        id: contents
        objectName: "folderContents"
        anchors.fill: contentGlass
        anchors.margins: root.margin / 2
        focus: true
        model: root.folderModel
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true

        Accessible.role: Accessible.List
        Accessible.name: qsTr("Folder contents")
        Accessible.description: count === 0 ? root.emptyText : ""

        delegate: FileRow {
            id: fileRow
            width: contents.width
            onClicked: {
                contents.currentIndex = fileRow.index;
                contents.forceActiveFocus(Qt.MouseFocusReason);
            }
            onActivated: root.activate(fileRow)
        }

        Keys.onPressed: event => root.handleContentKey(event)
    }

    // An empty list has no item to carry the focus ring.
    FocusFrame {
        anchors.fill: contents
        visible: contents.activeFocus && contents.count === 0
    }

    Text {
        id: emptyState
        objectName: "emptyState"
        anchors.centerIn: contentGlass
        width: contentGlass.width - 4 * root.margin
        visible: contents.count === 0 || root.folderModel.errorString !== ""
        text: root.emptyText
        color: Theme.text
        font: Theme.metrics.font
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    Item {
        id: statusBar
        anchors.fill: statusGlass
        anchors.leftMargin: root.margin
        anchors.rightMargin: root.margin / 2

        Text {
            id: statusLabel
            objectName: "statusLabel"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width / 3)
            text: root.statusLine
            color: Theme.text
            font: Theme.metrics.font
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Rectangle {
            id: errorMark
            anchors.right: messageLabel.left
            anchors.rightMargin: root.margin / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.focusRingWidth
            height: Math.round(parent.height * 0.6)
            visible: root.message !== "" && root.messageIsError
            color: Theme.focusRing
        }

        Text {
            id: messageLabel
            objectName: "messageLabel"
            anchors.right: dismissButton.visible ? dismissButton.left : parent.right
            anchors.rightMargin: root.margin
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - statusLabel.width - dismissButton.width - 4 * root.margin)
            visible: root.message !== ""
            text: root.message
            color: Theme.text
            font: Theme.metrics.font
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        FilesButton {
            id: dismissButton
            objectName: "dismissButton"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height - root.margin / 2
            visible: root.message !== ""
            text: qsTr("Dismiss")
            description: qsTr("Hide this message")
            onClicked: root.clearMessage()
        }
    }

    NameDialog {
        id: nameDialog
        objectName: "nameDialog"
        anchors.fill: parent
        screenSize: root.windowSize
        validate: name => root.operations.nameError(name)
        onAccepted: name => {
            contents.forceActiveFocus(Qt.OtherFocusReason);
            if (root.dialogAction === "rename") {
                root.operations.rename(root.dialogUrl, name);
            } else {
                root.operations.createFolder(root.folderModel.url, name);
            }
        }
        onRejected: contents.forceActiveFocus(Qt.OtherFocusReason)
    }

    ConfirmDialog {
        id: confirmDialog
        objectName: "confirmDialog"
        anchors.fill: parent
        screenSize: root.windowSize
        onConfirmed: {
            contents.forceActiveFocus(Qt.OtherFocusReason);
            if (root.dialogAction === "delete") {
                root.operations.deletePermanently([root.dialogUrl]);
            } else if (root.dialogAction === "emptyTrash") {
                root.operations.emptyTrash();
            }
        }
        onRejected: contents.forceActiveFocus(Qt.OtherFocusReason)
    }
}
