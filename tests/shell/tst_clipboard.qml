// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Clipboard history panel (M0.5, ADR-0014): where it sits, the empty
// state, rows for text and images, Return and clicks copy, Delete and the
// row's button forget, Clear, Escape and clicks outside, and the focus
// ring. The history is a ListModel with ClipboardHistory's roles and
// functions.
Item {
    id: root

    width: 1280
    height: 720

    readonly property date fixedNow: new Date(2026, 9, 25, 14, 30)

    ListModel {
        id: fakeHistory
    }

    // ClipboardHistory's functions, recorded.
    QtObject {
        id: actions

        property var calls: []

        function copy(row) {
            actions.calls = actions.calls.concat(["copy " + row]);
        }
        function remove(row) {
            actions.calls = actions.calls.concat(["remove " + row]);
            fakeHistory.remove(row, 1);
        }
        function clear() {
            actions.calls = actions.calls.concat(["clear"]);
            fakeHistory.clear();
        }
    }

    ClipboardPanel {
        id: panel
        anchors.fill: parent
        history: actions
        model: fakeHistory
    }

    Component {
        id: smallPanel

        ClipboardPanel {
            width: 640
            height: 360
            history: actions
            model: fakeHistory
        }
    }

    SignalSpy {
        id: closeSpy
        target: panel
        signalName: "closeRequested"
    }

    SignalSpy {
        id: copiedSpy
        target: panel
        signalName: "copied"
    }

    TestCase {
        name: "ClipboardPanel"
        when: windowShown

        property ListView list

        function initTestCase() {
            Theme.animationFactor = 0;
            list = findChild(panel, "clipboardList");
            verify(list);
        }

        function init() {
            fakeHistory.clear();
            actions.calls = [];
            closeSpy.clear();
            copiedSpy.clear();
        }

        function fill() {
            fakeHistory.append({kind: "text", text: "Newest words", thumbnail: "", description: "12 characters",
                                copiedAt: root.fixedNow});
            fakeHistory.append({kind: "image", text: "Image", thumbnail: "", description: "Image, 400 × 200 pixels",
                                copiedAt: new Date(root.fixedNow.getTime() - 5 * 60000)});
            fakeHistory.append({kind: "text", text: "Oldest", thumbnail: "", description: "6 characters",
                                copiedAt: new Date(root.fixedNow.getTime() - 3 * 3600000)});
            actions.calls = [];
            showPanel();
            tryVerify(() => list.itemAtIndex(2) !== null, 2000, "the rows are laid out");
        }

        function showPanel() {
            panel.reset();
            panel.now = root.fixedNow;
            waitForRendering(panel);
        }

        function test_panel_sits_above_the_taskbar() {
            showPanel();
            const glass = findChild(panel, "panel");
            fuzzyCompare(glass.x + glass.width / 2, root.width / 2, 1);
            const bottom = root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap;
            fuzzyCompare(glass.y + glass.height, bottom, 1);
            compare(panel.Accessible.name, "Clipboard history");
        }

        function test_empty_state() {
            showPanel();
            verify(findChild(panel, "emptyState").visible);
            verify(!findChild(panel, "clearButton").visible);
            verify(!list.visible);
            verify(findChild(panel, "hint").visible);
            keyClick(Qt.Key_Return);
            compare(actions.calls, []);
        }

        function test_rows() {
            fill();
            compare(panel.count, 3);
            compare(list.Accessible.name, "Copies");
            compare(list.itemAtIndex(0).Accessible.name, "Newest words");
            compare(list.itemAtIndex(0).Accessible.description, "12 characters. Copied just now");
            compare(list.itemAtIndex(1).Accessible.name, "Image, 400 × 200 pixels");
            compare(list.itemAtIndex(1).Accessible.description, "Copied 5 min ago");
            verify(list.itemAtIndex(2).Accessible.description.startsWith("6 characters. Copied at "));
            verify(findChild(list.itemAtIndex(1), "thumbnail").visible);
            verify(!findChild(list.itemAtIndex(1), "preview").visible);
            verify(findChild(list.itemAtIndex(0), "preview").visible);
            verify(!findChild(panel, "emptyState").visible);
        }

        function test_return_copies_the_current_row() {
            fill();
            tryVerify(() => list.itemAtIndex(0).activeFocus, 2000, "the newest copy has focus");
            keyClick(Qt.Key_Down);
            tryVerify(() => list.itemAtIndex(1).activeFocus);
            keyClick(Qt.Key_Return);
            compare(actions.calls, ["copy 1"]);
            compare(copiedSpy.count, 1);
        }

        function test_click_copies() {
            fill();
            mouseClick(list.itemAtIndex(2), 20, 10);
            compare(actions.calls, ["copy 2"]);
            compare(copiedSpy.count, 1);
        }

        function test_delete_forgets() {
            fill();
            tryVerify(() => list.itemAtIndex(0).activeFocus);
            keyClick(Qt.Key_Delete);
            compare(actions.calls, ["remove 0"]);
            compare(fakeHistory.count, 2);
            compare(copiedSpy.count, 0);
            waitForRendering(panel);
            mouseClick(findChild(list.itemAtIndex(1), "removeButton"));
            compare(actions.calls, ["remove 0", "remove 1"]);
            compare(copiedSpy.count, 0);
        }

        function test_clear() {
            fill();
            const clear = findChild(panel, "clearButton");
            verify(clear.visible);
            compare(clear.text, "Clear");
            mouseClick(clear);
            compare(actions.calls, ["clear"]);
            tryVerify(() => findChild(panel, "emptyState").visible);
            verify(panel.activeFocus || panel.Window.activeFocusItem === panel, "focus stays in the panel");
        }

        function test_escape_and_click_outside() {
            fill();
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 1);
            mouseClick(panel, 10, 10);
            compare(closeSpy.count, 2);
            const glass = findChild(panel, "panel");
            mouseClick(glass, 4, 4);
            compare(closeSpy.count, 2, "a click on the panel keeps it open");
        }

        // grabImage() returns device pixels without a pixel ratio, cropped to
        // the item's logical size; a short panel keeps the first row inside
        // that crop at every scale.
        function test_focus_ring() {
            fill();
            const small = createTemporaryObject(smallPanel, root);
            small.reset();
            const smallList = findChild(small, "clipboardList");
            tryVerify(() => smallList.itemAtIndex(0) !== null && smallList.itemAtIndex(0).activeFocus, 2000,
                      "the first row has focus");
            const row = smallList.itemAtIndex(0);
            waitForRendering(small);
            const img = grabImage(small);
            const dpr = Screen.devicePixelRatio;
            const p = row.mapToItem(small, 0, Math.min(row.height / 2, 12));
            const y = Math.floor(p.y * dpr);
            verify(Math.floor((p.x + 6) * dpr) < img.width && y < img.height,
                   "sample point inside the grabbed image " + img.width + "x" + img.height);
            let hits = 0;
            for (let x = Math.max(0, Math.floor(p.x * dpr) - 2); x < Math.floor((p.x + 6) * dpr); ++x) {
                if (Math.abs(img.red(x, y) - Theme.focusRing.r * 255) <= 8
                        && Math.abs(img.green(x, y) - Theme.focusRing.g * 255) <= 8
                        && Math.abs(img.blue(x, y) - Theme.focusRing.b * 255) <= 8) {
                    hits += 1;
                }
            }
            verify(hits >= Theme.focusRingWidth, "focus ring pixels: " + hits);
        }
    }
}
