// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

// The clipboard history (M0.5, ADR-0014), opened with Meta+V: a glass panel
// above the taskbar, centred, listing the last copies, newest first. Return
// or a click copies the chosen one again, Delete forgets it, "Clear" forgets
// them all. Escape or a click outside closes it.
//
// 'history' is StarOS.System's ClipboardHistory: a list model with the
// roles kind ("text" or "image"), text, thumbnail (an image URL),
// description and copiedAt, and the functions copy(row), remove(row) and
// clear(). Tests pass the functions and a ListModel ('model') apart.
FocusScope {
    id: root

    property var history: null
    property var model: root.history
    property bool shown: true
    property date now: new Date()

    readonly property int count: list.count

    signal closeRequested()
    // A copy went back on the clipboard; the host closes the panel.
    signal copied()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Clipboard history")

    // Called by the host every time the panel is shown.
    function reset() {
        root.now = new Date();
        list.currentIndex = 0;
        list.positionViewAtBeginning();
        if (list.count > 0) {
            list.forceActiveFocus(Qt.OtherFocusReason);
        } else {
            root.forceActiveFocus(Qt.OtherFocusReason);
        }
    }

    function copyRow(row) {
        if (root.history && row >= 0 && row < list.count) {
            root.history.copy(row);
            root.copied();
        }
    }

    function age(copiedAt) {
        const minutes = Math.round((root.now.getTime() - new Date(copiedAt).getTime()) / 60000);
        if (!isFinite(minutes) || minutes < 1) {
            return qsTr("Copied just now");
        }
        if (minutes < 60) {
            return qsTr("Copied %1 min ago").arg(minutes);
        }
        return qsTr("Copied at %1").arg(Qt.formatTime(new Date(copiedAt), Qt.locale().timeFormat(Locale.ShortFormat)));
    }

    Keys.onEscapePressed: event => {
        root.closeRequested();
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.scrim
        opacity: root.shown ? 1 : 0
        Accessible.ignored: true

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.durationMedium
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    GlassPanel {
        id: panel
        objectName: "panel"
        width: Math.min(Math.round(26 * Theme.gridUnit), root.width - 2 * Theme.spacing)
        height: Math.min(column.implicitHeight + 2 * Theme.panelPadding, panel.bottomEdge - Theme.popupGap)
        x: Math.round((root.width - panel.width) / 2)
        y: Math.round(panel.bottomEdge - panel.height)
        shown: root.shown
        wallpaperOrigin: Qt.point(panel.x, panel.y)
        screenSize: Qt.size(root.width, root.height)

        readonly property real bottomEdge: root.height - Theme.taskbarGap - Theme.taskbarPillHeight - Theme.popupGap

        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            x: Theme.panelPadding
            y: Theme.panelPadding
            width: panel.width - 2 * Theme.panelPadding
            spacing: Theme.spacing

            Item {
                width: parent.width
                height: Math.max(heading.implicitHeight, clearButton.height)

                Text {
                    id: heading
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Clipboard")
                    color: Theme.text
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.headingPixelSize
                    font.weight: Font.DemiBold
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }

                ShellButton {
                    id: clearButton
                    objectName: "clearButton"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(1.7 * Theme.gridUnit)
                    radius: height / 2
                    visible: list.count > 0
                    symbol: "trash"
                    text: qsTr("Clear")
                    description: qsTr("Forget every copy")
                    onClicked: {
                        root.history.clear();
                        root.forceActiveFocus(Qt.OtherFocusReason);
                    }
                }
            }

            Text {
                objectName: "emptyState"
                width: parent.width
                visible: list.count === 0
                text: qsTr("Nothing copied yet. Text and images you copy appear here.")
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize)
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }

            ListView {
                id: list
                objectName: "clipboardList"
                width: parent.width
                height: Math.min(contentHeight, Math.max(0, panel.bottomEdge - Theme.popupGap - 2 * Theme.panelPadding
                    - clearButton.height - hint.implicitHeight - 2 * Theme.spacing))
                visible: count > 0
                clip: true
                spacing: Theme.spacing / 2
                model: root.model
                keyNavigationEnabled: true
                highlightMoveDuration: 0
                activeFocusOnTab: count > 0
                boundsBehavior: Flickable.StopAtBounds

                Accessible.role: Accessible.List
                Accessible.name: qsTr("Copies")

                delegate: T.AbstractButton {
                    id: row

                    required property int index
                    required property var model

                    readonly property bool image: row.model.kind === "image"
                    readonly property string preview: row.model.text ?? ""
                    readonly property string detail: row.model.description ?? ""
                    readonly property var copiedAt: row.model.copiedAt

                    width: list.width
                    height: Math.max(Theme.rowHeight, content.implicitHeight + Theme.spacing * 1.5)
                    focus: row.ListView.isCurrentItem
                    focusPolicy: Qt.StrongFocus
                    hoverEnabled: true

                    Accessible.role: Accessible.Button
                    text: row.image ? row.detail : row.preview
                    Accessible.name: row.text
                    Accessible.description: (row.image ? "" : row.detail + ". ") + root.age(row.copiedAt)

                    Keys.onReturnPressed: event => {
                        root.copyRow(row.index);
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        root.copyRow(row.index);
                        event.accepted = true;
                    }
                    Keys.onDeletePressed: event => {
                        root.history.remove(row.index);
                        event.accepted = true;
                    }

                    onClicked: root.copyRow(row.index)

                    background: Rectangle {
                        radius: Theme.controlRadius
                        color: row.down ? Theme.glassButtonPressed
                            : row.hovered || row.activeFocus ? Theme.glassButton : Theme.tileGlass
                        border.width: 1
                        border.color: Theme.glassBorder
                    }

                    contentItem: Item {
                        Column {
                            id: content
                            x: Theme.spacing
                            y: Math.round(Theme.spacing * 0.75)
                            width: row.width - 2 * Theme.spacing - removeButton.width
                            spacing: 2

                            Image {
                                objectName: "thumbnail"
                                visible: row.image
                                width: Math.min(parent.width, sourceSize.width > 0 ? sourceSize.width : parent.width)
                                height: visible ? Math.min(Math.round(7 * Theme.gridUnit), implicitHeight) : 0
                                source: row.image ? row.model.thumbnail : ""
                                fillMode: Image.PreserveAspectFit
                                horizontalAlignment: Image.AlignLeft
                                Accessible.ignored: true
                            }

                            Text {
                                objectName: "preview"
                                width: parent.width
                                visible: !row.image
                                text: row.preview
                                color: Theme.text
                                font.family: Theme.metrics.font.family
                                font.pixelSize: Math.round(Theme.fontSize)
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                                Accessible.ignored: true
                            }

                            Text {
                                width: parent.width
                                text: row.image ? row.detail + " · " + root.age(row.copiedAt) : root.age(row.copiedAt)
                                color: Theme.textSecondary
                                font.family: Theme.metrics.font.family
                                font.pixelSize: Theme.smallPixelSize
                                elide: Text.ElideRight
                                Accessible.ignored: true
                            }
                        }

                        ShellButton {
                            id: removeButton
                            objectName: "removeButton"
                            anchors.right: parent.right
                            anchors.rightMargin: Math.round(Theme.spacing / 2)
                            anchors.top: parent.top
                            anchors.topMargin: Math.round(Theme.spacing / 2)
                            width: Math.round(1.6 * Theme.gridUnit)
                            height: width
                            flat: true
                            iconOnly: true
                            symbol: "close"
                            text: qsTr("Forget this copy")
                            focusPolicy: Qt.TabFocus
                            onClicked: root.history.remove(row.index)
                        }
                    }

                    FocusFrame {
                        visible: row.activeFocus
                        radius: Theme.controlRadius
                    }
                }
            }

            Text {
                id: hint
                objectName: "hint"
                width: parent.width
                text: qsTr("Select a copy to put it back on the clipboard. Copies stay in memory until you log out.")
                color: Theme.textTertiary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                wrapMode: Text.Wrap
                Accessible.role: Accessible.StaticText
                Accessible.name: text
            }
        }
    }
}
