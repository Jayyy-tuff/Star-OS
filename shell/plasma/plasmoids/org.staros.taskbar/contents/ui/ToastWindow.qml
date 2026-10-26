// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import StarOS.Shell

// New notifications at the top right: a layer-shell window as large as the
// toasts plus a transparent margin, above windows, that never takes the
// keyboard. Like the shell overlay it has no transient parent: tied to the
// panel's window, it would not become a layer surface of its own.
Window {
    id: win

    property alias model: toasts.model
    property Component iconFallback: null
    readonly property int margin: Theme.launcherMargin

    signal expireRequested(int row)
    signal closeRequested(int row)
    signal defaultActionRequested(int row)
    signal actionRequested(int row, string actionName)

    visible: toasts.count > 0
    transientParent: null
    width: toasts.implicitWidth + win.margin
    height: Math.max(1, toasts.implicitHeight + win.margin)
    title: qsTr("Notifications")
    color: "transparent"

    LayerShell.Window.scope: "staros-notifications"
    LayerShell.Window.layer: LayerShell.Window.LayerTop
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    NotificationToasts {
        id: toasts
        x: 0
        y: win.margin
        width: implicitWidth
        height: implicitHeight
        iconFallback: win.iconFallback
        glassOrigin: Qt.point(Screen.width - win.width, win.margin)
        screenSize: Qt.size(Screen.width, Screen.height)
        onExpireRequested: row => win.expireRequested(row)
        onCloseRequested: row => win.closeRequested(row)
        onDefaultActionRequested: row => win.defaultActionRequested(row)
        onActionRequested: (row, actionName) => win.actionRequested(row, actionName)
    }
}
