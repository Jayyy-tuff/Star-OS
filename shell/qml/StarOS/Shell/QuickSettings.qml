// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import "status.js" as Status

// Quick settings (M0.5): it fills a screen-sized overlay, dims the screen
// lightly and shows a glass panel above the tray, its right edge at
// 'anchorRight' (the taskbar's right end). Clicking outside or Escape closes
// it. Tiles for the network, night light, Do not disturb, game mode, the
// clipboard and Star Lens; volume and brightness sliders; where changes are
// kept; Settings and Power. The network tile opens a page with the Wi-Fi
// networks and asks for a passphrase when Wi-Fi needs one.
//
// The objects are StarOS.System's (or test doubles with the same members):
//   audio    available, volume (percent, writable), muted, toggleMute()
//   display  brightnessAvailable, brightness (writable), nightLightAvailable,
//            nightLight (writable)
//   network  state, kind, networkName, wifiAvailable, wifiEnabled, scanning,
//            wifiNetworks, setWifiEnabled(on), scan(), connectTo(path),
//            disconnectWifi(), submitPassphrase(text), cancelPassphrase(),
//            and the signals passphraseRequested(networkName),
//            passphraseDone() and connectFailed(networkName, error)
//   status   SystemStatus (storageMode, storageFree, storageTotal, battery)
// Any of them may be null; their parts are then left out.
FocusScope {
    id: root

    property var audio: null
    property var display: null
    property var network: null
    property var status: null
    property bool doNotDisturb: false
    property bool gameModeAvailable: false
    property bool gameMode: false
    // Copies kept by the clipboard history; -1 leaves the tile out.
    property int clipboardCount: -1
    // The taskbar's right end, in this item's coordinates.
    property real anchorRight: root.width - Theme.spacing
    property bool shown: true
    // "main" or "network".
    property string page: "main"
    property string passphraseFor: ""
    property string networkError: ""

    signal closeRequested()
    signal doNotDisturbToggled()
    signal gameModeToggled()
    signal clipboardRequested()
    signal lensRequested()
    signal storageRequested()
    signal settingsRequested()
    signal powerRequested()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Quick settings")

    // Called by the host every time the panel is shown.
    function reset() {
        root.page = "main";
        root.passphraseFor = "";
        root.networkError = "";
        networkTile.forceActiveFocus(Qt.OtherFocusReason);
    }

    function showNetworkPage() {
        root.page = "network";
        root.networkError = "";
        if (root.network && root.network.wifiAvailable && root.network.wifiEnabled) {
            root.network.scan();
        }
        backButton.forceActiveFocus(Qt.OtherFocusReason);
    }

    function showMainPage() {
        if (root.passphraseFor !== "" && root.network) {
            root.network.cancelPassphrase();
        }
        root.passphraseFor = "";
        root.page = "main";
        networkTile.forceActiveFocus(Qt.OtherFocusReason);
    }

    Keys.onEscapePressed: event => {
        if (root.passphraseFor !== "") {
            root.network.cancelPassphrase();
            root.passphraseFor = "";
        } else if (root.page !== "main") {
            root.showMainPage();
        } else {
            root.closeRequested();
        }
        event.accepted = true;
    }

    Connections {
        target: root.network
        ignoreUnknownSignals: true

        function onPassphraseRequested(networkName) {
            root.page = "network";
            root.passphraseFor = networkName;
            passphraseField.text = "";
            passphraseField.forceActiveFocus(Qt.OtherFocusReason);
        }
        function onPassphraseDone() {
            root.passphraseFor = "";
        }
        function onConnectFailed(networkName, error) {
            root.networkError = qsTr("Could not connect to %1: %2").arg(networkName).arg(error);
        }
    }

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

    GlassPanel {
        id: panel
        objectName: "panel"
        width: Math.min(Theme.trayPanelWidth, root.width - 2 * Theme.spacing)
        height: Math.min(panel.contentHeight, panel.bottomEdge - Theme.popupGap)
        x: Math.max(Theme.spacing, Math.min(root.width - Theme.spacing, root.anchorRight) - panel.width)
        y: Math.round(panel.bottomEdge - panel.height)
        shown: root.shown
        wallpaperOrigin: Qt.point(panel.x, panel.y)
        screenSize: Qt.size(root.width, root.height)

        readonly property real bottomEdge: root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap
        readonly property real innerWidth: panel.width - 2 * Theme.panelPadding
        readonly property real contentHeight: 2 * Theme.panelPadding
            + (root.page === "main" ? mainPage.implicitHeight : networkPage.implicitHeight)

        MouseArea {
            anchors.fill: parent
        }

        // Tiles, sliders and the footer.
        Column {
            id: mainPage
            objectName: "mainPage"
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: panel.innerWidth
            spacing: Theme.spacing
            visible: root.page === "main"

            Grid {
                id: tiles
                columns: 2
                width: parent.width
                columnSpacing: Theme.spacing
                rowSpacing: Theme.spacing

                readonly property real tileWidth: (width - columnSpacing) / 2

                QuickToggle {
                    id: networkTile
                    objectName: "networkTile"
                    width: tiles.tileWidth
                    text: root.network && root.network.kind === "wifi" ? qsTr("Wi-Fi") : qsTr("Network")
                    symbol: Status.networkSymbol(root.network)
                    stateText: Status.networkText(root.network)
                    checked: root.network !== null && root.network.state === "connected"
                    visible: root.network !== null
                    KeyNavigation.right: nightTile
                    onClicked: root.showNetworkPage()
                }

                QuickToggle {
                    id: nightTile
                    objectName: "nightLightTile"
                    width: tiles.tileWidth
                    isSwitch: true
                    text: qsTr("Night light")
                    symbol: "night"
                    stateText: !root.display || !root.display.nightLightAvailable ? qsTr("Not available")
                        : root.display.nightLight ? qsTr("On") : qsTr("Off")
                    checked: root.display !== null && root.display.nightLight
                    enabled: root.display !== null && root.display.nightLightAvailable
                    visible: root.display !== null
                    onClicked: root.display.nightLight = !root.display.nightLight
                }

                QuickToggle {
                    objectName: "doNotDisturbTile"
                    width: tiles.tileWidth
                    isSwitch: true
                    text: qsTr("Do not disturb")
                    symbol: root.doNotDisturb ? "bell-off" : "bell"
                    stateText: root.doNotDisturb ? qsTr("On") : qsTr("Off")
                    checked: root.doNotDisturb
                    onClicked: root.doNotDisturbToggled()
                }

                QuickToggle {
                    objectName: "gameModeTile"
                    width: tiles.tileWidth
                    isSwitch: true
                    text: qsTr("Game mode")
                    symbol: "gamepad"
                    stateText: root.gameMode ? qsTr("On") : qsTr("Off")
                    checked: root.gameMode
                    visible: root.gameModeAvailable
                    onClicked: root.gameModeToggled()
                }

                QuickToggle {
                    objectName: "clipboardTile"
                    width: tiles.tileWidth
                    text: qsTr("Clipboard")
                    symbol: "clipboard"
                    stateText: root.clipboardCount === 1 ? qsTr("1 item") : qsTr("%1 items").arg(Math.max(0, root.clipboardCount))
                    visible: root.clipboardCount >= 0
                    onClicked: root.clipboardRequested()
                }

                QuickToggle {
                    objectName: "lensTile"
                    width: tiles.tileWidth
                    text: qsTr("Star Lens")
                    symbol: "screenshot"
                    stateText: qsTr("Meta+Shift+L")
                    onClicked: root.lensRequested()
                }
            }

            QuickSlider {
                id: volumeSlider
                objectName: "volumeSlider"
                width: parent.width
                text: qsTr("Volume")
                symbol: Status.volumeSymbol(root.audio)
                symbolText: root.audio && root.audio.muted ? qsTr("Unmute") : qsTr("Mute")
                symbolClickable: root.audio !== null && root.audio.available
                value: root.audio ? root.audio.volume : 0
                enabled: root.audio !== null && root.audio.available
                visible: root.audio !== null
                onMoved: value => {
                    root.audio.volume = value;
                }
                onSymbolClicked: root.audio.toggleMute()
            }

            Text {
                objectName: "noAudio"
                width: parent.width
                visible: root.audio !== null && !root.audio.available
                text: qsTr("No sound output found.")
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            QuickSlider {
                objectName: "brightnessSlider"
                width: parent.width
                text: qsTr("Brightness")
                symbol: "brightness"
                value: root.display ? root.display.brightness : 0
                visible: root.display !== null && root.display.brightnessAvailable
                onMoved: value => {
                    root.display.brightness = value;
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.glassBorder
            }

            Item {
                width: parent.width
                height: Theme.minTarget

                ShellButton {
                    id: storageButton
                    objectName: "storageButton"
                    anchors.left: parent.left
                    anchors.right: footerButtons.left
                    anchors.rightMargin: Theme.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    flat: true
                    horizontalAlignment: Qt.AlignLeft
                    symbol: "disk"
                    text: !root.status ? qsTr("Storage")
                        : root.status.storageMode === "live" ? qsTr("Live session · %1 free").arg(Status.formatBytes(Status.value(root.status, "storageFree")))
                        : root.status.storageMode === "star-storage" ? qsTr("Star Storage · %1 free").arg(Status.formatBytes(Status.value(root.status, "storageFree")))
                        : qsTr("%1 free").arg(Status.formatBytes(Status.value(root.status, "storageFree")))
                    description: Status.summary(root.status)
                    onClicked: root.storageRequested()
                }

                Row {
                    id: footerButtons
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(Theme.spacing / 3)

                    Text {
                        objectName: "battery"
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.status !== null && root.status.batteryPresent === true
                        rightPadding: Theme.spacing / 2
                        text: root.status ? Math.round(Status.value(root.status, "batteryPercent")) + " %" : ""
                        color: Theme.textSecondary
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Theme.smallPixelSize
                        Accessible.role: Accessible.StaticText
                        Accessible.name: Status.batteryLine(root.status)
                    }

                    ShellButton {
                        objectName: "settingsButton"
                        flat: true
                        iconOnly: true
                        symbol: "settings"
                        text: qsTr("Settings")
                        description: qsTr("Open System Settings")
                        onClicked: root.settingsRequested()
                    }

                    ShellButton {
                        objectName: "powerButton"
                        flat: true
                        iconOnly: true
                        symbol: "power"
                        text: qsTr("Power")
                        description: qsTr("Log out, restart or shut down")
                        onClicked: root.powerRequested()
                    }
                }
            }
        }

        // The network: its state, Wi-Fi on or off, the networks.
        Column {
            id: networkPage
            objectName: "networkPage"
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: panel.innerWidth
            spacing: Theme.spacing
            visible: root.page === "network"

            Item {
                width: parent.width
                height: Theme.minTarget

                ShellButton {
                    id: backButton
                    objectName: "backButton"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(1.7 * Theme.gridUnit)
                    radius: height / 2
                    text: qsTr("Back")
                    symbol: "chevron-left"
                    onClicked: root.showMainPage()
                }

                T.Switch {
                    id: wifiSwitch
                    objectName: "wifiSwitch"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: switchTrack.width + switchLabel.implicitWidth + Theme.spacing
                    implicitHeight: Theme.minTarget
                    visible: root.network !== null && root.network.wifiAvailable
                    checked: root.network !== null && root.network.wifiEnabled
                    text: qsTr("Wi-Fi")
                    focusPolicy: Qt.StrongFocus

                    Accessible.role: Accessible.CheckBox
                    Accessible.name: qsTr("Wi-Fi")
                    Accessible.checked: wifiSwitch.checked

                    onToggled: root.network.setWifiEnabled(wifiSwitch.checked)

                    indicator: Rectangle {
                        id: switchTrack
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(2.2 * Theme.gridUnit)
                        height: Math.round(1.2 * Theme.gridUnit)
                        radius: height / 2
                        color: wifiSwitch.checked ? Theme.accent : Theme.glassButtonActive
                        border.width: wifiSwitch.activeFocus ? Theme.focusRingWidth : 0
                        border.color: Theme.focusRing

                        Rectangle {
                            x: wifiSwitch.checked ? parent.width - width - 3 : 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.height - 6
                            height: width
                            radius: width / 2
                            color: Theme.text

                            Behavior on x {
                                NumberAnimation {
                                    duration: Theme.durationShort
                                }
                            }
                        }
                    }

                    contentItem: Text {
                        id: switchLabel
                        rightPadding: switchTrack.width + Theme.spacing
                        text: wifiSwitch.text
                        color: Theme.text
                        font: Theme.metrics.font
                        verticalAlignment: Text.AlignVCenter
                        Accessible.ignored: true
                    }
                }
            }

            Text {
                objectName: "networkState"
                width: parent.width
                text: !root.network ? ""
                    : root.network.kind === "wired" && root.network.state !== "offline"
                        ? qsTr("Wired network: %1").arg(Status.networkText(root.network))
                        : Status.networkText(root.network)
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize)
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Text {
                objectName: "networkError"
                width: parent.width
                visible: root.networkError !== ""
                text: root.networkError
                color: Theme.focusRing
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            // The passphrase iwd asked for.
            Column {
                objectName: "passphrase"
                width: parent.width
                spacing: Theme.spacing / 2
                visible: root.passphraseFor !== ""

                Text {
                    width: parent.width
                    text: qsTr("Password for “%1”").arg(root.passphraseFor)
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                T.TextField {
                    id: passphraseField
                    objectName: "passphraseField"
                    width: parent.width
                    height: Theme.searchHeight
                    leftPadding: Theme.spacing
                    rightPadding: Theme.spacing
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Theme.text
                    font: Theme.metrics.font
                    Accessible.name: qsTr("Wi-Fi password")

                    background: Rectangle {
                        radius: Theme.controlRadius
                        color: Theme.glassButton
                        border.width: 1
                        border.color: passphraseField.activeFocus ? Theme.activeIndicator : Theme.glassBorder
                    }

                    Keys.onReturnPressed: event => {
                        connectButton.clicked();
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        connectButton.clicked();
                        event.accepted = true;
                    }

                    FocusFrame {
                        visible: passphraseField.activeFocus
                        radius: Theme.controlRadius
                    }
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.spacing / 2

                    ShellButton {
                        objectName: "cancelPassphraseButton"
                        text: qsTr("Cancel")
                        onClicked: {
                            root.network.cancelPassphrase();
                            root.passphraseFor = "";
                        }
                    }

                    ShellButton {
                        id: connectButton
                        objectName: "connectButton"
                        highlighted: true
                        text: qsTr("Connect")
                        enabled: passphraseField.text.length >= 8
                        onClicked: {
                            if (connectButton.enabled) {
                                root.network.submitPassphrase(passphraseField.text);
                                passphraseField.text = "";
                                root.passphraseFor = "";
                            }
                        }
                    }
                }
            }

            ListView {
                id: wifiList
                objectName: "wifiNetworks"
                width: parent.width
                height: Math.min(contentHeight, 6 * Theme.rowHeight)
                implicitHeight: height
                clip: true
                visible: root.network !== null && root.network.wifiAvailable && root.network.wifiEnabled
                model: visible ? root.network.wifiNetworks : []
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                activeFocusOnTab: count > 0
                boundsBehavior: Flickable.StopAtBounds

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Wi-Fi networks")

                delegate: T.AbstractButton {
                    id: networkRow

                    required property var modelData
                    required property int index

                    width: wifiList.width
                    height: Theme.rowHeight
                    focus: networkRow.ListView.isCurrentItem
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true
                    text: networkRow.modelData.name ?? ""

                    Accessible.role: Accessible.Button
                    Accessible.name: networkRow.text
                    Accessible.description: [
                        networkRow.modelData.connected ? qsTr("Connected") : "",
                        networkRow.modelData.secured ? qsTr("Secured") : qsTr("Open"),
                        qsTr("Signal %1 of 4").arg(networkRow.modelData.strength ?? 0)
                    ].filter(part => part !== "").join(", ")

                    Keys.onReturnPressed: event => {
                        networkRow.clicked();
                        event.accepted = true;
                    }

                    onClicked: {
                        wifiList.currentIndex = networkRow.index;
                        root.networkError = "";
                        if (networkRow.modelData.connected) {
                            root.network.disconnectWifi();
                        } else {
                            root.network.connectTo(networkRow.modelData.path);
                        }
                    }

                    background: Rectangle {
                        radius: Theme.controlRadius
                        color: networkRow.down ? Theme.glassButtonPressed
                            : networkRow.hovered || networkRow.activeFocus ? Theme.glassButton : "transparent"
                    }

                    contentItem: Item {
                        Symbol {
                            id: networkSymbol
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            name: "wifi"
                            opacity: 0.4 + 0.15 * (networkRow.modelData.strength ?? 0)
                        }

                        Column {
                            anchors.left: networkSymbol.right
                            anchors.leftMargin: Theme.spacing
                            anchors.right: lockSymbol.left
                            anchors.rightMargin: Theme.spacing
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                width: parent.width
                                text: networkRow.text
                                color: Theme.text
                                font: Theme.metrics.font
                                elide: Text.ElideRight
                                Accessible.ignored: true
                            }

                            Text {
                                width: parent.width
                                visible: networkRow.modelData.connected === true
                                text: qsTr("Connected · select to disconnect")
                                color: Theme.activeIndicator
                                font.family: Theme.metrics.font.family
                                font.pixelSize: Theme.smallPixelSize
                                Accessible.ignored: true
                            }
                        }

                        Symbol {
                            id: lockSymbol
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            name: "lock"
                            visible: networkRow.modelData.secured === true
                            opacity: 0.7
                        }
                    }

                    FocusFrame {
                        visible: networkRow.activeFocus
                        radius: Theme.controlRadius
                    }
                }
            }

            Text {
                objectName: "wifiHint"
                width: parent.width
                visible: root.network !== null && (!root.network.wifiAvailable || !root.network.wifiEnabled
                    || wifiList.count === 0)
                text: !root.network ? ""
                    : !root.network.wifiAvailable ? qsTr("This computer has no Wi-Fi that Star OS can use.")
                    : !root.network.wifiEnabled ? qsTr("Wi-Fi is off.")
                    : root.network.scanning ? qsTr("Looking for networks…") : qsTr("No networks found.")
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }
}
