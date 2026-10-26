// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import StarOS.Shell

// The Welcome tour (M0.5, ADR-0017): five pages over the Star OS wallpaper,
// each a glass card with a symbol, a heading, a few lines and, where it
// helps, a button that opens the app it shows. Right or Return goes on,
// Left goes back, Escape skips; the last page's button finishes. Finishing
// or skipping marks the tour as seen.
//
// 'welcome' is WelcomeState (or a test double): finish() and open(desktopId).
FocusScope {
    id: root

    property var welcome: null
    property int page: 0

    readonly property var pages: [
        {
            key: "welcome",
            symbol: "",
            title: qsTr("Welcome to Star OS"),
            text: qsTr("A calm, fast desktop built on Arch Linux and KDE technology. This short tour shows what makes it different; it takes a minute."),
            action: "",
            actionText: ""
        },
        {
            key: "start",
            symbol: "search",
            title: qsTr("Everything starts with the Star key"),
            text: qsTr("Press the Star (Meta) key and type: apps appear as you type. Type 12*3 or 5 km in miles for an answer, or note: buy milk to put a sticky note on the desktop. Meta+V shows what you copied."),
            action: "",
            actionText: ""
        },
        {
            key: "lens",
            symbol: "screenshot",
            title: qsTr("Star Lens reads your screen"),
            text: qsTr("Press Meta+Shift+L and select an area: Star Lens reads its text, QR codes and barcodes, without sending anything anywhere."),
            action: "org.staros.lens.desktop",
            actionText: qsTr("Try Star Lens")
        },
        {
            key: "storage",
            symbol: "disk",
            title: qsTr("Keep your work with Star Storage"),
            text: qsTr("This live session forgets changes when the computer turns off. Star Storage keeps your files and settings on a USB disk, so they are there next time."),
            action: "org.staros.storage.desktop",
            actionText: qsTr("Open Star Storage")
        },
        {
            key: "apps",
            symbol: "gamepad",
            title: qsTr("Apps and games"),
            text: qsTr("Sun Store installs apps from Flathub when you allow it. Game Center gathers your games from Steam and Flathub in one place, with game mode."),
            action: "org.staros.sunstore.desktop",
            actionText: qsTr("Open Sun Store")
        }
    ]
    readonly property var current: root.pages[root.page]
    readonly property bool last: root.page === root.pages.length - 1

    signal done()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Welcome to Star OS")

    function next() {
        if (root.last) {
            root.finish();
        } else {
            root.page += 1;
            nextButton.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    function back() {
        if (root.page > 0) {
            root.page -= 1;
        }
    }

    function finish() {
        if (root.welcome) {
            root.welcome.finish();
        }
        root.done();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Right && !(event.modifiers & Qt.AltModifier)) {
            root.next();
            event.accepted = true;
        } else if (event.key === Qt.Key_Left) {
            root.back();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.finish();
            event.accepted = true;
        }
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

    GlassPanel {
        id: card
        objectName: "card"
        anchors.centerIn: parent
        width: Math.min(Math.round(34 * Theme.gridUnit), root.width - 4 * Theme.spacing)
        height: Math.min(column.implicitHeight + 2 * Theme.panelPadding * 1.6, root.height - 4 * Theme.spacing)
        wallpaperOrigin: Qt.point(card.x, card.y)
        screenSize: Qt.size(root.width, root.height)

        Column {
            id: column
            x: Math.round(Theme.panelPadding * 1.6)
            y: Math.round(Theme.panelPadding * 1.6)
            width: card.width - 2 * x
            spacing: Theme.spacing * 1.5

            // The star on the first page, the page's symbol after it.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.round(4.4 * Theme.gridUnit)
                height: width

                Image {
                    objectName: "logo"
                    anchors.fill: parent
                    visible: root.current.symbol === ""
                    source: Icons.logo
                    sourceSize: Qt.size(width, height)
                    Accessible.ignored: true
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.current.symbol !== ""
                    radius: Theme.panelRadius
                    gradient: Theme.accentGradient

                    Symbol {
                        anchors.centerIn: parent
                        width: Math.round(parent.width * 0.55)
                        height: width
                        name: root.current.symbol
                    }
                }
            }

            Text {
                objectName: "pageTitle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.current.title
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.titlePixelSize
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            Text {
                objectName: "pageText"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.current.text
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize * 1.1)
                lineHeight: 1.25
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacing
                visible: root.current.action !== ""

                ShellButton {
                    objectName: "actionButton"
                    height: Math.round(2 * Theme.gridUnit)
                    radius: height / 2
                    text: root.current.actionText
                    onClicked: root.welcome.open(root.current.action)
                }

                ShellButton {
                    objectName: "gamesButton"
                    height: Math.round(2 * Theme.gridUnit)
                    radius: height / 2
                    visible: root.current.key === "apps"
                    text: qsTr("Open Game Center")
                    onClicked: root.welcome.open("org.staros.games.desktop")
                }
            }

            // Page dots.
            Row {
                objectName: "dots"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(Theme.spacing * 0.6)

                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("Page %1 of %2").arg(root.page + 1).arg(root.pages.length)

                Repeater {
                    model: root.pages.length

                    Rectangle {
                        required property int index

                        anchors.verticalCenter: parent.verticalCenter
                        width: index === root.page ? Math.round(1.4 * Theme.gridUnit) : Math.round(0.45 * Theme.gridUnit)
                        height: Math.round(0.45 * Theme.gridUnit)
                        radius: height / 2
                        color: index === root.page ? Theme.activeIndicator : Theme.glassButtonActive

                        Behavior on width {
                            NumberAnimation {
                                duration: Theme.durationMedium
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: nextButton.height

                ShellButton {
                    id: skipButton
                    objectName: "skipButton"
                    anchors.left: parent.left
                    flat: true
                    visible: !root.last
                    text: qsTr("Skip the tour")
                    onClicked: root.finish()
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.spacing

                    ShellButton {
                        objectName: "backButton"
                        visible: root.page > 0
                        symbol: "chevron-left"
                        text: qsTr("Back")
                        onClicked: root.back()
                    }

                    ShellButton {
                        id: nextButton
                        objectName: "nextButton"
                        highlighted: true
                        focus: true
                        text: root.page === 0 ? qsTr("Take the tour") : root.last ? qsTr("Start using Star OS") : qsTr("Next")
                        onClicked: root.next()
                    }
                }
            }
        }
    }
}
