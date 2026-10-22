// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import StarOS.Shell

// One app: icon, name, developer, verification, licence, summary, what the
// app may access, the description and Install / Remove / Open. Permissions
// come from Flathub (store.requestPermissions) each time the page opens.
FocusScope {
    id: page

    required property var store
    property string appId: ""

    // Read again whenever the store's apps change (installed, updates).
    readonly property var app: page.store.apps.revision >= 0 && page.appId !== "" ? page.store.apps.app(page.appId) : ({})
    readonly property bool installed: page.app.installed === true
    readonly property bool working: page.store.busy && page.store.busyAppId === page.appId

    property var permissions: []
    property string permissionsText: ""
    property string message: ""
    property bool messageIsError: false

    signal backRequested()

    Accessible.role: Accessible.Pane
    Accessible.name: page.app.name !== undefined ? page.app.name : page.appId

    function load() {
        page.permissions = [];
        page.message = "";
        page.messageIsError = false;
        if (page.appId === "") {
            return;
        }
        page.permissionsText = qsTr("Checking what this app may access…");
        page.store.requestPermissions(page.appId);
    }

    function showMessage(text, isError) {
        page.message = text;
        page.messageIsError = isError;
        messageLabel.Accessible.announce(text);
    }

    // Focus the main action: Open or Install.
    function focusAction() {
        if (openButton.visible) {
            openButton.forceActiveFocus(Qt.OtherFocusReason);
        } else if (installButton.visible && installButton.enabled) {
            installButton.forceActiveFocus(Qt.OtherFocusReason);
        } else {
            backButton.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    onAppIdChanged: page.load()

    Keys.onEscapePressed: event => {
        page.backRequested();
        event.accepted = true;
    }

    Connections {
        target: page.store

        function onPermissionsReady(appId, list) {
            if (appId !== page.appId) {
                return;
            }
            page.permissions = list;
            page.permissionsText = list.length === 0 ? qsTr("No special access: the app runs in its sandbox only.") : "";
        }

        function onPermissionsFailed(appId, message) {
            if (appId === page.appId) {
                page.permissionsText = qsTr("Could not get the app's permissions from Flathub: %1").arg(message);
            }
        }

        function onOperationFinished(operation, appId) {
            if (appId !== page.appId) {
                return;
            }
            if (operation === "install") {
                page.showMessage(qsTr("%1 is installed.").arg(page.app.name), false);
            } else if (operation === "remove") {
                page.showMessage(qsTr("%1 was removed.").arg(page.app.name), false);
            }
            page.focusAction();
        }

        function onOperationFailed(operation, appId, message) {
            if (appId !== page.appId) {
                return;
            }
            const text = operation === "install" ? qsTr("Could not install %1: %2")
                                                 : qsTr("Could not remove %1: %2");
            page.showMessage(text.arg(page.app.name).arg(message), true);
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + 2 * Theme.spacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // Keeps the focused control in view.
        function reveal(item) {
            const p = item.mapToItem(column, 0, 0);
            if (p.y < flick.contentY) {
                flick.contentY = Math.max(0, p.y - Theme.spacing);
            } else if (p.y + item.height > flick.contentY + flick.height) {
                flick.contentY = Math.min(flick.contentHeight - flick.height, p.y + item.height - flick.height + Theme.spacing);
            }
        }

        Column {
            id: column
            x: Theme.spacing
            y: Theme.spacing
            width: flick.width - 2 * Theme.spacing
            spacing: Theme.spacing

            StoreButton {
                id: backButton
                objectName: "backButton"
                text: qsTr("Back")
                description: qsTr("Back to the list (Escape)")
                onActiveFocusChanged: if (activeFocus) flick.reveal(backButton)
                onClicked: page.backRequested()
            }

            Row {
                width: parent.width
                spacing: Theme.spacing * 2

                Item {
                    width: Theme.tileIconSize
                    height: Theme.tileIconSize

                    Image {
                        id: picture
                        anchors.fill: parent
                        source: page.app.iconUrl !== undefined ? page.app.iconUrl : ""
                        sourceSize: Qt.size(width, height)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        visible: picture.status === Image.Ready
                        Accessible.ignored: true
                    }

                    AppIcon {
                        anchors.fill: parent
                        visible: picture.status !== Image.Ready
                        name: page.app.name !== undefined ? page.app.name : ""
                    }
                }

                Column {
                    width: parent.width - Theme.tileIconSize - parent.spacing
                    spacing: Math.round(Theme.spacing / 2)

                    Text {
                        objectName: "appName"
                        width: parent.width
                        text: page.app.name !== undefined ? page.app.name : page.appId
                        color: Theme.text
                        font.family: Theme.metrics.font.family
                        font.pixelSize: Math.round(Theme.metrics.height * 1.5)
                        font.bold: true
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.Heading
                        Accessible.name: text
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: {
                            const parts = [];
                            if (page.app.developer) {
                                parts.push(page.app.verified ? qsTr("%1 (verified by Flathub)").arg(page.app.developer)
                                                             : page.app.developer);
                            } else if (page.app.verified) {
                                parts.push(qsTr("Verified by Flathub"));
                            }
                            if (page.app.license) {
                                parts.push(qsTr("Licence: %1").arg(page.app.license));
                            }
                            if (page.installed && page.app.installedVersion) {
                                parts.push(qsTr("Installed version %1").arg(page.app.installedVersion));
                            } else if (page.app.version) {
                                parts.push(qsTr("Version %1").arg(page.app.version));
                            }
                            return parts.join(" · ");
                        }
                        color: Theme.placeholder
                        font: Theme.metrics.font
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: page.app.summary !== undefined ? page.app.summary : ""
                        color: Theme.text
                        font: Theme.metrics.font
                        wrapMode: Text.Wrap
                        Accessible.role: Accessible.StaticText
                        Accessible.name: text
                    }
                }
            }

            Row {
                spacing: Theme.spacing

                StoreButton {
                    id: installButton
                    objectName: "installButton"
                    visible: !page.installed
                    enabled: !page.store.busy && page.store.state === "ready" && page.app.inCatalogue === true
                    primary: true
                    text: qsTr("Install")
                    description: qsTr("Install %1 for your user account from Flathub").arg(page.app.name)
                    onActiveFocusChanged: if (activeFocus) flick.reveal(installButton)
                    onClicked: page.store.install(page.appId)
                }

                StoreButton {
                    id: openButton
                    objectName: "openButton"
                    visible: page.installed
                    enabled: !page.working
                    primary: true
                    text: qsTr("Open")
                    description: qsTr("Start %1").arg(page.app.name)
                    onActiveFocusChanged: if (activeFocus) flick.reveal(openButton)
                    onClicked: {
                        if (!page.store.open(page.appId)) {
                            page.showMessage(qsTr("Could not start %1.").arg(page.app.name), true);
                        }
                    }
                }

                StoreButton {
                    id: removeButton
                    objectName: "removeButton"
                    visible: page.installed
                    enabled: !page.store.busy
                    text: qsTr("Remove")
                    description: qsTr("Uninstall %1. Its settings and files in your home folder are kept.").arg(page.app.name)
                    onActiveFocusChanged: if (activeFocus) flick.reveal(removeButton)
                    onClicked: page.store.remove(page.appId)
                }
            }

            Text {
                id: messageLabel
                objectName: "messageLabel"
                width: parent.width
                visible: text !== ""
                text: page.working ? (page.store.progressText !== "" ? page.store.progressText : qsTr("Working…"))
                                   : page.message
                color: page.messageIsError && !page.working ? Theme.focusRing : Theme.text
                font: Theme.metrics.font
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Text {
                width: parent.width
                text: qsTr("What this app may access")
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.bold: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            Text {
                objectName: "permissionsText"
                width: parent.width
                visible: text !== ""
                text: page.permissionsText
                color: Theme.placeholder
                font: Theme.metrics.font
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Repeater {
                objectName: "permissions"
                model: page.permissions

                Text {
                    required property string modelData
                    width: column.width
                    text: "• " + modelData
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: modelData
                }
            }

            Text {
                width: parent.width
                visible: description.text !== ""
                topPadding: Theme.spacing
                text: qsTr("About")
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.bold: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            Text {
                id: description
                objectName: "description"
                width: parent.width
                text: page.app.description !== undefined ? page.app.description : ""
                color: Theme.text
                font: Theme.metrics.font
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageDown) {
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + flick.height * 0.9);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
            flick.contentY = Math.max(0, flick.contentY - flick.height * 0.9);
            event.accepted = true;
        }
    }
}
