// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// Asks before something that cannot be undone (permanent deletion, emptying
// the Trash). Cancel has the focus when it opens, so Return alone is safe.
DialogFrame {
    id: dialog

    property string message: ""
    property string confirmText: ""

    signal confirmed()
    signal rejected()

    function open() {
        dialog.visible = true;
        cancelButton.forceActiveFocus(Qt.PopupFocusReason);
    }

    function confirm() {
        dialog.visible = false;
        dialog.confirmed();
    }

    function reject() {
        dialog.visible = false;
        dialog.rejected();
    }

    Accessible.description: dialog.message

    onEscapePressed: dialog.reject()

    Text {
        objectName: "confirmMessage"
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

        FilesButton {
            id: cancelButton
            objectName: "cancelButton"
            text: qsTr("Cancel")
            KeyNavigation.tab: confirmButton
            KeyNavigation.backtab: confirmButton
            onClicked: dialog.reject()
        }

        FilesButton {
            id: confirmButton
            objectName: "confirmButton"
            text: dialog.confirmText
            KeyNavigation.tab: cancelButton
            KeyNavigation.backtab: cancelButton
            onClicked: dialog.confirm()
        }
    }
}
