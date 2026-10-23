// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Storage

// The Star Storage view with test doubles for the backend and the system
// status: what it says about the session, choosing a disk, the typed
// confirmation, progress, the result and the boot choices.
Item {
    id: root

    width: 900
    height: 760

    readonly property var sampleDisks: [
        {name: "vdb", path: "/dev/vdb", model: "", size: 10737418240, transport: "virtio", removable: false,
         usable: true, reason: "", reasonText: "", starStorage: false, partitions: []},
        {name: "sda", path: "/dev/sda", model: "SanDisk Ultra", size: 32000000000, transport: "usb", removable: true,
         usable: false, reason: "medium", reasonText: "This is the Star OS medium.", starStorage: false, partitions: []},
        {name: "sdc", path: "/dev/sdc", model: "Samsung SSD 870", size: 64000000000, transport: "sata", removable: false,
         usable: true, reason: "", reasonText: "", starStorage: false,
         partitions: [{name: "sdc1", path: "/dev/sdc1", size: 64000000000, fstype: "ntfs", label: "Data"}]}
    ]

    QtObject {
        id: fakeBackend

        property string state: "ready"
        property string errorString: ""
        property string step: ""
        property string partition: ""
        property var disks: []
        property var existing: []
        property bool uefi: true
        property bool canChooseBoot: true
        property bool alwaysStarStorage: false
        property bool busy: false
        property string message: ""
        property var calls: []

        function record(call) {
            fakeBackend.calls = fakeBackend.calls.concat([call]);
        }
        function refresh() {
            fakeBackend.record("refresh");
        }
        function format(name, confirmation) {
            fakeBackend.record("format:" + name + ":" + confirmation);
        }
        function setBoot(mode) {
            fakeBackend.record("setBoot:" + mode);
        }
        function restartIntoStarStorage() {
            fakeBackend.record("restartIntoStarStorage");
        }
    }

    QtObject {
        id: fakeStatus

        property string storageMode: "live"
        property real storageFree: 3200000000
        property real storageTotal: 4000000000
    }

    StorageView {
        id: view
        anchors.fill: parent
        backend: fakeBackend
        status: fakeStatus
    }

    TestCase {
        name: "StorageView"
        when: windowShown

        function init() {
            fakeBackend.state = "ready";
            fakeBackend.errorString = "";
            fakeBackend.step = "";
            fakeBackend.partition = "";
            fakeBackend.disks = root.sampleDisks;
            fakeBackend.existing = [];
            fakeBackend.uefi = true;
            fakeBackend.canChooseBoot = true;
            fakeBackend.alwaysStarStorage = false;
            fakeBackend.busy = false;
            fakeBackend.message = "";
            fakeBackend.calls = [];
            fakeStatus.storageMode = "live";
            const list = findChild(view, "disks");
            list.currentIndex = -1;
            view.forceActiveFocus();
        }

        function click(item) {
            tryVerify(() => item.visible && item.width > 0 && !isPolishScheduled(item.parent), 5000);
            mouseClick(item);
        }

        function rows() {
            const list = findChild(view, "disks");
            const found = [];
            for (let i = 0; i < list.count; ++i) {
                list.positionViewAtIndex(i, ListView.Contain);
                found.push(list.itemAtIndex(i));
            }
            return found;
        }

        function selectDisk(index) {
            const list = findChild(view, "disks");
            list.forceActiveFocus();
            list.currentIndex = index;
            tryVerify(() => view.selectedDisk !== null && view.selectedDisk.name === fakeBackend.disks[index].name);
        }

        function test_names_and_status() {
            compare(view.Accessible.role, Accessible.Pane);
            compare(view.Accessible.name, "Star Storage");
            compare(findChild(view, "title").text, "Star Storage");
            const list = findChild(view, "disks");
            compare(list.Accessible.role, Accessible.List);
            compare(list.Accessible.name, "Disks");
            const status = findChild(view, "statusText");
            compare(status.text, "This session keeps its changes in memory: they are lost when the computer is turned off.");
            fakeStatus.storageMode = "star-storage";
            compare(status.text, "This session keeps its changes on Star Storage: 3.2 GB free of 4 GB.");
            fakeStatus.storageMode = "installed";
            verify(status.text.startsWith("Star OS is installed"));
        }

        function test_rows() {
            const found = rows();
            compare(found.length, 3);
            compare(found[0].Accessible.role, Accessible.ListItem);
            compare(found[0].Accessible.name, "vdb · 10.7 GB");
            compare(found[0].Accessible.description, "vdb · VIRTIO");
            compare(found[1].Accessible.name, "SanDisk Ultra · 32 GB");
            compare(found[1].Accessible.description, "sda · USB · This is the Star OS medium.");
        }

        function test_keyboard_selects_first_disk() {
            const list = findChild(view, "disks");
            findChild(view, "refreshButton").forceActiveFocus();
            list.currentIndex = -1;
            list.forceActiveFocus();
            compare(list.currentIndex, 0, "focusing the list selects the first disk");
            keyClick(Qt.Key_Down);
            compare(list.currentIndex, 1);
            compare(view.selectedDisk.name, "sda");
        }

        function test_unusable_disk_says_why() {
            selectDisk(1);
            const reason = findChild(view, "reasonText");
            verify(reason.visible);
            compare(reason.text, "sda cannot be used. This is the Star OS medium.");
            verify(!findChild(view, "confirmField").visible);
            verify(!findChild(view, "eraseButton").visible);
        }

        function test_erasing_needs_the_typed_name() {
            selectDisk(2);
            const warning = findChild(view, "warning");
            verify(warning.visible);
            compare(warning.text, "Erasing sdc deletes everything on it (sdc1, ntfs “Data”, 64 GB). "
                    + "What you did in this session is not copied to Star Storage.");
            const field = findChild(view, "confirmField");
            const erase = findChild(view, "eraseButton");
            compare(field.Accessible.name, "Disk name to confirm");
            compare(field.Accessible.description, "Type sdc to confirm:");
            verify(!erase.enabled);
            field.forceActiveFocus();
            keyClick("s");
            keyClick("d");
            verify(!erase.enabled, "a partial name is not enough");
            keyClick(Qt.Key_Return);
            compare(fakeBackend.calls, []);
            keyClick("c");
            verify(erase.enabled);
            click(erase);
            compare(fakeBackend.calls, ["format:sdc:sdc"]);
        }

        function test_return_in_the_field_erases() {
            selectDisk(0);
            const field = findChild(view, "confirmField");
            compare(findChild(view, "warning").text.indexOf("(it has no partitions)") > 0, true);
            field.forceActiveFocus();
            field.text = "vdb";
            keyClick(Qt.Key_Return);
            compare(fakeBackend.calls, ["format:vdb:vdb"]);
        }

        function test_other_disk_clears_the_confirmation() {
            selectDisk(0);
            const field = findChild(view, "confirmField");
            field.text = "vdb";
            selectDisk(2);
            compare(field.text, "");
            verify(!findChild(view, "eraseButton").enabled);
        }

        function test_names_are_case_sensitive() {
            selectDisk(0);
            findChild(view, "confirmField").text = "VDB";
            verify(!findChild(view, "eraseButton").enabled);
        }

        function test_existing_star_storage() {
            fakeBackend.existing = ["vdc"];
            const panel = findChild(view, "existingPanel");
            verify(panel.visible);
            const restart = findChild(panel, "restartButton");
            verify(restart.visible);
            click(restart);
            compare(fakeBackend.calls, ["restartIntoStarStorage"]);
            fakeBackend.canChooseBoot = false;
            verify(!restart.visible);
            // While running from it, the panel is not needed.
            fakeStatus.storageMode = "star-storage";
            verify(!panel.visible);
        }

        function test_always_start_with_star_storage() {
            const always = findChild(view, "alwaysButton");
            verify(!always.visible, "only while running from Star Storage");
            fakeStatus.storageMode = "star-storage";
            verify(always.visible);
            compare(always.Accessible.role, Accessible.CheckBox);
            compare(always.Accessible.name, "Always start with Star Storage");
            verify(!always.Accessible.checked);
            click(always);
            compare(fakeBackend.calls, ["setBoot:always"]);
            fakeBackend.alwaysStarStorage = true;
            verify(always.Accessible.checked);
            click(always);
            compare(fakeBackend.calls, ["setBoot:always", "setBoot:never"]);
            fakeBackend.canChooseBoot = false;
            verify(!always.visible);
        }

        function test_working() {
            selectDisk(0);
            fakeBackend.state = "working";
            fakeBackend.step = "Making a partition on vdb";
            verify(findChild(view, "working").visible);
            compare(findChild(view, "stepText").text, "Making a partition on vdb");
            verify(!findChild(view, "details").visible);
            verify(!findChild(view, "refreshButton").visible);
        }

        function test_done_with_uefi() {
            fakeBackend.partition = "/dev/vdb1";
            fakeBackend.state = "done";
            verify(findChild(view, "donePanel").visible);
            compare(findChild(view, "doneText").text, "Star Storage is ready on /dev/vdb1.");
            const restart = findChild(view, "doneRestartButton");
            tryVerify(() => restart.activeFocus, 5000, "Restart into Star Storage has the focus");
            verify(!findChild(view, "biosText").visible);
            keyClick(Qt.Key_Return);
            compare(fakeBackend.calls, ["restartIntoStarStorage"]);
        }

        function test_done_with_bios() {
            fakeBackend.canChooseBoot = false;
            fakeBackend.uefi = false;
            fakeBackend.partition = "/dev/sdb1";
            fakeBackend.state = "done";
            const bios = findChild(view, "biosText");
            verify(bios.visible);
            verify(bios.text.indexOf("“Star OS live (prototype) with Star Storage”") > 0);
            verify(!findChild(view, "doneRestartButton").visible);
            tryVerify(() => findChild(view, "doneText").activeFocus, 5000);
        }

        function test_error() {
            fakeBackend.errorString = "Star Storage was not set up. Permission was not given.";
            fakeBackend.state = "error";
            compare(findChild(view, "errorText").text, "Star Storage was not set up. Permission was not given.");
            const again = findChild(view, "errorRefreshButton");
            tryVerify(() => again.activeFocus, 5000);
            click(again);
            compare(fakeBackend.calls, ["refresh"]);
        }

        function test_list_states() {
            const listState = findChild(view, "listState");
            fakeBackend.state = "loading";
            compare(listState.text, "Looking for disks…");
            fakeBackend.state = "ready";
            fakeBackend.disks = [];
            compare(listState.text, "No disks found. Connect one and look again.");
            click(findChild(view, "refreshButton"));
            compare(fakeBackend.calls, ["refresh"]);
        }

        function test_message() {
            fakeBackend.message = "Star OS now starts with Star Storage every time.";
            const message = findChild(view, "message");
            verify(message.visible);
            compare(message.text, "Star OS now starts with Star Storage every time.");
        }
    }
}
