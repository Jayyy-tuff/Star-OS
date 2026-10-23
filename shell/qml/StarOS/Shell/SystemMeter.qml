// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

// The taskbar's storage and system meter: two small bars (storage and memory
// in use) and the free storage. Its description says where changes are kept,
// how much memory is in use and the battery level. Activating it asks the
// host to show the details (Star Storage).
//
// `status` is any object with: storageMode ("star-storage", "live" or
// "installed"), storageTotal and storageFree (bytes), memoryTotal and
// memoryAvailable (bytes), batteryPresent, batteryPercent and charging:
// StarOS.System's SystemStatus in the session, a plain object in tests.
T.AbstractButton {
    id: control

    property var status: null

    readonly property real storageUsed: control.fraction(
        control.value("storageTotal") - control.value("storageFree"), control.value("storageTotal"))
    readonly property real memoryUsed: control.fraction(
        control.value("memoryTotal") - control.value("memoryAvailable"), control.value("memoryTotal"))
    readonly property string mode: control.status ? String(control.status.storageMode) : ""

    readonly property string storageLine: {
        const free = control.formatBytes(control.value("storageFree"));
        const total = control.formatBytes(control.value("storageTotal"));
        if (control.mode === "star-storage") {
            return qsTr("Star Storage: %1 free of %2.").arg(free).arg(total);
        }
        if (control.mode === "live") {
            return qsTr("Live session: changes are lost at shutdown. %1 free of %2.").arg(free).arg(total);
        }
        return qsTr("Storage: %1 free of %2.").arg(free).arg(total);
    }
    readonly property string memoryLine: qsTr("Memory: %1 of %2 in use.")
        .arg(control.formatBytes(control.value("memoryTotal") - control.value("memoryAvailable")))
        .arg(control.formatBytes(control.value("memoryTotal")))
    readonly property string batteryLine: control.status && control.status.batteryPresent
        ? (control.status.charging ? qsTr("Battery: %1 %, charging.") : qsTr("Battery: %1 %."))
            .arg(Math.round(control.value("batteryPercent")))
        : ""
    readonly property string summary: [control.storageLine, control.memoryLine, control.batteryLine]
        .filter(line => line !== "").join(" ")

    function value(name) {
        const v = control.status ? Number(control.status[name]) : 0;
        return isFinite(v) ? v : 0;
    }

    function fraction(part, whole) {
        return whole > 0 ? Math.min(1, Math.max(0, part / whole)) : 0;
    }

    // Decimal units, as disks are sold: "9.8 GB", "16 GB", "512 MB".
    function formatBytes(bytes) {
        const units = ["B", "kB", "MB", "GB", "TB"];
        let v = Math.max(0, bytes);
        let i = 0;
        while (v >= 1000 && i < units.length - 1) {
            v /= 1000;
            i += 1;
        }
        const digits = i === 0 || v >= 100 ? 0 : 1;
        return v.toFixed(digits).replace(/\.0$/, "") + " " + units[i];
    }

    text: control.mode === "live" ? qsTr("Live · %1 free").arg(control.formatBytes(control.value("storageFree")))
                                  : qsTr("%1 free").arg(control.formatBytes(control.value("storageFree")))
    implicitWidth: Math.max(Theme.minTarget, bars.width + label.implicitWidth + 3 * Theme.spacing)
    implicitHeight: Theme.minTarget
    focusPolicy: Qt.StrongFocus

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("System status")
    Accessible.description: control.summary

    Keys.onReturnPressed: event => {
        control.clicked();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        control.clicked();
        event.accepted = true;
    }

    background: Rectangle {
        radius: Theme.controlRadius
        color: control.down ? Theme.glassButtonPressed : Theme.glassButton
    }

    contentItem: Item {
        Row {
            id: bars
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.max(2, Math.round(Theme.spacing / 3))

            Repeater {
                model: [
                    {name: "storageBar", used: control.storageUsed},
                    {name: "memoryBar", used: control.memoryUsed}
                ]

                // A vertical bar, filled from the bottom by the share in use.
                Rectangle {
                    id: bar
                    required property var modelData
                    objectName: bar.modelData.name
                    width: Math.max(4, Math.round(Theme.spacing * 0.75))
                    height: Math.round(Theme.minTarget * 0.6)
                    radius: 2
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.placeholder
                    Accessible.ignored: true

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 1
                        height: Math.round((parent.height - 2) * bar.modelData.used)
                        color: bar.modelData.used > 0.9 ? Theme.focusRing : Theme.activeIndicator
                    }
                }
            }
        }

        Text {
            id: label
            objectName: "label"
            anchors.left: bars.right
            anchors.leftMargin: Theme.spacing
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: control.text
            color: Theme.text
            font: Theme.metrics.font
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius
    }
}
