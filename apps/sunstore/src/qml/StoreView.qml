// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import StarOS.Shell

// The Sun Store window content on frosted glass: section tabs and search,
// categories, the apps list, an app page, a status line and the first-run
// consent page. It only talks to `store`, so tests pass a double:
//   store  Store: state, offline, errorString, busy, operation, busyAppId,
//          progressText; apps (AppsModel: rows with appId, name, summary,
//          iconUrl, installed, updateAvailable; section, category,
//          searchText, count, updateCount, app(id), indexOf(id),
//          categoryIds(), categoryName(id)); start(), enableFlathub(),
//          refresh(), updateAll(); install/remove/open/requestPermissions for
//          AppPage; the signals operationFinished and operationFailed.
FocusScope {
    id: root

    required property var store

    readonly property var apps: root.store.apps
    readonly property size windowSize: Qt.size(root.width, root.height)
    readonly property int margin: Theme.spacing
    readonly property bool consent: root.store.state === "needsConsent"
    readonly property bool listed: root.store.state === "ready"
    // The app the page shows; empty shows the list.
    property string openAppId: ""
    property string message: ""
    property bool messageIsError: false

    signal closeRequested()

    readonly property string emptyText: {
        switch (root.store.state) {
        case "starting":
            return qsTr("Starting…");
        case "needsConsent":
            return "";
        case "loading":
            return qsTr("Loading apps from Flathub…");
        case "offline":
            return qsTr("Can't reach Flathub. Check your network connection.");
        case "error":
            return root.store.errorString !== "" ? qsTr("Sun Store cannot use Flatpak: %1").arg(root.store.errorString)
                                                 : qsTr("Sun Store cannot use Flatpak.");
        }
        if (root.apps.searchText.trim() !== "") {
            return qsTr("No apps match “%1”.").arg(root.apps.searchText.trim());
        }
        if (root.apps.section === "installed") {
            return qsTr("No Flatpak apps are installed.");
        }
        if (root.apps.section === "updates") {
            return qsTr("All apps are up to date.");
        }
        return qsTr("No apps in this category.");
    }

    readonly property string statusLine: {
        if (root.message !== "") {
            return root.message;
        }
        if (root.store.busy) {
            return root.store.progressText !== "" ? root.store.progressText : qsTr("Working…");
        }
        if (root.store.offline && root.listed) {
            return qsTr("Can't reach Flathub. Check your network connection. The list is from the last update.");
        }
        if (!root.listed) {
            return "";
        }
        return root.apps.count === 1 ? qsTr("1 app") : qsTr("%1 apps").arg(root.apps.count);
    }

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Sun Store")

    function showMessage(text, isError) {
        root.message = text;
        root.messageIsError = isError;
        statusLabel.Accessible.announce(text);
    }

    function clearMessage() {
        root.message = "";
        root.messageIsError = false;
    }

    function showSection(section) {
        root.clearMessage();
        root.closeApp();
        root.apps.section = section;
        appList.currentIndex = appList.count > 0 ? 0 : -1;
    }

    function openApp(appId) {
        if (appId === "") {
            return;
        }
        root.clearMessage();
        root.openAppId = appId;
        appPage.focusAction();
    }

    function closeApp() {
        if (root.openAppId === "") {
            return;
        }
        const row = root.apps.indexOf(root.openAppId);
        root.openAppId = "";
        if (row >= 0) {
            appList.currentIndex = row;
            appList.positionViewAtIndex(row, ListView.Contain);
        }
        appList.forceActiveFocus(Qt.OtherFocusReason);
    }

    function focusSearch() {
        root.closeApp();
        searchField.forceActiveFocus(Qt.ShortcutFocusReason);
        searchField.selectAll();
    }

    function sectionName(section) {
        if (section === "installed") {
            return qsTr("Installed");
        }
        return section === "updates" ? qsTr("Updates") : qsTr("Discover");
    }

    onConsentChanged: {
        if (root.consent) {
            consentPage.forceActiveFocus(Qt.OtherFocusReason);
        } else {
            appList.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    Connections {
        target: root.store

        function onOperationFinished(operation, appId) {
            if (operation === "update") {
                root.showMessage(qsTr("Apps are up to date."), false);
            }
        }

        function onOperationFailed(operation, appId, message) {
            if (operation === "update") {
                root.showMessage(qsTr("Could not update the apps: %1").arg(message), true);
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+F"
        enabled: !root.consent
        onActivated: root.focusSearch()
    }
    Shortcut {
        sequence: "F5"
        enabled: !root.consent
        onActivated: root.store.refresh()
    }

    // The window background: the wallpaper, frosted.
    GlassSurface {
        anchors.fill: parent
        radius: 0
        wallpaperOrigin: Qt.point(0, 0)
        screenSize: root.windowSize
    }

    GlassSurface {
        id: headerGlass
        x: root.margin
        y: root.margin
        width: root.width - 2 * root.margin
        height: Theme.minTarget + root.margin
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    Item {
        anchors.fill: headerGlass
        anchors.margins: root.margin / 2
        visible: !root.consent

        Row {
            id: sections
            objectName: "sections"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.margin / 2

            Accessible.role: Accessible.PageTabList
            Accessible.name: qsTr("Store sections")

            Repeater {
                model: ["discover", "installed", "updates"]

                StoreButton {
                    id: tab
                    required property string modelData
                    objectName: modelData + "Tab"
                    accessibleRole: Accessible.PageTab
                    accessibleName: root.sectionName(modelData)
                    text: modelData === "updates" && root.apps.updateCount > 0
                          ? qsTr("Updates (%1)").arg(root.apps.updateCount) : root.sectionName(modelData)
                    description: modelData === "updates" && root.apps.updateCount > 0
                                 ? qsTr("%n update(s) available", "", root.apps.updateCount) : ""
                    checked: root.apps.section === modelData
                    onClicked: root.showSection(tab.modelData)
                }
            }
        }

        StoreTextField {
            id: searchField
            objectName: "searchField"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(18 * Theme.gridUnit, parent.width - sections.width - 2 * root.margin)
            placeholderText: qsTr("Search apps")
            Accessible.name: qsTr("Search apps")
            Accessible.description: qsTr("Show only apps whose name or summary contains this text (Ctrl+F)")
            Accessible.searchEdit: true
            // Searching shows the list; the focus stays here.
            onTextChanged: {
                root.apps.searchText = text;
                root.openAppId = "";
                appList.currentIndex = appList.count > 0 ? 0 : -1;
            }
            Keys.onDownPressed: event => {
                appList.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                appList.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                appList.forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                if (searchField.text !== "") {
                    searchField.text = "";
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
        }
    }

    GlassSurface {
        id: statusGlass
        x: root.margin
        y: root.height - height - root.margin
        width: root.width - 2 * root.margin
        height: Theme.minTarget + root.margin
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    Item {
        anchors.fill: statusGlass
        anchors.leftMargin: root.margin
        anchors.rightMargin: root.margin / 2
        visible: !root.consent

        Text {
            id: statusLabel
            objectName: "statusLabel"
            anchors.left: parent.left
            anchors.right: statusButtons.left
            anchors.rightMargin: root.margin
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusLine
            color: root.messageIsError ? Theme.focusRing : Theme.text
            font: Theme.metrics.font
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Row {
            id: statusButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.margin / 2

            StoreButton {
                objectName: "updateAllButton"
                visible: root.listed && root.apps.section === "updates" && root.apps.updateCount > 0
                enabled: !root.store.busy
                text: qsTr("Update all")
                description: qsTr("Update every installed Flatpak app")
                onClicked: {
                    root.clearMessage();
                    root.store.updateAll();
                }
            }

            StoreButton {
                objectName: "retryButton"
                visible: root.store.state === "offline" || root.store.state === "error"
                         || (root.store.offline && root.listed)
                enabled: !root.store.busy
                text: qsTr("Try again")
                description: qsTr("Contact Flathub again (F5)")
                onClicked: {
                    root.clearMessage();
                    if (root.store.state === "error") {
                        root.store.start();
                    } else {
                        root.store.refresh();
                    }
                }
            }
        }
    }

    // Categories, in Discover only.
    GlassSurface {
        id: sidebarGlass
        x: root.margin
        y: headerGlass.y + headerGlass.height + root.margin
        width: root.apps.section === "discover" && root.listed ? Math.round(Math.min(12 * Theme.gridUnit, root.width / 4)) : 0
        height: statusGlass.y - y - root.margin
        visible: width > 0 && !root.consent
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    ListView {
        id: categoryList
        objectName: "categories"
        anchors.fill: sidebarGlass
        anchors.margins: root.margin / 2
        visible: sidebarGlass.visible
        model: [""].concat(root.apps.categoryIds())
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: visible

        Accessible.role: Accessible.List
        Accessible.name: qsTr("Categories")

        delegate: Item {
            id: categoryRow
            required property int index
            required property string modelData
            readonly property string label: modelData === "" ? qsTr("All apps") : root.apps.categoryName(modelData)

            width: categoryList.width
            height: Theme.minTarget

            Accessible.role: Accessible.ListItem
            Accessible.name: categoryRow.label
            Accessible.selectable: true
            Accessible.selected: root.apps.category === categoryRow.modelData

            Rectangle {
                anchors.fill: parent
                radius: Math.round(Theme.spacing / 2)
                color: categoryRow.ListView.isCurrentItem ? Theme.tile : "transparent"
            }

            Rectangle {
                visible: root.apps.category === categoryRow.modelData
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Theme.activeIndicatorHeight
                color: Theme.activeIndicator
            }

            Text {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacing
                anchors.rightMargin: Theme.spacing
                text: categoryRow.label
                color: Theme.text
                font: Theme.metrics.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Accessible.ignored: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    categoryList.currentIndex = categoryRow.index;
                    categoryList.forceActiveFocus(Qt.MouseFocusReason);
                    root.apps.category = categoryRow.modelData;
                }
            }

            FocusFrame {
                visible: categoryRow.activeFocus
            }
        }

        function choose() {
            if (currentItem) {
                root.closeApp();
                root.apps.category = currentItem.modelData;
                appList.currentIndex = appList.count > 0 ? 0 : -1;
            }
        }

        Keys.onReturnPressed: event => {
            choose();
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            choose();
            event.accepted = true;
        }
        Keys.onSpacePressed: event => {
            choose();
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
        x: sidebarGlass.width > 0 ? sidebarGlass.x + sidebarGlass.width + root.margin : root.margin
        y: sidebarGlass.y
        width: root.width - x - root.margin
        height: sidebarGlass.height
        visible: !root.consent
        wallpaperOrigin: Qt.point(x, y)
        screenSize: root.windowSize
    }

    ListView {
        id: appList
        objectName: "appList"
        anchors.fill: contentGlass
        anchors.margins: root.margin / 2
        visible: root.openAppId === "" && !root.consent
        focus: true
        model: root.apps
        clip: true
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: visible

        Accessible.role: Accessible.List
        Accessible.name: qsTr("Apps")
        Accessible.description: count === 0 ? root.emptyText : ""

        delegate: AppRow {
            id: appRow
            width: appList.width
            onClicked: {
                appList.currentIndex = appRow.index;
                appList.forceActiveFocus(Qt.MouseFocusReason);
            }
            onActivated: root.openApp(appRow.appId)
        }

        Keys.onReturnPressed: event => {
            if (currentItem) {
                root.openApp(currentItem.appId);
            }
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            if (currentItem) {
                root.openApp(currentItem.appId);
            }
            event.accepted = true;
        }

        onCountChanged: {
            if (currentIndex < 0 && count > 0) {
                currentIndex = 0;
            }
        }
    }

    // An empty list has no item to carry the focus ring.
    FocusFrame {
        anchors.fill: appList
        visible: appList.visible && appList.activeFocus && appList.count === 0
    }

    Text {
        id: emptyState
        objectName: "emptyState"
        anchors.centerIn: contentGlass
        width: contentGlass.width - 4 * root.margin
        visible: appList.visible && appList.count === 0 && text !== ""
        text: root.emptyText
        color: Theme.text
        font: Theme.metrics.font
        wrapMode: Text.Wrap
        horizontalAlignment: Text.AlignHCenter
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    AppPage {
        id: appPage
        objectName: "appPage"
        anchors.fill: contentGlass
        anchors.margins: root.margin / 2
        visible: root.openAppId !== "" && !root.consent
        store: root.store
        appId: root.openAppId
        onBackRequested: root.closeApp()
    }

    ConsentPage {
        id: consentPage
        objectName: "consentPage"
        anchors.fill: parent
        visible: root.consent
        screenSize: root.windowSize
        onAccepted: root.store.enableFlathub()
        onDeclined: root.closeRequested()
    }

    Component.onCompleted: {
        if (root.consent) {
            consentPage.forceActiveFocus(Qt.OtherFocusReason);
        }
    }
}
