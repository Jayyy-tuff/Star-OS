// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell
import StarOS.Welcome

// The Welcome tour with a test double for WelcomeState: five pages, Next and
// Back by keyboard and click, the app buttons, Skip and Escape finish, and
// the last page's button finishes.
Item {
    id: root

    width: 960
    height: 640

    QtObject {
        id: fakeWelcome

        property var calls: []

        function finish() {
            fakeWelcome.calls = fakeWelcome.calls.concat(["finish"]);
        }
        function open(desktopId) {
            fakeWelcome.calls = fakeWelcome.calls.concat(["open " + desktopId]);
            return true;
        }
    }

    WelcomeView {
        id: view
        anchors.fill: parent
        focus: true
        welcome: fakeWelcome
    }

    SignalSpy {
        id: doneSpy
        target: view
        signalName: "done"
    }

    TestCase {
        name: "WelcomeView"
        when: windowShown

        function initTestCase() {
            Theme.animationFactor = 0;
        }

        function init() {
            view.page = 0;
            fakeWelcome.calls = [];
            doneSpy.clear();
            view.forceActiveFocus();
            findChild(view, "nextButton").forceActiveFocus();
            waitForRendering(view);
        }

        function title() {
            return findChild(view, "pageTitle").text;
        }

        function test_first_page() {
            compare(view.Accessible.name, "Welcome to Star OS");
            compare(title(), "Welcome to Star OS");
            verify(findChild(view, "logo").visible);
            compare(findChild(view, "nextButton").text, "Take the tour");
            verify(findChild(view, "skipButton").visible);
            verify(!findChild(view, "backButton").visible);
            compare(findChild(view, "dots").Accessible.name, "Page 1 of 5");
        }

        function test_pages_by_keyboard() {
            const titles = [title()];
            for (let i = 0; i < 4; ++i) {
                keyClick(Qt.Key_Right);
                titles.push(title());
            }
            compare(titles, ["Welcome to Star OS", "Everything starts with the Star key", "Star Lens reads your screen",
                             "Keep your work with Star Storage", "Apps and games"]);
            compare(findChild(view, "dots").Accessible.name, "Page 5 of 5");
            compare(findChild(view, "nextButton").text, "Start using Star OS");
            verify(!findChild(view, "skipButton").visible);
            keyClick(Qt.Key_Left);
            compare(title(), "Keep your work with Star Storage");
            // Return on the focused Next button goes on, then finishes.
            keyClick(Qt.Key_Return);
            compare(view.page, 4);
            compare(doneSpy.count, 0);
            keyClick(Qt.Key_Return);
            compare(fakeWelcome.calls, ["finish"]);
            compare(doneSpy.count, 1);
        }

        function test_app_buttons() {
            view.page = 2;
            waitForRendering(view);
            const action = findChild(view, "actionButton");
            compare(action.text, "Try Star Lens");
            mouseClick(action);
            view.page = 3;
            waitForRendering(view);
            compare(action.text, "Open Star Storage");
            mouseClick(action);
            view.page = 4;
            waitForRendering(view);
            mouseClick(action);
            mouseClick(findChild(view, "gamesButton"));
            compare(fakeWelcome.calls, ["open org.staros.lens.desktop", "open org.staros.storage.desktop",
                                        "open org.staros.sunstore.desktop", "open org.staros.games.desktop"]);
            view.page = 1;
            verify(!action.parent.visible, "no app button on the start menu page");
        }

        function test_back_button() {
            mouseClick(findChild(view, "nextButton"));
            compare(view.page, 1);
            waitForRendering(view);
            const back = findChild(view, "backButton");
            verify(back.visible);
            mouseClick(back);
            compare(view.page, 0);
        }

        function test_skip_and_escape() {
            mouseClick(findChild(view, "skipButton"));
            compare(fakeWelcome.calls, ["finish"]);
            compare(doneSpy.count, 1);
            view.page = 2;
            keyClick(Qt.Key_Escape);
            compare(fakeWelcome.calls, ["finish", "finish"]);
            compare(doneSpy.count, 2);
        }

        function test_card_fits() {
            const card = findChild(view, "card");
            verify(card.width <= root.width);
            verify(card.height <= root.height);
            verify(card.x >= 0 && card.y >= 0);
        }
    }
}
