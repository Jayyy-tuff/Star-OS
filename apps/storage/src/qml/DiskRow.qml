// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// One disk in Star Storage's list: model, size and connection, and why it
// cannot be used when it cannot.
T.ItemDelegate {
    id: row

    // A row of the helper's disks (a JS array model).
    required property var modelData
    required property int index
    readonly property var disk: row.modelData
    property bool current: false
    // "12 GB" and the like; set by the view.
    property var formatBytes: bytes => String(bytes)

    readonly property string title: (row.disk.model !== "" ? row.disk.model : row.disk.name)
        + " · " + row.formatBytes(row.disk.size)
    readonly property string detail: {
        const parts = [row.disk.name];
        if (row.disk.transport !== "") {
            parts.push(row.disk.transport.toUpperCase());
        }
        if (row.disk.starStorage) {
            parts.push(qsTr("has Star Storage"));
        }
        if (!row.disk.usable) {
            parts.push(row.disk.reasonText);
        }
        return parts.join(" · ");
    }

    implicitHeight: Math.max(Theme.minTarget, column.implicitHeight + Theme.spacing)
    focusPolicy: Qt.NoFocus

    Accessible.role: Accessible.ListItem
    Accessible.name: row.title
    Accessible.description: row.detail
    Accessible.selected: row.current

    background: Rectangle {
        radius: Theme.controlRadius
        color: row.current ? Theme.glassButtonActive : row.down ? Theme.glassButtonPressed : "transparent"
    }

    contentItem: Column {
        id: column
        spacing: 2

        Text {
            width: parent.width
            text: row.title
            color: row.disk.usable ? Theme.text : Theme.placeholder
            font: Theme.metrics.font
            elide: Text.ElideRight
            Accessible.ignored: true
        }
        Text {
            width: parent.width
            text: row.detail
            color: Theme.placeholder
            font: Theme.metrics.font
            elide: Text.ElideRight
            Accessible.ignored: true
        }
    }
}
