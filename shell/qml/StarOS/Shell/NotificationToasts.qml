// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick

// New notifications as toasts, newest on top, each on glass. A toast goes
// after its timeout (the notification's own, else Theme's 5 s; critical ones
// stay) unless the pointer rests on it; the host expires it in the model.
//
// The model has libnotificationmanager's roles: summary, body,
// applicationName, applicationIconName, desktopEntry, created, actionNames,
// actionLabels, hasDefaultAction, closable, urgency (criticalUrgency, 4 in
// libnotificationmanager, is critical) and
// timeout (milliseconds; 0 never, -1 the default).
Item {
    id: root

    property var model: null
    property Component iconFallback: null
    // Where the toasts are on the screen, for the glass.
    property point glassOrigin: Qt.point(0, 0)
    property size screenSize: Qt.size(root.width, root.height)
    property int defaultTimeout: 5000
    property int criticalUrgency: 4

    readonly property int count: list.count

    signal expireRequested(int row)
    signal closeRequested(int row)
    signal defaultActionRequested(int row)
    signal actionRequested(int row, string actionName)

    implicitWidth: 21 * Theme.gridUnit
    implicitHeight: list.contentHeight

    Accessible.role: Accessible.List
    Accessible.name: qsTr("New notifications")

    ListView {
        id: list
        objectName: "toasts"
        anchors.fill: parent
        model: root.model
        spacing: Theme.spacing
        interactive: false

        delegate: Item {
            id: toast

            required property var model
            required property int index

            width: list.width
            height: card.implicitHeight

            readonly property int timeout: toast.model.urgency === root.criticalUrgency || toast.model.timeout === 0 ? 0
                : toast.model.timeout > 0 ? toast.model.timeout : root.defaultTimeout

            GlassPanel {
                anchors.fill: parent
                radius: Theme.controlRadius * 1.3
                wallpaperOrigin: Qt.point(root.glassOrigin.x + toast.x, root.glassOrigin.y + toast.y - list.contentY)
                screenSize: root.screenSize
            }

            NotificationCard {
                id: card
                anchors.fill: parent
                appName: toast.model.applicationName ?? ""
                appId: toast.model.desktopEntry ?? ""
                iconData: toast.model.applicationIconName
                iconFallback: root.iconFallback
                summary: toast.model.summary ?? ""
                body: toast.model.body ?? ""
                created: toast.model.created ?? new Date()
                actionNames: toast.model.actionNames ?? []
                actionLabels: toast.model.actionLabels ?? []
                hasDefaultAction: toast.model.hasDefaultAction === true
                closable: toast.model.closable !== false
                critical: toast.model.urgency === root.criticalUrgency
                timeLeft: toast.timeout > 0 ? 1 - progress.elapsed / toast.timeout : -1
                onClicked: {
                    if (card.hasDefaultAction) {
                        root.defaultActionRequested(toast.index);
                    } else {
                        root.expireRequested(toast.index);
                    }
                }
                onCloseRequested: root.closeRequested(toast.index)
                onActionRequested: actionName => root.actionRequested(toast.index, actionName)
            }

            // Counts down while the pointer is not on the toast.
            Timer {
                id: progress
                property int elapsed: 0
                interval: 100
                repeat: true
                running: toast.timeout > 0 && !card.hovered
                onTriggered: {
                    progress.elapsed += progress.interval;
                    if (progress.elapsed >= toast.timeout) {
                        progress.stop();
                        root.expireRequested(toast.index);
                    }
                }
            }
        }

        add: Transition {
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: Theme.durationMedium
            }
            NumberAnimation {
                property: "x"
                from: Theme.gridUnit
                duration: Theme.durationMedium
                easing.type: Easing.OutCubic
            }
        }
    }
}
