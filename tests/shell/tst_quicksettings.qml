// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Quick settings (M0.5, ADR-0014): the panel above the tray, the tiles and
// what they ask of their objects, the sliders, the network page with Wi-Fi
// networks and the passphrase iwd asks for, Escape stepping back, and the
// visible focus ring. The objects are test doubles with StarOS.System's
// members.
Item {
    id: root

    width: 1280
    height: 720

    QtObject {
        id: fakeAudio
        property bool available: true
        property int volume: 50
        property bool muted: false
        property int muteToggles: 0
        function toggleMute() {
            fakeAudio.muteToggles += 1;
            fakeAudio.muted = !fakeAudio.muted;
        }
    }

    QtObject {
        id: fakeDisplay
        property bool brightnessAvailable: false
        property int brightness: 70
        property bool nightLightAvailable: true
        property bool nightLight: false
    }

    QtObject {
        id: fakeNetwork
        property string state: "connected"
        property string kind: "wired"
        property string networkName: ""
        property bool wifiAvailable: true
        property bool wifiEnabled: true
        property bool scanning: false
        property var wifiNetworks: []
        property var calls: []
        signal passphraseRequested(string networkName)
        signal passphraseDone()
        signal connectFailed(string networkName, string error)
        function setWifiEnabled(on) {
            fakeNetwork.calls = fakeNetwork.calls.concat(["wifi " + on]);
        }
        function scan() {
            fakeNetwork.calls = fakeNetwork.calls.concat(["scan"]);
        }
        function connectTo(path) {
            fakeNetwork.calls = fakeNetwork.calls.concat(["connect " + path]);
        }
        function disconnectWifi() {
            fakeNetwork.calls = fakeNetwork.calls.concat(["disconnect"]);
        }
        function submitPassphrase(text) {
            fakeNetwork.calls = fakeNetwork.calls.concat(["passphrase " + text]);
        }
        function cancelPassphrase() {
            fakeNetwork.calls = fakeNetwork.calls.concat(["cancel"]);
        }
    }

    readonly property var liveStatus: ({storageMode: "live", storageTotal: 2e9, storageFree: 1.5e9,
                                        memoryTotal: 4e9, memoryAvailable: 3e9, batteryPresent: false,
                                        batteryPercent: 0, charging: false})

    QuickSettings {
        id: quick
        anchors.fill: parent
        audio: fakeAudio
        display: fakeDisplay
        network: fakeNetwork
        status: root.liveStatus
        anchorRight: 1100
    }

    Component {
        id: bareComponent

        QuickSettings {
            width: 1280
            height: 720
        }
    }

    SignalSpy {
        id: closeSpy
        target: quick
        signalName: "closeRequested"
    }

    SignalSpy {
        id: dndSpy
        target: quick
        signalName: "doNotDisturbToggled"
    }

    SignalSpy {
        id: gameSpy
        target: quick
        signalName: "gameModeToggled"
    }

    SignalSpy {
        id: clipboardSpy
        target: quick
        signalName: "clipboardRequested"
    }

    SignalSpy {
        id: lensSpy
        target: quick
        signalName: "lensRequested"
    }

    SignalSpy {
        id: storageSpy
        target: quick
        signalName: "storageRequested"
    }

    SignalSpy {
        id: settingsSpy
        target: quick
        signalName: "settingsRequested"
    }

    SignalSpy {
        id: powerSpy
        target: quick
        signalName: "powerRequested"
    }

    TestCase {
        name: "QuickSettings"
        when: windowShown

        readonly property var networks: [
            {path: "/net/connman/iwd/0/1/home_psk", name: "Home", strength: 4, secured: true, connected: true,
             known: true},
            {path: "/net/connman/iwd/0/1/cafe_open", name: "Cafe", strength: 2, secured: false, connected: false,
             known: false}
        ]
        property Item panel
        property Item networkTile
        property Item nightTile
        property Item volume
        property Item brightness

        function initTestCase() {
            Theme.animationFactor = 0;
            panel = findChild(quick, "panel");
            networkTile = findChild(quick, "networkTile");
            nightTile = findChild(quick, "nightLightTile");
            volume = findChild(quick, "volumeSlider");
            brightness = findChild(quick, "brightnessSlider");
            verify(panel && networkTile && nightTile && volume && brightness);
        }

        function init() {
            fakeAudio.available = true;
            fakeAudio.volume = 50;
            fakeAudio.muted = false;
            fakeAudio.muteToggles = 0;
            fakeDisplay.brightnessAvailable = false;
            fakeDisplay.brightness = 70;
            fakeDisplay.nightLightAvailable = true;
            fakeDisplay.nightLight = false;
            fakeNetwork.state = "connected";
            fakeNetwork.kind = "wired";
            fakeNetwork.networkName = "";
            fakeNetwork.wifiAvailable = true;
            fakeNetwork.wifiEnabled = true;
            fakeNetwork.scanning = false;
            fakeNetwork.wifiNetworks = [];
            fakeNetwork.calls = [];
            quick.doNotDisturb = false;
            quick.gameModeAvailable = false;
            quick.gameMode = false;
            quick.clipboardCount = -1;
            for (const spy of [closeSpy, dndSpy, gameSpy, clipboardSpy, lensSpy, storageSpy, settingsSpy, powerSpy]) {
                spy.clear();
            }
            quick.reset();
            tryVerify(() => networkTile.activeFocus, 5000, "the network tile has focus");
        }

        function stateOf(objectName) {
            return findChild(findChild(quick, objectName), "state").text;
        }

        function focusedItem() {
            return quick.Window.activeFocusItem;
        }

        function test_panel_sits_above_the_tray() {
            compare(Math.round(panel.x + panel.width), 1100);
            const bottom = root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap;
            fuzzyCompare(panel.y + panel.height, bottom, 1);
            verify(panel.y >= 0);
            compare(panel.width, Theme.trayPanelWidth);
            compare(quick.Accessible.name, "Quick settings");
        }

        function test_network_tile() {
            compare(networkTile.text, "Network");
            compare(networkTile.Accessible.description, "Wired, connected");
            verify(networkTile.checked);
            fakeNetwork.kind = "wifi";
            fakeNetwork.networkName = "Home";
            compare(networkTile.text, "Wi-Fi");
            compare(stateOf("networkTile"), "Home");
            fakeNetwork.state = "limited";
            verify(!networkTile.checked);
            compare(networkTile.Accessible.description, "Connected, no internet");
        }

        function test_night_light_switch() {
            compare(nightTile.Accessible.role, Accessible.CheckBox);
            compare(stateOf("nightLightTile"), "Off");
            nightTile.forceActiveFocus();
            keyClick(Qt.Key_Space);
            verify(fakeDisplay.nightLight);
            verify(nightTile.checked);
            compare(stateOf("nightLightTile"), "On");
            keyClick(Qt.Key_Return);
            verify(!fakeDisplay.nightLight);
            fakeDisplay.nightLightAvailable = false;
            verify(!nightTile.enabled);
            compare(stateOf("nightLightTile"), "Not available");
        }

        function test_do_not_disturb_and_game_mode() {
            const dnd = findChild(quick, "doNotDisturbTile");
            mouseClick(dnd);
            compare(dndSpy.count, 1);
            verify(!dnd.checked, "the host decides");
            quick.doNotDisturb = true;
            verify(dnd.checked);
            compare(dnd.Accessible.description, "On");
            const game = findChild(quick, "gameModeTile");
            verify(!game.visible);
            quick.gameModeAvailable = true;
            verify(game.visible);
            mouseClick(game);
            compare(gameSpy.count, 1);
        }

        function test_clipboard_and_lens_tiles() {
            const clipboard = findChild(quick, "clipboardTile");
            verify(!clipboard.visible);
            quick.clipboardCount = 1;
            verify(clipboard.visible);
            compare(clipboard.Accessible.description, "1 item");
            quick.clipboardCount = 3;
            compare(clipboard.Accessible.description, "3 items");
            mouseClick(clipboard);
            compare(clipboardSpy.count, 1);
            mouseClick(findChild(quick, "lensTile"));
            compare(lensSpy.count, 1);
        }

        function test_volume_keys() {
            const slider = findChild(volume, "slider");
            compare(slider.Accessible.name, "Volume");
            compare(slider.value, 50);
            compare(findChild(volume, "valueLabel").text, "50 %");
            slider.forceActiveFocus();
            keyClick(Qt.Key_Right);
            compare(fakeAudio.volume, 55);
            keyClick(Qt.Key_Left);
            keyClick(Qt.Key_Left);
            compare(fakeAudio.volume, 45);
            keyClick(Qt.Key_PageUp);
            compare(fakeAudio.volume, 55);
            keyClick(Qt.Key_End);
            compare(fakeAudio.volume, 100);
            keyClick(Qt.Key_Home);
            compare(fakeAudio.volume, 0);
            // A change from outside still moves the slider.
            fakeAudio.volume = 35;
            compare(slider.value, 35);
        }

        function test_volume_drag() {
            const slider = findChild(volume, "slider");
            mouseClick(slider, slider.leftPadding + slider.availableWidth * 0.8, slider.height / 2);
            verify(fakeAudio.volume >= 75 && fakeAudio.volume <= 90, "volume " + fakeAudio.volume);
        }

        function test_mute_button() {
            const button = findChild(volume, "symbolButton");
            compare(button.text, "Mute");
            mouseClick(button);
            compare(fakeAudio.muteToggles, 1);
            compare(button.text, "Unmute");
            compare(button.symbol, "volume-mute");
        }

        function test_without_sound_output() {
            fakeAudio.available = false;
            verify(!volume.enabled);
            verify(findChild(quick, "noAudio").visible);
            fakeAudio.available = true;
            verify(!findChild(quick, "noAudio").visible);
        }

        function test_brightness_only_when_available() {
            verify(!brightness.visible);
            fakeDisplay.brightnessAvailable = true;
            verify(brightness.visible);
            const slider = findChild(brightness, "slider");
            compare(slider.value, 70);
            slider.forceActiveFocus();
            keyClick(Qt.Key_Left);
            compare(fakeDisplay.brightness, 65);
        }

        function test_tab_order() {
            const order = [];
            for (let i = 0; i < 9; ++i) {
                keyClick(Qt.Key_Tab);
                const item = focusedItem();
                order.push(item.objectName !== "" ? item.objectName : item.Accessible.name);
            }
            const expected = ["nightLightTile", "doNotDisturbTile", "lensTile", "symbolButton", "slider",
                              "storageButton", "settingsButton", "powerButton", "networkTile"];
            compare(order, expected);
        }

        function test_footer() {
            const storage = findChild(quick, "storageButton");
            compare(storage.text, "Live session · 1.5 GB free");
            verify(storage.description.startsWith("Live session: changes are lost at shutdown."));
            mouseClick(storage);
            compare(storageSpy.count, 1);
            mouseClick(findChild(quick, "settingsButton"));
            compare(settingsSpy.count, 1);
            mouseClick(findChild(quick, "powerButton"));
            compare(powerSpy.count, 1);
            verify(!findChild(quick, "battery").visible);
        }

        function test_network_page_and_escape() {
            keyClick(Qt.Key_Return);
            compare(quick.page, "network");
            verify(findChild(quick, "networkPage").visible);
            verify(!findChild(quick, "mainPage").visible);
            compare(fakeNetwork.calls, ["scan"]);
            tryVerify(() => findChild(quick, "backButton").activeFocus);
            compare(findChild(quick, "networkState").text, "Wired network: Wired, connected");
            compare(findChild(quick, "wifiHint").text, "No networks found.");
            keyClick(Qt.Key_Escape);
            compare(quick.page, "main");
            tryVerify(() => networkTile.activeFocus);
            compare(closeSpy.count, 0);
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 1);
        }

        function test_wifi_networks() {
            fakeNetwork.wifiNetworks = networks;
            quick.showNetworkPage();
            const list = findChild(quick, "wifiNetworks");
            verify(list.visible);
            compare(list.count, 2);
            compare(list.Accessible.name, "Wi-Fi networks");
            const home = list.itemAtIndex(0);
            compare(home.Accessible.name, "Home");
            compare(home.Accessible.description, "Connected, Secured, Signal 4 of 4");
            compare(list.itemAtIndex(1).Accessible.description, "Open, Signal 2 of 4");
            mouseClick(list.itemAtIndex(1));
            compare(fakeNetwork.calls, ["scan", "connect /net/connman/iwd/0/1/cafe_open"]);
            mouseClick(home);
            compare(fakeNetwork.calls[2], "disconnect");
            // Keyboard: Tab from Back reaches the switch, then the list.
            findChild(quick, "backButton").forceActiveFocus();
            keyClick(Qt.Key_Tab);
            compare(focusedItem().objectName, "wifiSwitch");
            keyClick(Qt.Key_Tab);
            verify(list.currentItem.activeFocus);
        }

        function test_wifi_switch() {
            quick.showNetworkPage();
            const toggle = findChild(quick, "wifiSwitch");
            verify(toggle.visible && toggle.checked);
            compare(toggle.Accessible.role, Accessible.CheckBox);
            mouseClick(toggle);
            compare(fakeNetwork.calls[fakeNetwork.calls.length - 1], "wifi false");
            fakeNetwork.wifiEnabled = false;
            verify(!findChild(quick, "wifiNetworks").visible);
            compare(findChild(quick, "wifiHint").text, "Wi-Fi is off.");
            fakeNetwork.wifiAvailable = false;
            verify(!toggle.visible);
            compare(findChild(quick, "wifiHint").text, "This computer has no Wi-Fi that Star OS can use.");
        }

        function test_passphrase() {
            fakeNetwork.passphraseRequested("Cafe");
            compare(quick.page, "network");
            const field = findChild(quick, "passphraseField");
            verify(findChild(quick, "passphrase").visible);
            tryVerify(() => field.activeFocus);
            const connect = findChild(quick, "connectButton");
            for (const ch of "short") {
                keyClick(ch);
            }
            verify(!connect.enabled, "eight characters at least");
            keyClick(Qt.Key_Return);
            verify(fakeNetwork.calls.indexOf("passphrase short") < 0);
            for (const ch of "-enough") {
                keyClick(ch);
            }
            verify(connect.enabled);
            keyClick(Qt.Key_Return);
            compare(fakeNetwork.calls[fakeNetwork.calls.length - 1], "passphrase short-enough");
            verify(!findChild(quick, "passphrase").visible);
            compare(field.text, "", "the field forgets the passphrase");
        }

        function test_passphrase_escape_cancels() {
            fakeNetwork.passphraseRequested("Cafe");
            tryVerify(() => findChild(quick, "passphraseField").activeFocus);
            keyClick(Qt.Key_Escape);
            compare(fakeNetwork.calls[fakeNetwork.calls.length - 1], "cancel");
            verify(!findChild(quick, "passphrase").visible);
            compare(quick.page, "network");
            compare(closeSpy.count, 0);
        }

        function test_connect_failed() {
            quick.showNetworkPage();
            fakeNetwork.connectFailed("Cafe", "Wrong password");
            const error = findChild(quick, "networkError");
            verify(error.visible);
            compare(error.text, "Could not connect to Cafe: Wrong password");
            quick.showMainPage();
            quick.showNetworkPage();
            verify(!error.visible);
        }

        function test_click_outside_closes() {
            mouseClick(quick, 20, 20);
            compare(closeSpy.count, 1);
            mouseClick(panel, 4, 4);
            compare(closeSpy.count, 1, "a click on the panel keeps it open");
        }

        function test_without_objects() {
            const bare = createTemporaryObject(bareComponent, root);
            verify(bare);
            verify(!findChild(bare, "networkTile").visible);
            verify(!findChild(bare, "nightLightTile").visible);
            verify(!findChild(bare, "volumeSlider").visible);
            verify(!findChild(bare, "brightnessSlider").visible);
            compare(findChild(bare, "storageButton").text, "Storage");
            verify(findChild(bare, "doNotDisturbTile").visible);
        }

        function test_focus_ring() {
            waitForRendering(quick);
            const img = grabImage(quick);
            const dpr = Screen.devicePixelRatio;
            const p = networkTile.mapToItem(quick, 1, networkTile.height / 2);
            const y = Math.floor(p.y * dpr);
            let hits = 0;
            for (let x = Math.max(0, Math.floor((p.x - 2) * dpr)); x < Math.floor((p.x + 6) * dpr); ++x) {
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
