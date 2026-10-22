// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// Asks for a name (new folder, rename). Return accepts, Escape cancels. A
// name that `validate` rejects keeps the dialog open and shows why.
DialogFrame {
    id: dialog

    property string fieldName: ""
    property string acceptText: ""
    // Returns why a name cannot be used, or "".
    property var validate: name => ""

    signal accepted(string name)
    signal rejected()

    // Shows the dialog with `text`, selected up to `selectionEnd` (the whole
    // text when negative), so that typing replaces the name but keeps an
    // extension.
    function open(text, selectionEnd) {
        field.text = text;
        errorLabel.text = "";
        dialog.visible = true;
        field.forceActiveFocus(Qt.PopupFocusReason);
        field.select(0, selectionEnd >= 0 ? selectionEnd : text.length);
    }

    function accept() {
        const error = dialog.validate(field.text);
        if (error !== "") {
            errorLabel.text = error;
            errorLabel.Accessible.announce(error);
            return;
        }
        dialog.visible = false;
        dialog.accepted(field.text);
    }

    function reject() {
        dialog.visible = false;
        dialog.rejected();
    }

    onEscapePressed: dialog.reject()

    FilesTextField {
        id: field
        objectName: "nameField"
        width: parent.width
        Accessible.name: dialog.fieldName
        KeyNavigation.tab: cancelButton
        KeyNavigation.backtab: acceptButton
        Keys.onReturnPressed: event => {
            dialog.accept();
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            dialog.accept();
            event.accepted = true;
        }
    }

    Text {
        id: errorLabel
        objectName: "nameError"
        width: parent.width
        visible: text !== ""
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
            KeyNavigation.tab: acceptButton
            KeyNavigation.backtab: field
            onClicked: dialog.reject()
        }

        FilesButton {
            id: acceptButton
            objectName: "acceptButton"
            text: dialog.acceptText
            KeyNavigation.tab: field
            KeyNavigation.backtab: cancelButton
            onClicked: dialog.accept()
        }
    }
}
