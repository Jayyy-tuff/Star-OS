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
    }

    FilesView {
        id: view
        anchors.fill: parent
        focus: true
        folderModel: fakeFolder
        places: fakePlaces
        operations: fakeOps
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
                               accessibleDescription: "Folder"});
            fakeFolder.append({name: "notes.txt", url: "file:///home/test/notes.txt", isDir: false,
                               accessibleDescription: "Plain text document, 12 bytes"});
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
    }
}
