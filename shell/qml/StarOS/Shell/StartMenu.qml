// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import "quickanswers.js" as QuickAnswers

// The start menu (M0.5): it fills a screen-sized overlay, dims the screen
// lightly and shows a glass panel above the taskbar. Clicking outside the
// panel or Escape closes it.
//
// The catalogue is StarOS.System's ApplicationsModel or a test double with:
// model (rows with 'AppName', 'GenericName', 'AppId', 'decoration', 'IsNew'
// and 'Section'), count, a writable 'filter', revision, recentlyInstalled (a
// list of app maps), apps(desktopIds), launch(row) and launchDesktopId(id).
//
// Without search text the panel shows "Pinned" (pinnedIds that are
// installed), "Recently installed" and a button for "All apps"; with text,
// the ranked matches. The search field also answers sums, percentages and
// unit conversions (quickanswers.js; Return copies the answer) and makes
// sticky notes from text that starts with "note:" (Return emits
// noteRequested).
FocusScope {
    id: root

    required property var catalogue
    // Shows an app's own icon when Star OS has no artwork for it (AppIcon).
    property Component iconFallback: null
    property var pinnedIds: []
    property string userName: qsTr("Live user")
    property string userDetail: ""
    // Drives the panel's fade and slide; the host clears it before hiding.
    property bool shown: true
    // For "Installed 2 min ago"; reset() updates it.
    property date now: new Date()
    // "home" or "all"; search text shows the matches whatever the view.
    property string view: "home"

    readonly property var answer: QuickAnswers.evaluate(searchField.text)
    readonly property string noteText: {
        const match = searchField.text.match(/^\s*note:\s*(.*)$/i);
        return match ? match[1].trim() : "";
    }
    readonly property bool isNote: /^\s*note:/i.test(searchField.text)
    readonly property string answerText: root.answer ? root.answer.text : ""
    readonly property bool searching: searchField.text.trim() !== "" && !root.isNote
    readonly property var pinnedApps: root.catalogue && root.catalogue.revision >= 0
        ? root.catalogue.apps(root.pinnedIds).slice(0, 12) : []
    readonly property var recentApps: root.catalogue && root.catalogue.recentlyInstalled
        ? root.catalogue.recentlyInstalled.slice(0, 4) : []

    signal closeRequested()
    signal answerCopied(string text)
    signal noteRequested(string text)
    signal lockRequested()
    signal logoutRequested()
    signal restartRequested()
    signal shutdownRequested()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Application launcher")

    // Called by the host every time the menu is shown.
    function reset() {
        searchField.text = "";
        if (root.catalogue) {
            root.catalogue.filter = "";
        }
        root.view = "home";
        root.now = new Date();
        powerMenu.shown = false;
        results.currentIndex = 0;
        searchField.forceActiveFocus(Qt.OtherFocusReason);
    }

    // Return in the search field: a note, an answer, or the first match.
    function accept() {
        if (root.isNote) {
            if (root.noteText !== "") {
                root.noteRequested(root.noteText);
                root.closeRequested();
            }
            return;
        }
        if (root.answer) {
            clipboard.text = root.answer.text;
            clipboard.selectAll();
            clipboard.copy();
            root.answerCopied(root.answer.text);
            root.closeRequested();
            return;
        }
        if (root.searching) {
            root.launchRow(0);
        }
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

    function launchApp(appId) {
        if (root.catalogue && root.catalogue.launchDesktopId(appId)) {
            root.closeRequested();
            return true;
        }
        return false;
    }

    function showView(name) {
        root.view = name;
        if (name === "all") {
            allApps.positionViewAtBeginning();
            allApps.currentIndex = 0;
            allApps.forceActiveFocus(Qt.TabFocusReason);
        } else {
            searchField.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    // "Installed 5 min ago · Flatpak" for an app map.
    function installedDetail(app) {
        const when = app.InstalledAt instanceof Date ? app.InstalledAt : new Date(app.InstalledAt);
        const minutes = Math.max(0, Math.round((root.now.getTime() - when.getTime()) / 60000));
        let ago;
        if (!isFinite(minutes)) {
            ago = qsTr("Installed");
        } else if (minutes < 1) {
            ago = qsTr("Installed just now");
        } else if (minutes < 60) {
            ago = qsTr("Installed %n min ago", "", minutes);
        } else if (minutes < 24 * 60) {
            ago = qsTr("Installed %n h ago", "", Math.round(minutes / 60));
        } else {
            ago = qsTr("Installed %n days ago", "", Math.round(minutes / (24 * 60)));
        }
        const source = app.Source === "flatpak" ? qsTr("Flatpak") : app.Source === "user" ? qsTr("Your apps") : "";
        return source !== "" ? ago + " · " + source : ago;
    }

    function isPrintable(event) {
        const blocked = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier;
        return event.text.length > 0 && event.text.charCodeAt(0) >= 0x20
            && event.text.charCodeAt(0) !== 0x7f && (event.modifiers & blocked) === 0;
    }

    // Typing anywhere continues the search; Escape steps back, then closes.
    Keys.onPressed: event => {
        if (root.isPrintable(event) && !searchField.activeFocus) {
            searchField.text += event.text;
            searchField.forceActiveFocus(Qt.OtherFocusReason);
            event.accepted = true;
        }
    }
    Keys.onEscapePressed: event => {
        if (powerMenu.shown) {
            powerMenu.shown = false;
            powerButton.forceActiveFocus(Qt.OtherFocusReason);
        } else if (searchField.text !== "") {
            searchField.text = "";
            searchField.forceActiveFocus(Qt.OtherFocusReason);
        } else if (root.view !== "home") {
            root.showView("home");
        } else {
            root.closeRequested();
        }
        event.accepted = true;
    }

    // The light dim; a click outside the panel closes the menu.
    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.shown ? 1 : 0
        Accessible.ignored: true

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durationMedium
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    // Copies answers to the clipboard; never shown.
    TextInput {
        id: clipboard
        visible: false
        Accessible.ignored: true
    }

    GlassPanel {
        id: panel
        objectName: "panel"
        width: Math.min(Theme.startMenuWidth, root.width - 2 * Theme.spacing)
        height: Math.min(34 * Theme.gridUnit, panel.availableHeight)
        x: Math.round((root.width - panel.width) / 2)
        y: Math.round(panel.bottomEdge - panel.height)
        shown: root.shown
        wallpaperOrigin: Qt.point(panel.x, panel.y)
        screenSize: Qt.size(root.width, root.height)

        readonly property real bottomEdge: root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap
        readonly property real availableHeight: Math.max(10 * Theme.gridUnit, bottomEdge - Theme.popupGap)
        readonly property real contentWidth: panel.width - 2 * Theme.panelPadding

        // Clicks on the panel itself stay in the menu.
        MouseArea {
            anchors.fill: parent
            onClicked: powerMenu.shown = false
        }

        T.TextField {
            id: searchField
            objectName: "searchField"
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: panel.contentWidth
            height: Theme.searchHeight
            focus: true
            leftPadding: Theme.symbolSize + 2 * Theme.spacing
            rightPadding: Theme.spacing * 2
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font: Theme.metrics.font
            placeholderText: qsTr("Search apps, or type 12*3, 20% of 80, note: …")
            placeholderTextColor: Theme.placeholder
            selectByMouse: true

            Accessible.name: qsTr("Search applications")
            Accessible.description: root.answer ? qsTr("Answer: %1. Press Return to copy it.").arg(root.answerText)
                                                : root.isNote ? qsTr("Press Return to put this on a sticky note.")
                                                              : ""

            background: Rectangle {
                radius: height / 2
                color: Theme.glassButton
                border.width: 1
                border.color: searchField.activeFocus ? Theme.activeIndicator : Theme.glassBorder

                Symbol {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacing * 1.25
                    anchors.verticalCenter: parent.verticalCenter
                    name: "search"
                    opacity: 0.75
                }
            }

            onTextChanged: {
                if (root.catalogue) {
                    root.catalogue.filter = root.searching ? searchField.text : "";
                }
                results.currentIndex = 0;
            }

            Keys.onDownPressed: event => {
                if (root.searching) {
                    if (results.count > 0) {
                        results.forceActiveFocus(Qt.TabFocusReason);
                    }
                } else if (root.view === "all") {
                    allApps.forceActiveFocus(Qt.TabFocusReason);
                } else if (pinned.count > 0) {
                    pinned.forceActiveFocus(Qt.TabFocusReason);
                } else if (recent.count > 0) {
                    recent.forceActiveFocus(Qt.TabFocusReason);
                }
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                root.accept();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.accept();
                event.accepted = true;
            }

            FocusFrame {
                visible: searchField.activeFocus
                radius: searchField.height / 2
            }
        }

        // The answer or the note to be, under the search field.
        Rectangle {
            id: answerCard
            objectName: "answerCard"
            x: Theme.panelPadding
            anchors.top: searchField.bottom
            anchors.topMargin: Theme.spacing
            width: panel.contentWidth
            height: visible ? answerLabel.implicitHeight + 2 * Theme.spacing : 0
            visible: root.answer !== null || root.isNote
            radius: Theme.controlRadius
            color: Theme.tileGlass
            border.width: 1
            border.color: Theme.glassBorder

            Text {
                id: answerLabel
                objectName: "answerLabel"
                anchors.fill: parent
                anchors.margins: Theme.spacing
                text: root.answer ? "= " + root.answerText
                                  : root.noteText !== "" ? qsTr("New sticky note: %1").arg(root.noteText)
                                                         : qsTr("Type the note after “note:”")
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: root.answer ? Theme.titlePixelSize : Math.round(Theme.fontSize)
                font.weight: root.answer ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                Accessible.role: Accessible.StaticText
                Accessible.name: root.answer ? qsTr("Answer: %1").arg(root.answerText) : text
            }
        }

        // The middle: home, all apps or the matches.
        Item {
            id: middle
            x: Theme.panelPadding
            anchors.top: answerCard.visible ? answerCard.bottom : searchField.bottom
            anchors.topMargin: Theme.panelPadding
            anchors.bottom: footer.top
            anchors.bottomMargin: Theme.spacing
            width: panel.contentWidth
            clip: true

            // Home: pinned apps, then the recently installed ones if they fit.
            Item {
                id: home
                objectName: "home"
                anchors.fill: parent
                visible: !root.searching && !answerCard.visible && root.view === "home"

                readonly property real headerHeight: Math.max(allAppsButton.height, pinnedHeading.implicitHeight)
                readonly property bool recentFits: home.height >= pinnedHeader.height + pinned.height
                    + 2 * Theme.panelPadding + home.headerHeight + 2 * Theme.rowHeight

                Item {
                    id: pinnedHeader
                    width: parent.width
                    height: home.headerHeight

                    Text {
                        id: pinnedHeading
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Pinned")
                        color: Theme.text
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Math.round(Theme.fontSize)
                        font.weight: Font.DemiBold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ShellButton {
                        id: allAppsButton
                        objectName: "allAppsButton"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.round(1.7 * Theme.gridUnit)
                        radius: height / 2
                        text: qsTr("All apps")
                        description: qsTr("Every installed app, from A to Z")
                        symbol: "chevron-right"
                        onClicked: root.showView("all")
                    }
                }

                GridView {
                    id: pinned
                    objectName: "pinned"
                    anchors.top: pinnedHeader.bottom
                    anchors.topMargin: Theme.spacing / 2
                    width: parent.width
                    height: Math.min(Math.ceil(count / columns) * cellHeight,
                                     Math.max(cellHeight, home.height - pinnedHeader.height - Theme.spacing / 2))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: Theme.tileHeight
                    clip: true
                    model: root.pinnedApps
                    keyNavigationEnabled: true
                    highlightMoveDuration: 0
                    activeFocusOnTab: count > 0
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    readonly property int columns: Math.max(1, Math.floor(width / Theme.tileWidth))

                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Pinned")

                    delegate: FocusScope {
                        id: pinnedCell

                        required property var modelData
                        required property int index

                        width: pinned.cellWidth
                        height: pinned.cellHeight

                        focus: pinnedCell.GridView.isCurrentItem

                        LauncherTile {
                            objectName: "tile"
                            anchors.centerIn: parent
                            width: Math.min(Theme.tileWidth, pinned.cellWidth)
                            height: Theme.tileHeight
                            focus: true
                            appName: pinnedCell.modelData.AppName ?? ""
                            genericName: pinnedCell.modelData.GenericName ?? ""
                            appId: pinnedCell.modelData.AppId ?? ""
                            iconData: pinnedCell.modelData.decoration
                            iconFallback: root.iconFallback
                            onClicked: {
                                pinned.currentIndex = pinnedCell.index;
                                root.launchApp(pinnedCell.modelData.AppId);
                            }
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
                    Keys.onDownPressed: event => {
                        if (currentIndex + columns >= count && recent.visible && recent.count > 0) {
                            recent.forceActiveFocus(Qt.TabFocusReason);
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }

                Item {
                    id: recentHeader
                    anchors.top: pinned.bottom
                    anchors.topMargin: Theme.panelPadding
                    width: parent.width
                    height: home.headerHeight
                    visible: home.recentFits

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacing / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Recently installed")
                        color: Theme.text
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Math.round(Theme.fontSize)
                        font.weight: Font.DemiBold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    ShellButton {
                        objectName: "storeButton"
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.round(1.7 * Theme.gridUnit)
                        radius: height / 2
                        text: qsTr("Sun Store")
                        description: qsTr("Get more apps")
                        symbol: "chevron-right"
                        onClicked: root.launchApp("org.staros.sunstore.desktop")
                    }
                }

                GridView {
                    id: recent
                    objectName: "recent"
                    anchors.top: recentHeader.bottom
                    anchors.topMargin: Theme.spacing / 2
                    width: parent.width
                    height: 2 * cellHeight
                    visible: home.recentFits && count > 0
                    cellWidth: Math.floor(width / 2)
                    cellHeight: Theme.rowHeight
                    interactive: false
                    model: root.recentApps
                    keyNavigationEnabled: true
                    highlightMoveDuration: 0
                    activeFocusOnTab: count > 0

                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Recently installed")

                    delegate: AppRow {
                        id: recentRow

                        required property var modelData
                        required property int index

                        width: recent.cellWidth - Theme.spacing / 2
                        height: recent.cellHeight
                        focus: recentRow.GridView.isCurrentItem
                        appName: recentRow.modelData.AppName ?? ""
                        appId: recentRow.modelData.AppId ?? ""
                        iconData: recentRow.modelData.decoration
                        iconFallback: root.iconFallback
                        isNew: recentRow.modelData.IsNew === true
                        detail: root.installedDetail(recentRow.modelData)
                        onClicked: {
                            recent.currentIndex = recentRow.index;
                            root.launchApp(recentRow.modelData.AppId);
                        }
                    }

                    Keys.onUpPressed: event => {
                        if (currentIndex < 2) {
                            if (pinned.count > 0) {
                                pinned.forceActiveFocus(Qt.BacktabFocusReason);
                            } else {
                                searchField.forceActiveFocus(Qt.BacktabFocusReason);
                            }
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }

                Text {
                    objectName: "recentHint"
                    anchors.top: recentHeader.bottom
                    anchors.topMargin: Theme.spacing
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacing / 2
                    width: parent.width - Theme.spacing
                    visible: home.recentFits && recent.count === 0
                    text: qsTr("Apps you install from Sun Store appear here.")
                    color: Theme.textSecondary
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.smallPixelSize
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            // Every app, A to Z, with letter headings.
            Item {
                id: all
                objectName: "allAppsView"
                anchors.fill: parent
                visible: !root.searching && !answerCard.visible && root.view === "all"

                Item {
                    id: allHeader
                    width: parent.width
                    height: home.headerHeight

                    ShellButton {
                        objectName: "backButton"
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.round(1.7 * Theme.gridUnit)
                        radius: height / 2
                        text: qsTr("Back")
                        symbol: "chevron-left"
                        onClicked: root.showView("home")
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacing / 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("All apps")
                        color: Theme.text
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Math.round(Theme.fontSize)
                        font.weight: Font.DemiBold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }
                }

                ListView {
                    id: allApps
                    objectName: "allApps"
                    anchors.top: allHeader.bottom
                    anchors.topMargin: Theme.spacing / 2
                    anchors.bottom: parent.bottom
                    width: parent.width
                    clip: true
                    model: all.visible && root.catalogue ? root.catalogue.model : null
                    keyNavigationEnabled: true
                    highlightMoveDuration: 0
                    activeFocusOnTab: all.visible && count > 0
                    boundsBehavior: Flickable.StopAtBounds

                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("All apps")

                    section.property: "Section"
                    section.delegate: Text {
                        required property string section

                        width: allApps.width
                        height: implicitHeight + Theme.spacing
                        leftPadding: Theme.spacing
                        topPadding: Theme.spacing / 2
                        text: section
                        color: Theme.activeIndicator
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Theme.smallPixelSize
                        font.weight: Font.Bold
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    delegate: AppRow {
                        id: allRow

                        required property var model
                        required property int index

                        width: allApps.width
                        focus: allRow.ListView.isCurrentItem
                        appName: allRow.model.AppName ?? ""
                        appId: allRow.model.AppId ?? ""
                        iconData: allRow.model.decoration
                        iconFallback: root.iconFallback
                        isNew: allRow.model.IsNew === true
                        detail: allRow.model.GenericName ?? ""
                        onClicked: {
                            allApps.currentIndex = allRow.index;
                            root.launchRow(allRow.index);
                        }
                    }

                    Keys.onUpPressed: event => {
                        if (currentIndex === 0) {
                            searchField.forceActiveFocus(Qt.BacktabFocusReason);
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }
            }

            // The matches for the search text.
            Item {
                id: matches
                objectName: "results"
                anchors.fill: parent
                visible: root.searching && !answerCard.visible

                ListView {
                    id: results
                    objectName: "appGrid"
                    anchors.fill: parent
                    clip: true
                    model: matches.visible && root.catalogue ? root.catalogue.model : null
                    keyNavigationEnabled: true
                    highlightMoveDuration: 0
                    activeFocusOnTab: matches.visible && count > 0
                    boundsBehavior: Flickable.StopAtBounds

                    Accessible.role: Accessible.List
                    Accessible.name: qsTr("Applications")

                    delegate: AppRow {
                        id: resultRow

                        required property var model
                        required property int index

                        width: results.width
                        focus: resultRow.ListView.isCurrentItem
                        appName: resultRow.model.AppName ?? ""
                        appId: resultRow.model.AppId ?? ""
                        iconData: resultRow.model.decoration
                        iconFallback: root.iconFallback
                        isNew: resultRow.model.IsNew === true
                        detail: resultRow.model.GenericName ?? ""
                        onClicked: {
                            results.currentIndex = resultRow.index;
                            root.launchRow(resultRow.index);
                        }
                    }

                    Keys.onUpPressed: event => {
                        if (currentIndex === 0) {
                            searchField.forceActiveFocus(Qt.BacktabFocusReason);
                            event.accepted = true;
                        } else {
                            event.accepted = false;
                        }
                    }
                }

                Text {
                    objectName: "emptyState"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Theme.panelPadding
                    visible: results.count === 0
                    text: qsTr("No applications match")
                    color: Theme.textSecondary
                    font: Theme.metrics.font
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }
        }

        // The person, Lock, Settings and Power.
        Rectangle {
            id: footer
            objectName: "footer"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.round(3.75 * Theme.gridUnit)
            bottomLeftRadius: panel.radius
            bottomRightRadius: panel.radius
            color: "#1f000010"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.glassBorder
            }

            Rectangle {
                id: avatar
                anchors.left: parent.left
                anchors.leftMargin: Theme.panelPadding
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(1.9 * Theme.gridUnit)
                height: width
                radius: width / 2
                gradient: Theme.accentGradient

                Symbol {
                    anchors.centerIn: parent
                    name: "user"
                }
            }

            Column {
                anchors.left: avatar.right
                anchors.leftMargin: Theme.spacing
                anchors.right: footerButtons.left
                anchors.rightMargin: Theme.spacing
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: root.userName
                    color: Theme.text
                    font: Theme.metrics.font
                    elide: Text.ElideRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.userDetail
                    color: Theme.textTertiary
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.smallPixelSize
                    elide: Text.ElideRight
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            Row {
                id: footerButtons
                anchors.right: parent.right
                anchors.rightMargin: Theme.panelPadding - Theme.spacing / 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(Theme.spacing / 3)

                ShellButton {
                    objectName: "lockButton"
                    flat: true
                    iconOnly: true
                    symbol: "lock"
                    text: qsTr("Lock")
                    description: qsTr("Lock the screen")
                    onClicked: root.lockRequested()
                }

                ShellButton {
                    objectName: "settingsButton"
                    flat: true
                    iconOnly: true
                    symbol: "settings"
                    text: qsTr("Settings")
                    description: qsTr("Open System Settings")
                    onClicked: root.launchApp("systemsettings.desktop")
                }

                ShellButton {
                    id: powerButton
                    objectName: "powerButton"
                    flat: true
                    iconOnly: true
                    symbol: "power"
                    text: qsTr("Power")
                    description: qsTr("Log out, restart or shut down")
                    checked: powerMenu.shown
                    onClicked: {
                        powerMenu.shown = !powerMenu.shown;
                        if (powerMenu.shown) {
                            lockItem.forceActiveFocus(Qt.TabFocusReason);
                        }
                    }
                }
            }
        }

        // Log out, restart and shut down, above the Power button.
        GlassPanel {
            id: powerMenu
            objectName: "powerMenu"
            shown: false
            width: Math.round(11 * Theme.gridUnit)
            height: powerItems.implicitHeight + Theme.spacing
            x: Math.min(panel.width - width - Theme.spacing,
                        footer.x + footerButtons.x + powerButton.x + powerButton.width - width)
            y: footer.y - height - Theme.spacing / 2
            radius: Theme.controlRadius * 1.5
            wallpaperOrigin: Qt.point(panel.x + powerMenu.x, panel.y + powerMenu.y)
            screenSize: Qt.size(root.width, root.height)

            Accessible.role: Accessible.PopupMenu
            Accessible.name: qsTr("Power")

            Column {
                id: powerItems
                anchors.centerIn: parent
                width: parent.width - Theme.spacing
                spacing: 2

                ShellButton {
                    id: lockItem
                    width: parent.width
                    flat: true
                    horizontalAlignment: Qt.AlignLeft
                    symbol: "lock"
                    text: qsTr("Lock")
                    enabled: powerMenu.shown
                    KeyNavigation.down: logoutItem
                    onClicked: root.lockRequested()
                }

                ShellButton {
                    id: logoutItem
                    width: parent.width
                    flat: true
                    horizontalAlignment: Qt.AlignLeft
                    symbol: "logout"
                    text: qsTr("Log out")
                    enabled: powerMenu.shown
                    KeyNavigation.up: lockItem
                    KeyNavigation.down: restartItem
                    onClicked: root.logoutRequested()
                }

                ShellButton {
                    id: restartItem
                    width: parent.width
                    flat: true
                    horizontalAlignment: Qt.AlignLeft
                    symbol: "restart"
                    text: qsTr("Restart")
                    enabled: powerMenu.shown
                    KeyNavigation.up: logoutItem
                    KeyNavigation.down: shutdownItem
                    onClicked: root.restartRequested()
                }

                ShellButton {
                    id: shutdownItem
                    width: parent.width
                    flat: true
                    horizontalAlignment: Qt.AlignLeft
                    symbol: "power"
                    text: qsTr("Shut down")
                    enabled: powerMenu.shown
                    KeyNavigation.up: restartItem
                    onClicked: root.shutdownRequested()
                }
            }
        }
    }
}
