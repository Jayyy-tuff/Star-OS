// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// The Star OS lock screen (M0.5, ADR-0016), loaded by kscreenlocker's
// greeter: the wallpaper dimmed, the time and date, the user and a password
// field. kscreenlocker provides 'authenticator' (PAM) and the user's name and
// picture as context properties; the greeter quits (unlocking) when PAM
// accepts. The live user has no password: Return unlocks through
// pam_unix's nullok.
//
// The authenticator's methods differ between kscreenlocker versions, so the
// calls below check for them: startAuthenticating() and respond(text) in
// Plasma 6, tryUnlock(text) before.
Item {
    id: root

    // Set by the greeter.
    property bool viewVisible: false
    property bool debug: false
    property string notification: ""
    property bool suspendToRamSupported: false
    property bool suspendToDiskSupported: false

    property date now: new Date()
    // The password typed before PAM asked for it.
    property string pending: ""
    property bool waiting: false
    property bool accepted: false

    readonly property var auth: typeof authenticator !== "undefined" ? authenticator : null
    readonly property string userName: typeof kscreenlocker_userName !== "undefined" ? kscreenlocker_userName : ""
    readonly property string userImage: typeof kscreenlocker_userImage !== "undefined" ? String(kscreenlocker_userImage) : ""

    signal clearPassword()
    signal notificationRepeated()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Screen locked")

    function unlockNow() {
        console.info("STAROS-LOCK unlocked");
        Qt.quit();
    }

    function submit() {
        if (root.accepted) {
            root.unlockNow();
            return;
        }
        if (!root.auth) {
            root.notification = qsTr("The lock screen cannot reach the login service.");
            return;
        }
        root.pending = password.text;
        root.waiting = true;
        root.notification = "";
        if (typeof root.auth.respond === "function" && root.auth.hadPrompt === true) {
            root.auth.respond(root.pending);
        } else if (typeof root.auth.startAuthenticating === "function") {
            root.auth.startAuthenticating();
        } else if (typeof root.auth.tryUnlock === "function") {
            root.auth.tryUnlock(root.pending);
        }
    }

    onClearPassword: {
        password.text = "";
        password.forceActiveFocus();
    }
    onViewVisibleChanged: {
        if (root.viewVisible) {
            password.forceActiveFocus();
        }
    }

    Connections {
        target: root.auth
        ignoreUnknownSignals: true

        // Without a password PAM may accept before anything was typed; as
        // in Breeze, the screen then waits for Return.
        function onSucceeded() {
            root.accepted = true;
            if (root.waiting) {
                root.waiting = false;
                root.unlockNow();
            }
        }
        function onFailed(kind) {
            // Fingerprint and smart card failures (kind != 0) are not ours.
            if (kind !== undefined && kind !== 0) {
                return;
            }
            root.waiting = false;
            root.notification = qsTr("That password did not work.");
            password.text = "";
            password.forceActiveFocus();
        }
        function onPromptForSecretChanged() {
            if (root.waiting && typeof root.auth.respond === "function") {
                root.auth.respond(root.pending);
            }
        }
        function onPromptForSecret() {
            if (root.waiting && typeof root.auth.respond === "function") {
                root.auth.respond(root.pending);
            }
        }
        function onErrorMessageChanged() {
            if (root.auth.errorMessage) {
                root.notification = root.auth.errorMessage;
            }
        }
        function onInfoMessageChanged() {
            if (root.auth.infoMessage) {
                root.notification = root.auth.infoMessage;
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.desktop
        Accessible.ignored: true
    }

    Image {
        anchors.fill: parent
        source: Theme.wallpaper
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        Accessible.ignored: true
    }

    Rectangle {
        anchors.fill: parent
        color: "#99070818"
        Accessible.ignored: true
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.14)
        spacing: Math.round(Theme.spacing / 2)

        Text {
            objectName: "time"
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, Qt.locale().timeFormat(Locale.ShortFormat).replace(/:ss/, ""))
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.pixelSize: Math.round(6 * Theme.gridUnit)
            font.weight: Font.Light
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            objectName: "date"
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, d MMMM")
            color: Theme.textSecondary
            font.family: Theme.metrics.font.family
            font.pixelSize: Theme.titlePixelSize
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }

    GlassPanel {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * 0.52)
        width: Math.min(Math.round(22 * Theme.gridUnit), root.width - 4 * Theme.spacing)
        height: column.implicitHeight + 2 * Theme.panelPadding
        wallpaperOrigin: Qt.point(card.x, card.y)
        screenSize: Qt.size(root.width, root.height)

        Column {
            id: column
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: card.width - 2 * Theme.panelPadding
            spacing: Theme.spacing

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(4 * Theme.gridUnit)
                height: width
                radius: width / 2
                gradient: Theme.accentGradient
                clip: true

                Text {
                    anchors.centerIn: parent
                    visible: picture.status !== Image.Ready
                    text: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : ""
                    color: Theme.accentText
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Math.round(1.8 * Theme.gridUnit)
                    font.weight: Font.DemiBold
                    Accessible.ignored: true
                }

                Image {
                    id: picture
                    anchors.fill: parent
                    source: root.userImage.startsWith("/") ? "file://" + root.userImage : root.userImage
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    Accessible.ignored: true
                }
            }

            Text {
                objectName: "userName"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.userName
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.headingPixelSize
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Row {
                width: parent.width
                spacing: Math.round(Theme.spacing / 2)

                T.TextField {
                    id: password
                    objectName: "password"
                    width: parent.width - unlockButton.width - parent.spacing
                    height: Theme.searchHeight
                    focus: true
                    leftPadding: Theme.spacing
                    rightPadding: Theme.spacing
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    enabled: !root.waiting
                    color: Theme.text
                    placeholderText: root.userName === "liveuser" || root.userName === "" ? qsTr("Press Enter to unlock")
                        : qsTr("Password")
                    placeholderTextColor: Theme.placeholder
                    font: Theme.metrics.font
                    Accessible.name: qsTr("Password")

                    Keys.onReturnPressed: event => {
                        root.submit();
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        root.submit();
                        event.accepted = true;
                    }
                    Keys.onEscapePressed: event => {
                        password.text = "";
                        event.accepted = true;
                    }

                    background: Rectangle {
                        radius: height / 2
                        color: Theme.searchField
                        border.width: 1
                        border.color: password.activeFocus ? Theme.searchBorder : Theme.glassBorder
                    }

                    FocusFrame {
                        visible: password.activeFocus
                        radius: height / 2
                    }
                }

                ShellButton {
                    id: unlockButton
                    objectName: "unlockButton"
                    width: Theme.searchHeight
                    height: Theme.searchHeight
                    radius: height / 2
                    iconOnly: true
                    highlighted: true
                    symbol: "chevron-right"
                    text: qsTr("Unlock")
                    enabled: !root.waiting
                    onClicked: root.submit()
                }
            }

            Text {
                objectName: "message"
                width: parent.width
                visible: text !== ""
                horizontalAlignment: Text.AlignHCenter
                text: root.waiting ? qsTr("Unlocking…") : root.notification
                color: root.waiting ? Theme.textSecondary : Theme.focusRing
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    Component.onCompleted: {
        password.forceActiveFocus();
        console.info("STAROS-LOCK ready user=" + root.userName + " authenticator=" + (root.auth !== null)
            + " api=" + (root.auth ? ["startAuthenticating", "respond", "tryUnlock"].filter(
                name => typeof root.auth[name] === "function").join(",") : ""));
    }
}
