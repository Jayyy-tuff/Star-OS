// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import "status.js" as Status

// The desktop's System widget: processor, memory and storage in use, each a
// value and a thin bar. 'status' is StarOS.System's SystemStatus (or an
// object with cpuUsage, memoryTotal, memoryAvailable, storageTotal,
// storageFree and storageMode).
WidgetCard {
    id: root

    property var status: null

    readonly property var rows: {
        const memoryTotal = Status.value(root.status, "memoryTotal");
        const memoryUsed = memoryTotal - Status.value(root.status, "memoryAvailable");
        const storageTotal = Status.value(root.status, "storageTotal");
        const storageFree = Status.value(root.status, "storageFree");
        const cpu = root.status ? Number(root.status.cpuUsage) : -1;
        return [
            {key: "cpu", symbol: "cpu", label: qsTr("Processor"),
             value: cpu >= 0 ? cpu + " %" : qsTr("Measuring…"), fraction: cpu >= 0 ? cpu / 100 : 0},
            {key: "memory", symbol: "memory", label: qsTr("Memory"),
             value: qsTr("%1 of %2").arg(Status.formatBytes(memoryUsed)).arg(Status.formatBytes(memoryTotal)),
             fraction: Status.fraction(memoryUsed, memoryTotal)},
            {key: "storage", symbol: "disk",
             label: root.status && root.status.storageMode === "live" ? qsTr("Live session") : qsTr("Storage"),
             value: qsTr("%1 free").arg(Status.formatBytes(storageFree)),
             fraction: Status.fraction(storageTotal - storageFree, storageTotal)}
        ];
    }

    title: qsTr("System")
    symbol: "cpu"

    Repeater {
        model: root.rows

        Item {
            id: row

            required property var modelData

            objectName: row.modelData.key
            width: parent.width
            height: Math.round(2.2 * Theme.gridUnit)

            Accessible.role: Accessible.StaticText
            Accessible.name: row.modelData.label + ": " + row.modelData.value

            Symbol {
                id: rowSymbol
                anchors.left: parent.left
                y: Math.round(Theme.gridUnit * 0.1)
                width: Math.round(Theme.symbolSize * 0.85)
                height: width
                name: row.modelData.symbol
            }

            Text {
                anchors.left: rowSymbol.right
                anchors.leftMargin: Math.round(Theme.spacing / 2)
                anchors.verticalCenter: rowSymbol.verticalCenter
                text: row.modelData.label
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                Accessible.ignored: true
            }

            Text {
                objectName: "value"
                anchors.right: parent.right
                anchors.verticalCenter: rowSymbol.verticalCenter
                text: row.modelData.value
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                Accessible.ignored: true
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                height: Math.max(3, Math.round(Theme.gridUnit / 5))
                radius: height / 2
                color: Theme.glassButtonActive

                Rectangle {
                    objectName: "bar"
                    width: Math.round(parent.width * Math.min(1, Math.max(0, row.modelData.fraction)))
                    height: parent.height
                    radius: parent.radius
                    gradient: Theme.accentGradient
                }
            }
        }
    }
}
