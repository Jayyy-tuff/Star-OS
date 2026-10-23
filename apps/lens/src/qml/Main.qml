// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import StarOS.Shell

// The Star Lens window. It stays hidden while the screen is captured (KWin
// leaves the caller's windows out anyway), then covers the screen for the
// selection. On an error it shows a normal window with the reason.
Window {
    id: window

    width: 900
    height: 520
    visible: false
    title: qsTr("Star Lens")
    color: "black"

    LensBackend {
        id: backend

        onStateChanged: {
            if (backend.state === "selecting" && window.visibility !== Window.FullScreen) {
                window.showFullScreen();
                view.forceActiveFocus();
            } else if (backend.state === "error" && !window.visible) {
                window.color = Theme.glassFallback;
                window.show();
            }
        }
    }

    LensView {
        id: view
        anchors.fill: parent
        focus: true
        lens: backend
        onCloseRequested: {
            window.hide();
            backend.quit();
        }
    }

    Component.onCompleted: backend.capture()
}
