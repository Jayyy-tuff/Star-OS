// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// Asks before anything leaves the computer: "Search with Google Lens" sends
// the selected image to Google. Shown every time; Cancel has the focus.
FocusScope {
    id: dialog

    property size screenSize: Qt.size(width, height)

    signal confirmed()
    signal rejected()

    readonly property string message: qsTr("This sends the selected image to Google. Star Lens copies the image, saves it in Pictures/Star Lens and opens Google Lens in your browser; when you paste or upload it there, Google receives it and Google's privacy policy applies.")

    visible: false
    z: 20

    Accessible.role: Accessible.Dialog
    Accessible.name: qsTr("Search with Google Lens?")
    Accessible.description: dialog.message

    function open() {
        dialog.visible = true;
        cancelButton.forceActiveFocus(Qt.PopupFocusReason);
    }

    function close() {
        dialog.visible = false;
    }

    Keys.onEscapePressed: event => {
        dialog.close();
        dialog.rejected();
        event.accepted = true;
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: wheel => wheel.accepted = true
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: 0.45
    }

    GlassSurface {
        id: panel
        anchors.centerIn: parent
        width: Math.min(dialog.width - 4 * Theme.spacing, 32 * Theme.gridUnit)
        height: column.implicitHeight + 4 * Theme.spacing
        wallpaperOrigin: Qt.point(panel.x, panel.y)
        screenSize: dialog.screenSize
    }

    Column {
        id: column
        anchors.centerIn: panel
        width: panel.width - 4 * Theme.spacing
        spacing: Theme.spacing

        Text {
            width: parent.width
            text: qsTr("Search with Google Lens?")
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.pixelSize: Math.round(Theme.metrics.height * 1.25)
            font.bold: true
            wrapMode: Text.Wrap
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        Text {
            objectName: "lensWarning"
            width: parent.width
            text: dialog.message
            color: Theme.text
            font: Theme.metrics.font
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Row {
            x: parent.width - width
            spacing: Theme.spacing

            ShellButton {
                id: cancelButton
                objectName: "lensCancelButton"
                text: qsTr("Cancel")
                KeyNavigation.tab: confirmButton
                KeyNavigation.backtab: confirmButton
                onClicked: {
                    dialog.close();
                    dialog.rejected();
                }
            }

            ShellButton {
                id: confirmButton
                objectName: "lensConfirmButton"
                text: qsTr("Open Google Lens")
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: cancelButton
                onClicked: {
                    dialog.close();
                    dialog.confirmed();
                }
            }
        }
    }
}
