// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import StarOS.Shell

// The Star OS logout screen (M0.5, ADR-0016), loaded by Plasma's logout
// greeter for the start menu's Log out, Restart, Shut down and Power: the
// wallpaper dimmed, the user, and the choices on glass. Asked for one
// action, that action is chosen after 30 seconds unless cancelled, as in
// Breeze. Escape or a click outside cancels.
//
// The greeter provides the context properties sdtype (-1 any, 0 log out,
// 1 restart, 2 shut down), maysd, canLogout, spdMethods,
// softwareUpdatePending and screenGeometry, and listens to the signals below
// (Plasma 6.7's Breeze Logout.qml). They are read defensively so that a
// change in them shows fewer buttons instead of failing.
FocusScope {
    id: root

    focus: true

    signal logoutRequested()
    signal haltRequested()
    signal haltUpdateRequested()
    signal suspendRequested(int spdMethod)
    signal rebootRequested()
    signal rebootRequested2(int opt)
    signal rebootUpdateRequested()
    signal cancelRequested()
    signal lockScreenRequested()
    signal cancelSoftwareUpdateRequested()

    readonly property int typeDefault: -1
    readonly property int typeLogout: 0
    readonly property int typeReboot: 1
    readonly property int typeHalt: 2

    readonly property int kind: typeof sdtype !== "undefined" ? Number(sdtype) : root.typeDefault
    readonly property bool showAll: root.kind !== root.typeLogout && root.kind !== root.typeReboot
        && root.kind !== root.typeHalt
    readonly property bool canShutDown: typeof maysd === "undefined" || maysd === true
    readonly property bool mayLogOut: typeof canLogout === "undefined" || canLogout === true
    readonly property bool canSleep: typeof spdMethods !== "undefined" && spdMethods !== null
        && spdMethods.SuspendState === true
    readonly property bool updates: typeof softwareUpdatePending !== "undefined" && softwareUpdatePending === true

    property real timeout: 30
    property real remainingTime: root.timeout

    width: typeof screenGeometry !== "undefined" ? screenGeometry.width : 1280
    height: typeof screenGeometry !== "undefined" ? screenGeometry.height : 800

    Accessible.role: Accessible.Dialog
    Accessible.name: root.kind === root.typeReboot ? qsTr("Restart")
        : root.kind === root.typeHalt ? qsTr("Shut down")
        : root.kind === root.typeLogout ? qsTr("Log out") : qsTr("Power")

    function runChosen() {
        if (root.kind === root.typeReboot) {
            root.updates ? root.rebootUpdateRequested() : root.rebootRequested();
        } else if (root.kind === root.typeHalt) {
            root.updates ? root.haltUpdateRequested() : root.haltRequested();
        } else {
            root.logoutRequested();
        }
    }

    onRemainingTimeChanged: {
        if (root.remainingTime <= 0) {
            root.runChosen();
        }
    }

    Keys.onEscapePressed: event => {
        root.cancelRequested();
        event.accepted = true;
    }

    Timer {
        id: countDown
        running: !root.showAll
        repeat: true
        interval: 1000
        onTriggered: root.remainingTime -= 1
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
        color: "#b3070818"
        Accessible.ignored: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.cancelRequested()
    }

    GlassPanel {
        id: card
        anchors.centerIn: parent
        width: Math.min(Math.round(30 * Theme.gridUnit), root.width - 4 * Theme.spacing)
        height: column.implicitHeight + 2 * Theme.panelPadding * 1.4
        wallpaperOrigin: Qt.point(card.x, card.y)
        screenSize: Qt.size(root.width, root.height)

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            x: Math.round(Theme.panelPadding * 1.4)
            y: Math.round(Theme.panelPadding * 1.4)
            width: card.width - 2 * x
            spacing: Theme.spacing * 1.5

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(3.6 * Theme.gridUnit)
                height: width
                source: Icons.logo
                sourceSize: Qt.size(width, height)
                Accessible.ignored: true
            }

            Text {
                objectName: "title"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.kind === root.typeReboot ? qsTr("Restart Star OS?")
                    : root.kind === root.typeHalt ? qsTr("Shut down?")
                    : root.kind === root.typeLogout ? qsTr("Log out?") : qsTr("What would you like to do?")
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.titlePixelSize
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            Text {
                objectName: "countdown"
                width: parent.width
                visible: countDown.running
                horizontalAlignment: Text.AlignHCenter
                text: root.kind === root.typeReboot ? qsTr("Restarting in %1 seconds").arg(Math.max(0, root.remainingTime))
                    : root.kind === root.typeHalt ? qsTr("Shutting down in %1 seconds").arg(Math.max(0, root.remainingTime))
                    : qsTr("Logging out in %1 seconds").arg(Math.max(0, root.remainingTime))
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize)
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Unsaved work in open apps may be lost. On the live medium, changes not kept by Star Storage are lost at shutdown.")
                color: Theme.textTertiary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Flow {
                id: buttons
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width, implicitButtonsWidth)
                spacing: Theme.spacing

                readonly property real implicitButtonsWidth: {
                    let total = 0;
                    let shown = 0;
                    for (const child of buttons.children) {
                        if (child.visible) {
                            total += child.implicitWidth;
                            shown += 1;
                        }
                    }
                    return total + Math.max(0, shown - 1) * buttons.spacing;
                }

                ShellButton {
                    objectName: "sleepButton"
                    visible: root.showAll && root.canSleep
                    symbol: "night"
                    text: qsTr("Sleep")
                    onClicked: root.suspendRequested(2)
                }

                ShellButton {
                    id: restartButton
                    objectName: "restartButton"
                    visible: root.canShutDown && (root.showAll || root.kind === root.typeReboot)
                    highlighted: root.kind === root.typeReboot
                    focus: root.kind === root.typeReboot
                    symbol: "restart"
                    text: root.updates ? qsTr("Update and restart") : qsTr("Restart")
                    onClicked: root.updates ? root.rebootUpdateRequested() : root.rebootRequested()
                }

                ShellButton {
                    id: shutdownButton
                    objectName: "shutdownButton"
                    visible: root.canShutDown && (root.showAll || root.kind === root.typeHalt)
                    highlighted: root.kind === root.typeHalt
                    focus: root.kind === root.typeHalt || root.showAll
                    symbol: "power"
                    text: root.updates ? qsTr("Update and shut down") : qsTr("Shut down")
                    onClicked: root.updates ? root.haltUpdateRequested() : root.haltRequested()
                }

                ShellButton {
                    objectName: "logoutButton"
                    visible: root.mayLogOut && (root.showAll || root.kind === root.typeLogout)
                    highlighted: root.kind === root.typeLogout
                    focus: root.kind === root.typeLogout
                    symbol: "logout"
                    text: qsTr("Log out")
                    onClicked: root.logoutRequested()
                }

                ShellButton {
                    objectName: "cancelButton"
                    symbol: "close"
                    text: qsTr("Cancel")
                    onClicked: root.cancelRequested()
                }
            }
        }
    }

    Component.onCompleted: console.info("STAROS-LOGOUT ready type=" + root.kind + " maysd=" + root.canShutDown
        + " canLogout=" + root.mayLogOut)
}
