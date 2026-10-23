// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// Star Storage: where this session keeps its changes, the disks that can keep
// them, erasing one after its name is typed, and how Star OS starts with it.
// It talks to two objects, so tests pass doubles:
//   backend  StorageBackend: state, errorString, step, partition, disks,
//            existing, uefi, canChooseBoot, alwaysStarStorage, busy,
//            message; refresh(), format(name, confirmation), setBoot(mode),
//            restartIntoStarStorage()
//   status   StarOS.System's SystemStatus: storageMode ("star-storage",
//            "live" or "installed"), storageFree, storageTotal
FocusScope {
    id: root

    required property var backend
    property var status: null

    readonly property string mode: root.status ? String(root.status.storageMode) : ""
    readonly property var selectedDisk: diskList.currentIndex >= 0 && diskList.currentIndex < root.backend.disks.length
                                        ? root.backend.disks[diskList.currentIndex] : null
    readonly property bool canErase: root.selectedDisk !== null && root.selectedDisk.usable
                                     && root.backend.state === "ready"
                                     && confirmField.text === root.selectedDisk.name
    readonly property int margin: 2 * Theme.gridUnit

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Star Storage")

    // Decimal units, as disks are sold: "32 GB", "512 MB".
    function formatBytes(bytes) {
        const units = ["B", "kB", "MB", "GB", "TB"];
        let v = Math.max(0, Number(bytes) || 0);
        let i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i += 1;
        }
        const digits = i === 0 || v >= 100 ? 0 : 1;
        return v.toFixed(digits).replace(/\.0$/, "") + " " + units[i];
    }

    // "sdc1, ntfs “Data”, 64 GB; sdc2, 1 GB" or "it has no partitions".
    function partitionSummary(disk) {
        if (!disk || disk.partitions.length === 0) {
            return qsTr("it has no partitions");
        }
        return disk.partitions.map(p => {
            const parts = [p.name];
            if (p.fstype !== "") {
                parts.push(p.label !== "" ? qsTr("%1 “%2”").arg(p.fstype).arg(p.label) : p.fstype);
            }
            parts.push(root.formatBytes(p.size));
            return parts.join(", ");
        }).join("; ");
    }

    readonly property string statusLine: {
        const free = root.formatBytes(root.status ? root.status.storageFree : 0);
        const total = root.formatBytes(root.status ? root.status.storageTotal : 0);
        if (root.mode === "star-storage") {
            return qsTr("This session keeps its changes on Star Storage: %1 free of %2.").arg(free).arg(total);
        }
        if (root.mode === "live") {
            return qsTr("This session keeps its changes in memory: they are lost when the computer is turned off.");
        }
        if (root.mode === "installed") {
            return qsTr("Star OS is installed on this computer; Star Storage is for the live medium.");
        }
        return "";
    }

    Connections {
        target: root.backend

        function onStateChanged() {
            if (root.backend.state === "done") {
                Qt.callLater(() => (root.backend.canChooseBoot ? doneRestartButton : doneText).forceActiveFocus());
            } else if (root.backend.state === "error") {
                Qt.callLater(() => errorRefreshButton.forceActiveFocus());
            } else if (root.backend.state === "ready" && !diskList.activeFocus && !confirmField.activeFocus) {
                diskList.forceActiveFocus();
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 2 * root.margin
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: content
            x: Math.max(root.margin, (flick.width - width) / 2)
            y: root.margin
            width: Math.min(flick.width - 2 * root.margin, 44 * Theme.gridUnit)
            spacing: Theme.spacing

            Text {
                objectName: "title"
                width: parent.width
                text: qsTr("Star Storage")
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.metrics.height * 1.6)
                font.bold: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            Text {
                width: parent.width
                text: qsTr("Star Storage keeps your files, settings and the apps you install on a disk you choose, so they are still there the next time you start this version of Star OS with Star Storage.")
                color: Theme.text
                font: Theme.metrics.font
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            Text {
                objectName: "statusText"
                width: parent.width
                visible: text !== ""
                text: root.statusLine
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.bold: true
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            ShellButton {
                id: alwaysButton
                objectName: "alwaysButton"
                visible: root.mode === "star-storage" && root.backend.canChooseBoot
                enabled: !root.backend.busy
                text: root.backend.alwaysStarStorage ? qsTr("Always start with Star Storage: on")
                                                     : qsTr("Always start with Star Storage: off")
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Always start with Star Storage")
                Accessible.checkable: true
                Accessible.checked: root.backend.alwaysStarStorage
                onClicked: root.backend.setBoot(root.backend.alwaysStarStorage ? "never" : "always")
            }

            // Star Storage exists on a disk, but this session does not use it.
            Column {
                objectName: "existingPanel"
                width: parent.width
                spacing: Theme.spacing
                visible: root.backend.existing.length > 0 && root.mode !== "star-storage"
                         && root.backend.state !== "done" && root.backend.state !== "working"

                Text {
                    width: parent.width
                    text: qsTr("Star Storage is set up on %1.").arg(root.backend.existing.join(", "))
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                ShellButton {
                    objectName: "restartButton"
                    visible: root.backend.canChooseBoot
                    enabled: !root.backend.busy
                    text: qsTr("Restart into Star Storage")
                    description: qsTr("Star OS starts with Star Storage once; the boot menu still offers both.")
                    onClicked: root.backend.restartIntoStarStorage()
                }
                Text {
                    width: parent.width
                    visible: !root.backend.canChooseBoot
                    text: qsTr("To use it, restart the computer and choose “Star OS live (prototype) with Star Storage” in the boot menu.")
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            Text {
                width: parent.width
                topPadding: Theme.spacing
                text: qsTr("Disks")
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.bold: true
                Accessible.role: Accessible.Heading
                Accessible.name: text
            }

            ListView {
                id: diskList
                objectName: "disks"
                width: parent.width
                height: contentHeight
                interactive: false
                model: root.backend.disks
                currentIndex: -1
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                activeFocusOnTab: true
                spacing: 2

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Disks")
                Accessible.description: qsTr("Choose the disk for Star Storage")

                onModelChanged: currentIndex = -1
                onCurrentIndexChanged: confirmField.text = ""
                onActiveFocusChanged: {
                    if (activeFocus && currentIndex < 0 && count > 0) {
                        currentIndex = 0;
                    }
                }

                delegate: DiskRow {
                    id: diskRow
                    width: diskList.width
                    current: ListView.isCurrentItem
                    formatBytes: bytes => root.formatBytes(bytes)
                    onClicked: {
                        diskList.currentIndex = diskRow.index;
                        diskList.forceActiveFocus(Qt.MouseFocusReason);
                    }
                }

                FocusFrame {
                    visible: diskList.activeFocus
                    radius: Theme.controlRadius
                }
            }

            Text {
                objectName: "listState"
                width: parent.width
                visible: text !== ""
                text: root.backend.state === "loading" ? qsTr("Looking for disks…")
                    : diskList.count === 0 && root.backend.state === "ready" ? qsTr("No disks found. Connect one and look again.")
                    : ""
                color: Theme.placeholder
                font: Theme.metrics.font
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            ShellButton {
                objectName: "refreshButton"
                visible: root.backend.state === "ready"
                text: qsTr("Look again")
                description: qsTr("List the disks again, for example after connecting one")
                onClicked: root.backend.refresh()
            }

            // The chosen disk: why it cannot be used, or what erasing it deletes.
            Column {
                objectName: "details"
                width: parent.width
                spacing: Theme.spacing
                visible: root.selectedDisk !== null && root.backend.state === "ready"

                Text {
                    objectName: "reasonText"
                    width: parent.width
                    visible: root.selectedDisk !== null && !root.selectedDisk.usable
                    text: root.selectedDisk ? qsTr("%1 cannot be used. %2").arg(root.selectedDisk.name)
                                                                         .arg(root.selectedDisk.reasonText) : ""
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Text {
                    objectName: "warning"
                    width: parent.width
                    visible: root.selectedDisk !== null && root.selectedDisk.usable
                    text: root.selectedDisk ? qsTr("Erasing %1 deletes everything on it (%2). What you did in this session is not copied to Star Storage.")
                                              .arg(root.selectedDisk.name).arg(root.partitionSummary(root.selectedDisk)) : ""
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }

                Text {
                    id: confirmLabel
                    width: parent.width
                    visible: confirmField.visible
                    text: root.selectedDisk ? qsTr("Type %1 to confirm:").arg(root.selectedDisk.name) : ""
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.ignored: true
                }

                T.TextField {
                    id: confirmField
                    objectName: "confirmField"
                    width: Math.min(parent.width, 16 * Theme.gridUnit)
                    implicitHeight: Theme.minTarget
                    visible: root.selectedDisk !== null && root.selectedDisk.usable
                    leftPadding: Theme.spacing
                    rightPadding: Theme.spacing
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.text
                    font: Theme.metrics.font
                    selectByMouse: true
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    Accessible.name: qsTr("Disk name to confirm")
                    Accessible.description: confirmLabel.text

                    background: Rectangle {
                        radius: Math.round(Theme.spacing / 2)
                        color: Theme.searchField
                        border.width: 1
                        border.color: Theme.searchBorder
                    }

                    Keys.onReturnPressed: event => {
                        if (root.canErase) {
                            root.backend.format(root.selectedDisk.name, confirmField.text);
                        }
                        event.accepted = true;
                    }

                    FocusFrame {
                        visible: confirmField.activeFocus
                    }
                }

                ShellButton {
                    objectName: "eraseButton"
                    visible: confirmField.visible
                    enabled: root.canErase
                    opacity: enabled ? 1 : 0.5
                    text: qsTr("Erase and set up")
                    description: root.selectedDisk ? qsTr("Erases %1 and makes it Star Storage").arg(root.selectedDisk.name) : ""
                    onClicked: root.backend.format(root.selectedDisk.name, confirmField.text)
                }
            }

            Column {
                objectName: "working"
                width: parent.width
                spacing: Theme.spacing
                visible: root.backend.state === "working"

                Text {
                    id: stepText
                    objectName: "stepText"
                    width: parent.width
                    text: root.backend.step
                    color: Theme.text
                    font.family: Theme.metrics.font.family
                    font.bold: true
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                    onTextChanged: {
                        if (stepText.visible && stepText.text !== "") {
                            stepText.Accessible.announce(stepText.text);
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: qsTr("Keep the disk connected until this is finished.")
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            Column {
                objectName: "donePanel"
                width: parent.width
                spacing: Theme.spacing
                visible: root.backend.state === "done"

                Text {
                    id: doneText
                    objectName: "doneText"
                    width: parent.width
                    text: qsTr("Star Storage is ready on %1.").arg(root.backend.partition)
                    color: Theme.text
                    font.family: Theme.metrics.font.family
                    font.bold: true
                    wrapMode: Text.Wrap
                    activeFocusOnTab: true
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                    Accessible.focusable: true

                    FocusFrame {
                        visible: doneText.activeFocus
                    }
                }
                ShellButton {
                    id: doneRestartButton
                    objectName: "doneRestartButton"
                    visible: root.backend.canChooseBoot
                    enabled: !root.backend.busy
                    text: qsTr("Restart into Star Storage")
                    description: qsTr("Star OS starts with Star Storage once; the boot menu still offers both.")
                    onClicked: root.backend.restartIntoStarStorage()
                }
                Text {
                    objectName: "biosText"
                    width: parent.width
                    visible: !root.backend.canChooseBoot
                    text: qsTr("To use it, restart the computer and choose “Star OS live (prototype) with Star Storage” in the boot menu.")
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacing
                visible: root.backend.state === "error"

                Text {
                    objectName: "errorText"
                    width: parent.width
                    text: root.backend.errorString
                    color: Theme.text
                    font: Theme.metrics.font
                    wrapMode: Text.Wrap
                    Accessible.role: Accessible.StaticText
                    Accessible.name: text
                }
                ShellButton {
                    id: errorRefreshButton
                    objectName: "errorRefreshButton"
                    text: qsTr("Look again")
                    onClicked: root.backend.refresh()
                }
            }

            Text {
                id: messageLabel
                objectName: "message"
                width: parent.width
                visible: text !== ""
                text: root.backend.message
                color: Theme.text
                font: Theme.metrics.font
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
                onTextChanged: {
                    if (messageLabel.text !== "") {
                        messageLabel.Accessible.announce(messageLabel.text);
                    }
                }
            }
        }
    }
}
