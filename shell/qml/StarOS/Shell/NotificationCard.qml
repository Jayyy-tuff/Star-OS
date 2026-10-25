// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T

// One notification: the app's icon and name, when it came, the summary, the
// body (simple markup such as bold and links) and its actions. Activating
// the card runs the default action when there is one. A toast shows a
// thinner bar that empties until it goes.
T.AbstractButton {
    id: control

    property string appName: ""
    property string appId: ""
    property var iconData: undefined
    property Component iconFallback: null
    property string summary: ""
    property string body: ""
    property date created: new Date()
    property date now: new Date()
    property var actionNames: []
    property var actionLabels: []
    property bool hasDefaultAction: false
    property bool closable: true
    property bool critical: false
    // 0..1 of a toast's time left; negative hides the bar.
    property real timeLeft: -1

    signal closeRequested()
    signal actionRequested(string actionName)

    readonly property string age: {
        const minutes = Math.round((control.now.getTime() - control.created.getTime()) / 60000);
        if (!isFinite(minutes) || minutes < 1) {
            return qsTr("now");
        }
        if (minutes < 60) {
            return qsTr("%1 min").arg(minutes);
        }
        if (minutes < 24 * 60) {
            return qsTr("%1 h").arg(Math.round(minutes / 60));
        }
        return Qt.formatDate(control.created, "d MMM");
    }

    text: control.summary
    implicitWidth: 21 * Theme.gridUnit
    implicitHeight: column.implicitHeight + 2 * Theme.spacing * 1.25
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true

    Accessible.role: Accessible.Button
    Accessible.name: control.appName !== "" ? control.appName + ": " + control.summary : control.summary
    Accessible.description: control.body.replace(/<[^>]*>/g, "")

    Keys.onReturnPressed: event => {
        control.clicked();
        event.accepted = true;
    }
    Keys.onDeletePressed: event => {
        if (control.closable) {
            control.closeRequested();
        }
        event.accepted = true;
    }

    background: Rectangle {
        radius: Theme.controlRadius * 1.3
        color: control.down ? Theme.glassButtonActive : control.hovered ? Theme.glassButton : Theme.tileGlass
        border.width: 1
        border.color: control.critical ? Theme.focusRing : Theme.glassBorder

        Rectangle {
            objectName: "timeLeft"
            visible: control.timeLeft >= 0
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: parent.radius
            anchors.bottomMargin: 1
            width: Math.max(0, (parent.width - 2 * parent.radius) * control.timeLeft)
            height: 2
            radius: 1
            color: Theme.activeIndicator
            opacity: 0.6
        }
    }

    contentItem: Item {
        AppIcon {
            id: icon
            objectName: "icon"
            x: Math.round(Theme.spacing * 1.25)
            y: Math.round(Theme.spacing * 1.25)
            width: Theme.rowIconSize
            height: Theme.rowIconSize
            appId: control.appId
            name: control.appName !== "" ? control.appName : control.summary
            iconData: control.iconData
            fallback: control.iconFallback
        }

        Column {
            id: column
            anchors.left: icon.right
            anchors.leftMargin: Theme.spacing
            anchors.right: parent.right
            anchors.rightMargin: Math.round(Theme.spacing * 1.25)
            y: Math.round(Theme.spacing * 1.25)
            spacing: 2

            Item {
                width: parent.width
                height: Math.max(appLabel.implicitHeight, closeButton.height)

                Text {
                    id: appLabel
                    anchors.left: parent.left
                    anchors.right: ageLabel.left
                    anchors.rightMargin: Theme.spacing / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: control.appName
                    color: Theme.textSecondary
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.smallPixelSize
                    elide: Text.ElideRight
                    Accessible.ignored: true
                }

                Text {
                    id: ageLabel
                    objectName: "age"
                    anchors.right: closeButton.left
                    anchors.rightMargin: Theme.spacing / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: control.age
                    color: Theme.textSecondary
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.smallPixelSize
                    Accessible.ignored: true
                }

                ShellButton {
                    id: closeButton
                    objectName: "closeButton"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(1.4 * Theme.gridUnit)
                    height: width
                    flat: true
                    iconOnly: true
                    symbol: "close"
                    text: qsTr("Close")
                    visible: control.closable
                    focusPolicy: Qt.TabFocus
                    onClicked: control.closeRequested()
                }
            }

            Text {
                objectName: "summary"
                width: parent.width
                text: control.summary
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(Theme.fontSize)
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Accessible.ignored: true
            }

            Text {
                objectName: "body"
                width: parent.width
                visible: text !== ""
                text: control.body
                textFormat: Text.StyledText
                color: Theme.textSecondary
                linkColor: Theme.activeIndicator
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
                Accessible.ignored: true
            }

            Row {
                objectName: "actions"
                topPadding: Theme.spacing / 2
                spacing: Theme.spacing / 2
                visible: control.actionNames.length > 0

                Repeater {
                    model: control.actionNames

                    ShellButton {
                        id: actionButton

                        required property string modelData
                        required property int index

                        height: Math.round(1.7 * Theme.gridUnit)
                        radius: height / 2
                        highlighted: actionButton.index === 0
                        text: control.actionLabels[actionButton.index] ?? actionButton.modelData
                        onClicked: control.actionRequested(actionButton.modelData)
                    }
                }
            }
        }
    }

    FocusFrame {
        visible: control.activeFocus
        radius: Theme.controlRadius * 1.3
    }
}
