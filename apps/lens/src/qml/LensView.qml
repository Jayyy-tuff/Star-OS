// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import StarOS.Shell

// The Star Lens screen: the frozen screenshot, dimmed outside the selection.
// Drag to select (or Ctrl+A for everything, arrows to move, Shift+arrows to
// resize, Return to read it); Escape closes. Results appear beside the
// selection. It only talks to `lens`, so tests pass a double:
//   lens  LensBackend: state, errorString, captureUrl, captureSize, text,
//         code, codeFormat, links, recognitionError, message; select(x, y,
//         width, height) in capture pixels, selectAgain(), copyText(),
//         copyCode(), copyImage(), saveImage(), searchWeb(), openLink(link),
//         openGoogleLens().
FocusScope {
    id: root

    required property var lens

    // The selection in view coordinates.
    property rect area: Qt.rect(0, 0, 0, 0)
    property point anchorPoint: Qt.point(0, 0)

    readonly property bool hasArea: root.area.width >= 8 && root.area.height >= 8
    readonly property real scaleX: root.lens.captureSize.width > 0 && root.width > 0
                                   ? root.lens.captureSize.width / root.width : 1
    readonly property real scaleY: root.lens.captureSize.height > 0 && root.height > 0
                                   ? root.lens.captureSize.height / root.height : 1
    readonly property size screenSize: Qt.size(root.width, root.height)
    readonly property int step: Theme.gridUnit

    signal closeRequested()

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Star Lens")

    function selectAll() {
        root.area = Qt.rect(0, 0, root.width, root.height);
    }

    function confirm() {
        if (root.lens.state !== "selecting") {
            return;
        }
        if (!root.hasArea) {
            root.selectAll();
        }
        root.lens.select(root.area.x * root.scaleX, root.area.y * root.scaleY,
                         root.area.width * root.scaleX, root.area.height * root.scaleY);
    }

    // Moves the selection, or with resize changes its size; it stays on screen.
    function nudge(dx, dy, resize) {
        if (!root.hasArea) {
            const w = Math.min(root.width, 20 * Theme.gridUnit);
            const h = Math.min(root.height, 10 * Theme.gridUnit);
            root.area = Qt.rect((root.width - w) / 2, (root.height - h) / 2, w, h);
            return;
        }
        let a = root.area;
        if (resize) {
            const w = Math.max(8, Math.min(root.width - a.x, a.width + dx));
            const h = Math.max(8, Math.min(root.height - a.y, a.height + dy));
            root.area = Qt.rect(a.x, a.y, w, h);
        } else {
            const x = Math.max(0, Math.min(root.width - a.width, a.x + dx));
            const y = Math.max(0, Math.min(root.height - a.height, a.y + dy));
            root.area = Qt.rect(x, y, a.width, a.height);
        }
    }

    Keys.onPressed: event => {
        const state = root.lens.state;
        if (event.key === Qt.Key_Escape) {
            if (state === "results") {
                root.lens.selectAgain();
            } else {
                root.closeRequested();
            }
            event.accepted = true;
            return;
        }
        if (state !== "selecting") {
            return;
        }
        const resize = (event.modifiers & Qt.ShiftModifier) !== 0;
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
            root.selectAll();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.confirm();
        } else if (event.key === Qt.Key_Left) {
            root.nudge(-root.step, 0, resize);
        } else if (event.key === Qt.Key_Right) {
            root.nudge(root.step, 0, resize);
        } else if (event.key === Qt.Key_Up) {
            root.nudge(0, -root.step, resize);
        } else if (event.key === Qt.Key_Down) {
            root.nudge(0, root.step, resize);
        } else {
            return;
        }
        event.accepted = true;
    }

    Connections {
        target: root.lens

        function onStateChanged() {
            if (root.lens.state === "results") {
                results.focusFirst();
            } else if (root.lens.state === "selecting") {
                root.forceActiveFocus(Qt.OtherFocusReason);
            }
        }
    }

    Image {
        id: shot
        objectName: "capture"
        anchors.fill: parent
        source: root.lens.captureUrl
        cache: false
        fillMode: Image.Stretch
        smooth: true
        visible: root.lens.state !== "error"
        Accessible.ignored: true
    }

    // Dims everything but the selection.
    Item {
        anchors.fill: parent
        visible: shot.visible

        Rectangle {
            width: parent.width
            height: root.hasArea ? root.area.y : parent.height
            color: "black"
            opacity: 0.45
        }
        Rectangle {
            visible: root.hasArea
            y: root.area.y
            width: root.area.x
            height: root.area.height
            color: "black"
            opacity: 0.45
        }
        Rectangle {
            visible: root.hasArea
            x: root.area.x + root.area.width
            y: root.area.y
            width: parent.width - x
            height: root.area.height
            color: "black"
            opacity: 0.45
        }
        Rectangle {
            visible: root.hasArea
            y: root.area.y + root.area.height
            width: parent.width
            height: parent.height - y
            color: "black"
            opacity: 0.45
        }
    }

    Rectangle {
        objectName: "selection"
        x: root.area.x - border.width
        y: root.area.y - border.width
        width: root.area.width + 2 * border.width
        height: root.area.height + 2 * border.width
        visible: root.hasArea && shot.visible
        color: "transparent"
        border.width: Theme.focusRingWidth
        border.color: Theme.focusRing
        radius: 2
        Accessible.role: Accessible.Graphic
        Accessible.name: qsTr("Selected area")
        Accessible.description: qsTr("%1 by %2 pixels").arg(Math.round(root.area.width * root.scaleX))
                                                        .arg(Math.round(root.area.height * root.scaleY))
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.lens.state === "selecting"
        cursorShape: Qt.CrossCursor
        onPressed: mouse => {
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.anchorPoint = Qt.point(mouse.x, mouse.y);
            root.area = Qt.rect(mouse.x, mouse.y, 0, 0);
        }
        onPositionChanged: mouse => {
            const x = Math.max(0, Math.min(root.width, mouse.x));
            const y = Math.max(0, Math.min(root.height, mouse.y));
            root.area = Qt.rect(Math.min(root.anchorPoint.x, x), Math.min(root.anchorPoint.y, y),
                                Math.abs(x - root.anchorPoint.x), Math.abs(y - root.anchorPoint.y));
        }
        onReleased: {
            if (root.hasArea) {
                root.confirm();
            }
        }
    }

    // What to do, at the top while selecting; "Reading…" while recognising.
    GlassSurface {
        id: hintGlass
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.launcherMargin
        width: hintColumn.implicitWidth + 4 * Theme.spacing
        height: hintColumn.implicitHeight + 2 * Theme.spacing
        visible: root.lens.state === "selecting" || root.lens.state === "recognizing"
            || root.lens.state === "capturing"
        wallpaperOrigin: Qt.point(hintGlass.x, hintGlass.y)
        screenSize: root.screenSize
    }

    Column {
        id: hintColumn
        anchors.centerIn: hintGlass
        visible: hintGlass.visible
        spacing: Theme.spacing / 2

        Text {
            objectName: "hint"
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.lens.state === "recognizing" ? qsTr("Reading the selected area…")
                : root.lens.state === "capturing" ? qsTr("Taking a screenshot…")
                : qsTr("Select an area")
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.pixelSize: Math.round(Theme.metrics.height * 1.25)
            font.bold: true
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.lens.state === "selecting"
            text: qsTr("Drag over it, or press Ctrl+A for the whole screen and Return to read it. Escape closes.")
            color: Theme.text
            font: Theme.metrics.font
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }
    }

    ResultsPanel {
        id: results
        objectName: "results"
        lens: root.lens
        visible: root.lens.state === "results"
        width: Math.min(implicitWidth, root.width - 2 * Theme.spacing)
        height: Math.min(implicitHeight, root.height - 2 * Theme.spacing)
        // Beside the selection when there is room, else centred.
        x: {
            const right = root.area.x + root.area.width + Theme.spacing;
            const left = root.area.x - Theme.spacing - width;
            if (right + width <= root.width) {
                return right;
            }
            return left >= 0 ? left : (root.width - width) / 2;
        }
        y: Math.max(Theme.spacing, Math.min(root.height - height - Theme.spacing, root.area.y))
        glassOrigin: Qt.point(results.x, results.y)
        screenSize: root.screenSize
        onLensSearchRequested: lensDialog.open()
        onCloseRequested: root.closeRequested()
    }

    // Capture errors: a normal window with the reason.
    Column {
        objectName: "errorView"
        anchors.centerIn: parent
        width: Math.min(parent.width - 4 * Theme.spacing, 40 * Theme.gridUnit)
        visible: root.lens.state === "error"
        spacing: Theme.spacing

        Text {
            objectName: "errorText"
            width: parent.width
            text: root.lens.errorString
            color: Theme.text
            font: Theme.metrics.font
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        ShellButton {
            objectName: "errorCloseButton"
            text: qsTr("Close")
            onClicked: root.closeRequested()
        }
    }

    LensDialog {
        id: lensDialog
        objectName: "lensDialog"
        anchors.fill: parent
        screenSize: root.screenSize
        onConfirmed: {
            root.lens.openGoogleLens();
            results.focusFirst();
        }
        onRejected: results.focusFirst()
    }
}
