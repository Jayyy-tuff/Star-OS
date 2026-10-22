// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// First run: Sun Store adds Flathub only when the person agrees. "Not now"
// closes Sun Store without changing anything; it asks again next time.
FocusScope {
    id: page

    readonly property string message: qsTr("Sun Store installs apps from Flathub, a community app store. Star OS does not review these apps.")
    property size screenSize: Qt.size(width, height)

    signal accepted()
    signal declined()

    Accessible.role: Accessible.Dialog
    Accessible.name: qsTr("Enable Flathub?")
    Accessible.description: page.message

    Keys.onEscapePressed: event => {
        page.declined();
        event.accepted = true;
    }

    // Nothing behind the page takes the pointer.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: wheel => wheel.accepted = true
    }

    GlassSurface {
        id: panel
        anchors.centerIn: parent
        width: Math.min(page.width - 4 * Theme.spacing, 32 * Theme.gridUnit)
        height: column.implicitHeight + 4 * Theme.spacing
        wallpaperOrigin: Qt.point(panel.x, panel.y)
        screenSize: page.screenSize
    }

    Column {
        id: column
        anchors.centerIn: panel
        width: panel.width - 4 * Theme.spacing
        spacing: Theme.spacing

        AppIcon {
            anchors.horizontalCenter: parent.horizontalCenter
            appId: "org.staros.sunstore"
            name: qsTr("Sun Store")
        }

        Text {
            width: parent.width
            text: qsTr("Enable Flathub?")
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.pixelSize: Math.round(Theme.metrics.height * 1.25)
            font.bold: true
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        Text {
            objectName: "consentMessage"
            width: parent.width
            text: page.message
            color: Theme.text
            font: Theme.metrics.font
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            width: parent.width
            text: qsTr("Flathub is added for your user account only. Apps and their updates are downloaded from flathub.org, and each app shows what it may access before you install it.")
            color: Theme.placeholder
            font: Theme.metrics.font
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Row {
            x: parent.width - width
            spacing: Theme.spacing

            StoreButton {
                id: declineButton
                objectName: "declineButton"
                text: qsTr("Not now")
                description: qsTr("Close Sun Store without adding Flathub")
                KeyNavigation.tab: acceptButton
                KeyNavigation.backtab: acceptButton
                onClicked: page.declined()
            }

            StoreButton {
                id: acceptButton
                objectName: "enableFlathubButton"
                text: qsTr("Enable Flathub")
                primary: true
                focus: true
                KeyNavigation.tab: declineButton
                KeyNavigation.backtab: declineButton
                onClicked: page.accepted()
            }
        }
    }
}
