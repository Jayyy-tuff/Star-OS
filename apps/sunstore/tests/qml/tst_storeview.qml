// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.SunStore
import StarOS.Shell

// The Sun Store view with a fake store: the consent page, sections, the
// apps list, the app page and its actions, offline text, accessible names.
Item {
    id: root

    width: 1100
    height: 720

    ListModel {
        id: fakeApps

        property string section: "discover"
        property string category: ""
        property string searchText: ""
        property int updateCount: 0
        property int revision: 0

        function app(appId) {
            for (let i = 0; i < fakeApps.count; ++i) {
                const row = fakeApps.get(i);
                if (row.appId === appId) {
                    return {appId: row.appId, name: row.name, summary: row.summary, iconUrl: row.iconUrl,
                            installed: row.installed, updateAvailable: row.updateAvailable, inCatalogue: true,
                            developer: "Example Developers", verified: true, license: "GPL-3.0-or-later",
                            version: "2.1", installedVersion: row.installed ? "2.0" : "",
                            description: "Writes text files."};
                }
            }
            return {};
        }
        function indexOf(appId) {
            for (let i = 0; i < fakeApps.count; ++i) {
                if (fakeApps.get(i).appId === appId) {
                    return i;
                }
            }
            return -1;
        }
        function categoryIds() {
            return ["Game", "Utility"];
        }
        function categoryName(id) {
            return id === "Game" ? "Games" : "Utilities";
        }
    }

    QtObject {
        id: fakeStore

        property string state: "ready"
        property bool offline: false
        property string errorString: ""
        property bool busy: false
        property string operation: ""
        property string busyAppId: ""
        property string progressText: ""
        property var apps: fakeApps
        property var calls: []

        signal operationFinished(string operation, string appId)
        signal operationFailed(string operation, string appId, string message)
        signal permissionsReady(string appId, var permissions)
        signal permissionsFailed(string appId, string message)

        function record(call) {
            fakeStore.calls = fakeStore.calls.concat([call]);
        }
        function start() { fakeStore.record("start"); }
        function enableFlathub() { fakeStore.record("enableFlathub"); }
        function refresh() { fakeStore.record("refresh"); }
        function updateAll() { fakeStore.record("updateAll"); return true; }
        function install(appId) { fakeStore.record("install:" + appId); return true; }
        function remove(appId) { fakeStore.record("remove:" + appId); return true; }
        function open(appId) { fakeStore.record("open:" + appId); return true; }
        function requestPermissions(appId) { fakeStore.record("permissions:" + appId); }
    }

    StoreView {
        id: view
        anchors.fill: parent
        focus: true
        store: fakeStore
    }

    SignalSpy {
        id: closeSpy
        target: view
        signalName: "closeRequested"
    }

    TestCase {
        name: "StoreView"
        when: windowShown

        property ListView appList
        property Item appPage
        property Item consentPage
        property Item sections
        property Item searchField

        function initTestCase() {
            appList = findChild(view, "appList");
            appPage = findChild(view, "appPage");
            consentPage = findChild(view, "consentPage");
            sections = findChild(view, "sections");
            searchField = findChild(view, "searchField");
            verify(appList !== null && appPage !== null && consentPage !== null && sections !== null
                   && searchField !== null);
        }

        function init() {
            fakeApps.clear();
            fakeApps.append({appId: "org.example.Editor", name: "Example Editor", summary: "Edit plain text",
                             iconUrl: "", installed: false, updateAvailable: false});
            fakeApps.append({appId: "org.example.Game", name: "Example Game", summary: "Play a game",
                             iconUrl: "", installed: true, updateAvailable: false});
            fakeApps.section = "discover";
            fakeApps.searchText = "";
            fakeStore.state = "ready";
            fakeStore.offline = false;
            fakeStore.calls = [];
            closeSpy.clear();
            view.closeApp();
            view.clearMessage();
            appList.currentIndex = 0;
            appList.forceActiveFocus();
            tryVerify(() => appList.activeFocus, 5000, "the apps list has focus");
            tryVerify(() => appList.currentItem !== null, 5000, "a current app");
        }

        function test_accessible_structure() {
            compare(sections.Accessible.role, Accessible.PageTabList);
            compare(sections.Accessible.name, "Store sections");
            const names = ["Discover", "Installed", "Updates"];
            for (const section of ["discover", "installed", "updates"]) {
                const tab = findChild(view, section + "Tab");
                verify(tab !== null, section + " tab");
                compare(tab.Accessible.role, Accessible.PageTab);
                compare(tab.Accessible.name, names.shift());
            }
            verify(findChild(view, "discoverTab").checked);
            compare(appList.Accessible.role, Accessible.List);
            compare(appList.Accessible.name, "Apps");
            compare(searchField.Accessible.name, "Search apps");
            compare(appList.currentItem.Accessible.name, "Example Editor");
            compare(appList.currentItem.Accessible.description, "Edit plain text");
            appList.currentIndex = 1;
            compare(appList.currentItem.Accessible.description, "Play a game. Installed");
        }

        function test_consent_page() {
            fakeStore.state = "needsConsent";
            tryVerify(() => consentPage.visible, 5000, "the consent page is shown");
            verify(!appList.visible);
            const enable = findChild(consentPage, "enableFlathubButton");
            compare(enable.Accessible.role, Accessible.Button);
            compare(enable.Accessible.name, "Enable Flathub");
            compare(findChild(consentPage, "consentMessage").text,
                    "Sun Store installs apps from Flathub, a community app store. Star OS does not review these apps.");
            compare(findChild(consentPage, "declineButton").Accessible.name, "Not now");
            tryVerify(() => enable.activeFocus, 5000, "Enable Flathub has the focus");
            keyClick(Qt.Key_Return);
            compare(fakeStore.calls, ["enableFlathub"]);
            keyClick(Qt.Key_Tab);
            keyClick(Qt.Key_Space);
            compare(closeSpy.count, 1);
            fakeStore.state = "ready";
            tryVerify(() => !consentPage.visible && appList.activeFocus, 5000, "the list returns");
        }

        function test_offline_without_catalogue() {
            fakeApps.clear();
            fakeStore.state = "offline";
            const empty = findChild(view, "emptyState");
            tryVerify(() => empty.visible, 5000, "the empty state is shown");
            compare(empty.text, "Can't reach Flathub. Check your network connection.");
            const retry = findChild(view, "retryButton");
            verify(retry.visible);
            mouseClick(retry);
            compare(fakeStore.calls, ["refresh"]);
        }

        function test_tabs_choose_the_section() {
            mouseClick(findChild(view, "installedTab"));
            compare(fakeApps.section, "installed");
            verify(findChild(view, "installedTab").checked);
            verify(!findChild(view, "categories").visible, "categories only in Discover");
            mouseClick(findChild(view, "discoverTab"));
            compare(fakeApps.section, "discover");
            verify(findChild(view, "categories").visible);
        }

        function test_search_filters_through_the_model() {
            keyClick(Qt.Key_F, Qt.ControlModifier);
            tryVerify(() => searchField.activeFocus, 5000, "Ctrl+F focuses the search");
            keyClick("e");
            keyClick("d");
            compare(fakeApps.searchText, "ed");
            keyClick(Qt.Key_Down);
            verify(appList.activeFocus);
        }

        function test_return_opens_the_app_page_and_installs() {
            keyClick(Qt.Key_Return);
            tryVerify(() => appPage.visible, 5000, "the app page is shown");
            verify(!appList.visible);
            compare(findChild(appPage, "appName").text, "Example Editor");
            compare(fakeStore.calls, ["permissions:org.example.Editor"]);
            const install = findChild(appPage, "installButton");
            compare(install.Accessible.name, "Install");
            verify(!findChild(appPage, "openButton").visible);
            verify(!findChild(appPage, "removeButton").visible);
            tryVerify(() => install.activeFocus, 5000, "Install has the focus");
            keyClick(Qt.Key_Return);
            compare(fakeStore.calls, ["permissions:org.example.Editor", "install:org.example.Editor"]);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !appPage.visible && appList.activeFocus, 5000, "Escape returns to the list");
            compare(appList.currentIndex, 0);
        }

        function test_installed_app_offers_open_and_remove() {
            keyClick(Qt.Key_Down);
            compare(appList.currentIndex, 1);
            keyClick(Qt.Key_Return);
            tryVerify(() => appPage.visible, 5000, "the app page is shown");
            const open = findChild(appPage, "openButton");
            const remove = findChild(appPage, "removeButton");
            compare(open.Accessible.name, "Open");
            compare(remove.Accessible.name, "Remove");
            verify(!findChild(appPage, "installButton").visible);
            tryVerify(() => open.activeFocus, 5000, "Open has the focus");
            keyClick(Qt.Key_Space);
            mouseClick(remove);
            compare(fakeStore.calls, ["permissions:org.example.Game", "open:org.example.Game", "remove:org.example.Game"]);
        }

        function test_permissions_are_listed() {
            keyClick(Qt.Key_Return);
            tryVerify(() => appPage.visible, 5000, "the app page is shown");
            fakeStore.permissionsReady("org.example.Other", ["Ignored"]);
            fakeStore.permissionsReady("org.example.Editor", ["Network access", "Your home folder"]);
            const list = findChild(appPage, "permissions");
            compare(list.count, 2);
            compare(findChild(appPage, "permissionsText").visible, false);
            fakeStore.operationFailed("install", "org.example.Editor", "No remote refs found");
            const message = findChild(appPage, "messageLabel");
            compare(message.text, "Could not install Example Editor: No remote refs found");
        }

        function test_busy_disables_install() {
            fakeStore.busy = true;
            keyClick(Qt.Key_Return);
            tryVerify(() => appPage.visible, 5000, "the app page is shown");
            verify(!findChild(appPage, "installButton").enabled);
            fakeStore.busy = false;
            verify(findChild(appPage, "installButton").enabled);
        }
    }
}
