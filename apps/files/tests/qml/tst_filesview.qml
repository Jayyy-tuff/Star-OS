// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Files
import StarOS.Shell

// The Files view with test doubles for the folder, the places and the file
// operations: keyboard operation, accessible names, confirmations.
Item {
    id: root

    width: 1100
    height: 700

    ListModel {
        id: fakeFolder

        property url url: "file:///home/test"
        property string location: "/home/test"
        property url parentUrl: "file:///home"
        property bool isTrash: false
        property string nameFilter: ""
        property bool showHidden: false
        property int sortKey: 0
        property string freeText: ""
        property bool loading: false
        property string errorString: ""
        property int refreshes: 0

        function refresh() {
            fakeFolder.refreshes += 1;
        }

        function indexOfUrl(url) {
            for (let i = 0; i < fakeFolder.count; ++i) {
                if (String(fakeFolder.get(i).url) === String(url)) {
                    return i;
                }
            }
            return -1;
        }

        function urlFromLocation(text) {
            return text.startsWith("/") ? "file://" + text : "";
        }
    }

    ListModel {
        id: fakePlaces

        ListElement {
            name: "Home"
            url: "file:///home/test"
        }
        ListElement {
            name: "Trash"
            url: "trash:/"
        }

        function indexOfUrl(url) {
            for (let i = 0; i < fakePlaces.count; ++i) {
                if (String(fakePlaces.get(i).url) === String(url)) {
                    return i;
                }
            }
            return -1;
        }

        function nameForUrl(url) {
            const row = fakePlaces.indexOfUrl(url);
            return row >= 0 ? fakePlaces.get(row).name : String(url).split("/").pop();
        }
    }

    QtObject {
        id: fakeOps

        property bool busy: false
        property int progress: -1
        property string statusText: ""
        property var calls: []

        signal finished(string operation, var urls)
        signal failed(string operation, string message)

        function record(name, args) {
            fakeOps.calls = fakeOps.calls.concat([name + ":" + args.map(String).join(",")]);
        }
        function nameError(name) {
            return name.trim() === "" ? "Enter a name." : "";
        }
        function open(url) { fakeOps.record("open", [url]); }
        function moveToTrash(urls) { fakeOps.record("trash", urls); }
        function deletePermanently(urls) { fakeOps.record("delete", urls); }
        function rename(url, name) { fakeOps.record("rename", [url, name]); }
        function createFolder(parent, name) { fakeOps.record("newFolder", [parent, name]); }
        function copyToClipboard(urls) { fakeOps.record("copy", urls); }
        function cutToClipboard(urls) { fakeOps.record("cut", urls); }
        function paste(destination) { fakeOps.record("paste", [destination]); }
        function restoreFromTrash(urls) { fakeOps.record("restore", urls); }
        function emptyTrash() { fakeOps.record("emptyTrash", []); }
        function openTerminal(url) { fakeOps.record("terminal", [url]); return true; }
        function openStarStorage() { fakeOps.record("storage", []); return true; }
    }

    QtObject {
        id: fakeStatus

        property string storageMode: "live"
        property real storageFree: 3200000000
        property real storageTotal: 4000000000
    }

    FilesView {
        id: view
        anchors.fill: parent
        focus: true
        folderModel: fakeFolder
        places: fakePlaces
        operations: fakeOps
        status: fakeStatus
    }

    TestCase {
        name: "FilesView"
        when: windowShown

        property ListView contents
        property ListView placesList
        property Item confirmDialog
        property Item nameDialog

        function initTestCase() {
            contents = findChild(view, "folderContents");
            placesList = findChild(view, "places");
            confirmDialog = findChild(view, "confirmDialog");
            nameDialog = findChild(view, "nameDialog");
            verify(contents !== null && placesList !== null && confirmDialog !== null && nameDialog !== null);
        }

        function init() {
            fakeFolder.clear();
            fakeFolder.append({name: "Documents", url: "file:///home/test/Documents", isDir: true,
                               accessibleDescription: "Folder", mimeType: "inode/directory", size: 0});
            fakeFolder.append({name: "notes.txt", url: "file:///home/test/notes.txt", isDir: false,
                               accessibleDescription: "Plain text document, 12 bytes",
                               mimeType: "text/plain", size: 12});
            fakeFolder.isTrash = false;
            fakeFolder.sortKey = 0;
            fakeFolder.freeText = "";
            fakeStatus.storageMode = "live";
            fakeOps.calls = [];
            contents.currentIndex = 0;
            contents.forceActiveFocus();
            tryVerify(() => contents.activeFocus, 5000, "folder contents have focus");
            tryVerify(() => contents.currentItem !== null, 5000, "a current item");
        }

        function test_accessible_structure() {
            compare(view.title, "Files — Home");
            compare(findChild(view, "toolbar").Accessible.name, "Files toolbar");
            compare(placesList.Accessible.role, Accessible.List);
            compare(placesList.Accessible.name, "Places");
            compare(contents.Accessible.role, Accessible.List);
            compare(contents.Accessible.name, "Folder contents");
            compare(contents.currentItem.Accessible.name, "Documents");
            compare(contents.currentItem.Accessible.description, "Folder");
        }

        function test_return_opens_files_through_operations() {
            keyClick(Qt.Key_Down);
            compare(contents.currentIndex, 1);
            keyClick(Qt.Key_Return);
            compare(fakeOps.calls, ["open:file:///home/test/notes.txt"]);
        }

        function test_delete_moves_to_trash() {
            keyClick(Qt.Key_Delete);
            compare(fakeOps.calls, ["trash:file:///home/test/Documents"]);
        }

        function test_shift_delete_asks_first() {
            keyClick(Qt.Key_Delete, Qt.ShiftModifier);
            tryVerify(() => confirmDialog.visible, 5000, "the confirmation is shown");
            compare(fakeOps.calls, []);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !confirmDialog.visible, 5000, "Escape closes the confirmation");
            compare(fakeOps.calls, []);
        }

        function test_copy_and_paste_keys() {
            keyClick(Qt.Key_C, Qt.ControlModifier);
            keyClick(Qt.Key_V, Qt.ControlModifier);
            compare(fakeOps.calls, ["copy:file:///home/test/Documents", "paste:file:///home/test"]);
        }

        function test_f2_opens_rename_dialog() {
            keyClick(Qt.Key_F2);
            tryVerify(() => nameDialog.visible, 5000, "the rename dialog is shown");
            keyClick(Qt.Key_Escape);
            tryVerify(() => !nameDialog.visible, 5000, "Escape closes the dialog");
            compare(fakeOps.calls, []);
        }

        function test_focus_ring_follows_current_item() {
            verify(contents.currentItem.activeFocus || contents.activeFocus);
        }

        function click(item) {
            tryVerify(() => item.visible && item.width > 0 && !isPolishScheduled(item.parent), 5000);
            mouseClick(item);
        }

        function test_sort_button_and_keys() {
            const sort = findChild(view, "sortButton");
            compare(sort.text, "Sort: Name");
            compare(sort.Accessible.description, "Ctrl+1 name, Ctrl+2 size, Ctrl+3 time modified");
            click(sort);
            compare(fakeFolder.sortKey, 1);
            compare(sort.text, "Sort: Size");
            contents.forceActiveFocus();
            keyClick(Qt.Key_3, Qt.ControlModifier);
            compare(fakeFolder.sortKey, 2);
            compare(sort.text, "Sort: Modified");
            keyClick(Qt.Key_1, Qt.ControlModifier);
            compare(fakeFolder.sortKey, 0);
        }

        function test_status_line_shows_free_space() {
            const status = findChild(view, "statusLabel");
            compare(status.text, "2 items");
            fakeFolder.freeText = "9.8 GiB free";
            compare(status.text, "2 items · 9.8 GiB free");
        }

        function test_open_terminal() {
            keyClick(Qt.Key_F4, Qt.ShiftModifier);
            compare(fakeOps.calls, ["terminal:file:///home/test"]);
            const terminal = findChild(view, "terminalButton");
            compare(terminal.Accessible.name, "Open Terminal");
            click(terminal);
            compare(fakeOps.calls.length, 2);
            fakeFolder.isTrash = true;
            verify(!terminal.visible);
            contents.forceActiveFocus();
            keyClick(Qt.Key_F4, Qt.ShiftModifier);
            compare(fakeOps.calls.length, 2, "no terminal in the Trash");
        }

        function test_storage_panel() {
            const panel = findChild(view, "storagePanel");
            verify(panel.visible);
            compare(panel.Accessible.name, "Storage");
            compare(panel.Accessible.description, "Live session: 3.2 GB free of 4 GB. Changes are lost at shutdown.");
            const button = findChild(view, "storageButton");
            compare(button.text, "Set up Star Storage");
            click(button);
            compare(fakeOps.calls, ["storage:"]);
            fakeStatus.storageMode = "star-storage";
            compare(panel.Accessible.description, "Star Storage: 3.2 GB free of 4 GB.");
            compare(button.text, "Star Storage");
            fakeStatus.storageMode = "installed";
            verify(!button.visible);
        }

        function test_type_icons_and_thumbnails() {
            compare(contents.itemAtIndex(0).kind, "folder");
            compare(contents.itemAtIndex(1).kind, "text");
            fakeFolder.append({name: "photo.png", url: "file:///home/test/photo.png", isDir: false,
                               accessibleDescription: "PNG image, 2 kB", mimeType: "image/png", size: 2048});
            fakeFolder.append({name: "huge.png", url: "file:///home/test/huge.png", isDir: false,
                               accessibleDescription: "PNG image, 30 MB", mimeType: "image/png", size: 30000000});
            tryVerify(() => contents.itemAtIndex(3) !== null, 5000);
            const photo = contents.itemAtIndex(2);
            compare(photo.kind, "image");
            compare(String(findChild(photo, "thumbnail").source), "file:///home/test/photo.png");
            compare(String(findChild(contents.itemAtIndex(3), "thumbnail").source), "", "no thumbnail over 20 MB");
            compare(String(findChild(contents.itemAtIndex(1), "thumbnail").source), "");
        }
    }
}
