// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Lens

// The Star Lens view with a test double for the backend: selecting with the
// mouse and the keyboard (on a 1280 × 720 capture shown at half size), the
// results, Google Lens asking first every time, errors, accessible names.
Item {
    id: root

    width: 1280
    height: 720

    QtObject {
        id: fakeLens

        property string state: "selecting"
        property string errorString: ""
        property url captureUrl: ""
        property size captureSize: Qt.size(1280, 720)
        property string text: ""
        property string code: ""
        property string codeFormat: ""
        property var links: []
        property string recognitionError: ""
        property string message: ""
        property var calls: []

        function record(call) {
            fakeLens.calls = fakeLens.calls.concat([call]);
        }
        function select(x, y, width, height) {
            fakeLens.record("select:" + [x, y, width, height].map(Math.round).join(","));
        }
        function selectAgain() {
            fakeLens.record("selectAgain");
            fakeLens.state = "selecting";
        }
        function copyText(part) {
            fakeLens.record("copyText:" + (part ?? ""));
        }
        function copyCode() {
            fakeLens.record("copyCode");
        }
        function copyImage() {
            fakeLens.record("copyImage");
        }
        function saveImage() {
            fakeLens.record("saveImage");
            return "";
        }
        function searchWeb() {
            fakeLens.record("searchWeb");
        }
        function openLink(link) {
            fakeLens.record("openLink:" + link);
            return true;
        }
        function openGoogleLens() {
            fakeLens.record("openGoogleLens");
        }
    }

    LensView {
        id: view
        width: 640
        height: 360
        lens: fakeLens
    }

    SignalSpy {
        id: closeSpy
        target: view
        signalName: "closeRequested"
    }

    TestCase {
        name: "LensView"
        when: windowShown

        function init() {
            fakeLens.state = "selecting";
            fakeLens.errorString = "";
            fakeLens.text = "";
            fakeLens.code = "";
            fakeLens.codeFormat = "";
            fakeLens.links = [];
            fakeLens.recognitionError = "";
            fakeLens.message = "";
            fakeLens.calls = [];
            view.area = Qt.rect(0, 0, 0, 0);
            closeSpy.clear();
            view.forceActiveFocus();
        }

        // Clicks once the item's row or flow has placed it.
        function click(item) {
            tryVerify(() => item.visible && item.width > 0 && !isPolishScheduled(item.parent), 5000);
            mouseClick(item);
        }

        function showResults() {
            fakeLens.state = "results";
            const results = findChild(view, "results");
            tryVerify(() => results.visible && results.width > 0, 5000);
            return results;
        }

        function test_names_and_hint() {
            compare(view.Accessible.role, Accessible.Pane);
            compare(view.Accessible.name, "Star Lens");
            compare(findChild(view, "hint").text, "Select an area");
            fakeLens.state = "recognizing";
            compare(findChild(view, "hint").text, "Reading the selected area…");
            fakeLens.state = "capturing";
            compare(findChild(view, "hint").text, "Taking a screenshot…");
        }

        function test_select_all_and_return() {
            keyClick(Qt.Key_A, Qt.ControlModifier);
            const selection = findChild(view, "selection");
            verify(selection.visible);
            compare(selection.Accessible.name, "Selected area");
            compare(selection.Accessible.description, "1280 by 720 pixels");
            keyClick(Qt.Key_Return);
            // View coordinates are scaled to the capture's.
            compare(fakeLens.calls, ["select:0,0,1280,720"]);
        }

        function test_return_without_area_reads_everything() {
            keyClick(Qt.Key_Return);
            compare(fakeLens.calls, ["select:0,0,1280,720"]);
        }

        function test_drag_selects() {
            mousePress(view, 100, 50);
            mouseMove(view, 200, 100, -1, Qt.LeftButton);
            mouseMove(view, 300, 150, -1, Qt.LeftButton);
            mouseRelease(view, 300, 150);
            compare(fakeLens.calls, ["select:200,100,400,200"]);
        }

        function test_tiny_drag_is_not_a_selection() {
            mousePress(view, 100, 50);
            mouseMove(view, 103, 52, -1, Qt.LeftButton);
            mouseRelease(view, 103, 52);
            compare(fakeLens.calls, []);
        }

        function test_arrows_place_move_and_resize() {
            keyClick(Qt.Key_Right);
            verify(view.hasArea, "the first arrow places an area in the middle");
            const first = view.area;
            fuzzyCompare(first.x + first.width / 2, view.width / 2, 0.5);
            keyClick(Qt.Key_Right);
            compare(view.area.x, first.x + view.step);
            compare(view.area.width, first.width);
            keyClick(Qt.Key_Down, Qt.ShiftModifier);
            compare(view.area.height, first.height + view.step);
            compare(view.area.y, first.y);
            // The area stays on screen.
            for (let i = 0; i < 100; ++i) {
                keyClick(Qt.Key_Left);
            }
            compare(view.area.x, 0);
        }

        function test_escape_closes_while_selecting() {
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 1);
        }

        function test_results() {
            fakeLens.text = "Hello star";
            fakeLens.links = ["https://example.org/"];
            const results = showResults();
            compare(results.Accessible.name, "Results");
            compare(findChild(results, "resultText").text, "Hello star");
            compare(findChild(results, "resultText").Accessible.name, "Recognised text");
            verify(!findChild(results, "noText").visible);
            const copy = findChild(results, "copyTextButton");
            tryVerify(() => copy.activeFocus, 5000, "Copy text has the focus");
            click(copy);
            const link = findChild(results, "linkButton");
            compare(link.text, "Open https://example.org/");
            compare(link.Accessible.name, "Open link");
            click(link);
            click(findChild(results, "searchButton"));
            click(findChild(results, "saveImageButton"));
            compare(fakeLens.calls, ["copyText:", "openLink:https://example.org/", "searchWeb", "saveImage"]);
        }

        function test_copy_shortcut_copies_through_lens() {
            fakeLens.text = "Hello star";
            const results = showResults();
            const area = findChild(results, "resultText");
            area.forceActiveFocus();
            area.select(0, 5);
            keySequence(StandardKey.Copy);
            compare(fakeLens.calls, ["copyText:Hello"]);
        }

        function test_no_text() {
            fakeLens.code = "4006381333931";
            fakeLens.codeFormat = "EAN13";
            const results = showResults();
            const noText = findChild(results, "noText");
            verify(noText.visible);
            compare(noText.text, "No text found.");
            fakeLens.recognitionError = "Text recognition is not available.";
            compare(noText.text, "Text recognition is not available.");
            verify(!findChild(results, "copyTextButton").enabled);
            compare(findChild(results, "codeText").text, "4006381333931");
            tryVerify(() => findChild(results, "searchButton").activeFocus, 5000, "Search the web has the focus");
            click(findChild(results, "copyCodeButton"));
            compare(fakeLens.calls, ["copyCode"]);
        }

        function test_nothing_found_focuses_copy_image() {
            const results = showResults();
            tryVerify(() => findChild(results, "copyImageButton").activeFocus, 5000);
        }

        function test_escape_in_results_selects_again() {
            fakeLens.text = "x";
            showResults();
            keyClick(Qt.Key_Escape);
            compare(fakeLens.calls, ["selectAgain"]);
            compare(closeSpy.count, 0);
            tryVerify(() => view.activeFocus, 5000, "the view takes the keys again");
        }

        function test_google_lens_asks_every_time() {
            fakeLens.text = "x";
            const results = showResults();
            const dialog = findChild(view, "lensDialog");
            verify(!dialog.visible);

            click(findChild(results, "googleLensButton"));
            verify(dialog.visible);
            compare(dialog.Accessible.role, Accessible.Dialog);
            compare(dialog.Accessible.name, "Search with Google Lens?");
            verify(findChild(dialog, "lensWarning").text.startsWith("This sends the selected image to Google."));
            const cancel = findChild(dialog, "lensCancelButton");
            verify(cancel.activeFocus, "Cancel has the focus");
            keyClick(Qt.Key_Escape);
            verify(!dialog.visible);
            compare(fakeLens.calls, []);

            click(findChild(results, "googleLensButton"));
            verify(dialog.visible, "asks again");
            click(findChild(dialog, "lensCancelButton"));
            verify(!dialog.visible);
            compare(fakeLens.calls, []);

            click(findChild(results, "googleLensButton"));
            click(findChild(dialog, "lensConfirmButton"));
            verify(!dialog.visible);
            compare(fakeLens.calls, ["openGoogleLens"]);
        }

        function test_close_button() {
            fakeLens.text = "x";
            const results = showResults();
            click(findChild(results, "closeButton"));
            compare(closeSpy.count, 1);
        }

        function test_error() {
            fakeLens.errorString = "Star Lens could not take a screenshot: no KWin.";
            fakeLens.state = "error";
            verify(findChild(view, "errorView").visible);
            verify(!findChild(view, "capture").visible);
            compare(findChild(view, "errorText").text, "Star Lens could not take a screenshot: no KWin.");
            keyClick(Qt.Key_Return);
            compare(fakeLens.calls, [], "nothing to select");
            click(findChild(view, "errorCloseButton"));
            compare(closeSpy.count, 1);
        }
    }
}
