// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import StarOS.Shell

// What Star Lens found in the selected area: the text, a QR code or barcode,
// links, and what to do with them. "Search with Google Lens" only asks the
// view to confirm (LensDialog); nothing leaves the computer from here.
FocusScope {
    id: panel

    required property var lens
    property point glassOrigin: Qt.point(panel.x, panel.y)
    property size screenSize: Qt.size(0, 0)

    signal lensSearchRequested()
    signal closeRequested()

    implicitWidth: 30 * Theme.gridUnit
    implicitHeight: column.implicitHeight + 2 * Theme.spacing

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Results")

    // The first button that can be used: Copy text, Search the web or Copy
    // image.
    function focusFirst() {
        const first = copyTextButton.enabled ? copyTextButton : searchButton.enabled ? searchButton : copyImageButton;
        first.forceActiveFocus(Qt.OtherFocusReason);
    }

    GlassSurface {
        anchors.fill: parent
        wallpaperOrigin: panel.glassOrigin
        screenSize: panel.screenSize
    }

    Column {
        id: column
        x: Theme.spacing
        y: Theme.spacing
        width: panel.width - 2 * Theme.spacing
        spacing: Theme.spacing

        Text {
            width: parent.width
            text: qsTr("Text")
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.bold: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        Flickable {
            id: textFlick
            width: parent.width
            height: Math.min(textArea.implicitHeight, 12 * Theme.gridUnit)
            visible: panel.lens.text !== ""
            clip: true
            contentWidth: width
            contentHeight: textArea.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            T.TextArea.flickable: T.TextArea {
                id: textArea
                objectName: "resultText"
                text: panel.lens.text
                readOnly: true
                selectByMouse: true
                selectByKeyboard: true
                wrapMode: TextEdit.Wrap
                color: Theme.text
                font: Theme.metrics.font
                padding: Theme.spacing / 2
                Accessible.name: qsTr("Recognised text")
                Accessible.description: textArea.text

                background: Rectangle {
                    radius: Theme.controlRadius
                    color: Theme.tileGlass
                }

                // Copies through Star Lens, so the copy outlives the window.
                Keys.onPressed: event => {
                    if (event.matches(StandardKey.Copy)) {
                        panel.lens.copyText(textArea.selectedText);
                        event.accepted = true;
                    }
                }
                Keys.onTabPressed: event => {
                    const next = textArea.nextItemInFocusChain(true);
                    if (next) {
                        next.forceActiveFocus(Qt.TabFocusReason);
                    }
                    event.accepted = true;
                }

                FocusFrame {
                    visible: textArea.activeFocus
                    radius: Theme.controlRadius
                }
            }
        }

        Text {
            objectName: "noText"
            width: parent.width
            visible: panel.lens.text === ""
            text: panel.lens.recognitionError !== "" ? panel.lens.recognitionError : qsTr("No text found.")
            color: Theme.placeholder
            font: Theme.metrics.font
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Text {
            width: parent.width
            visible: panel.lens.code !== ""
            text: panel.lens.codeFormat !== "" ? qsTr("Code (%1)").arg(panel.lens.codeFormat) : qsTr("Code")
            color: Theme.text
            font.family: Theme.metrics.font.family
            font.bold: true
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        Text {
            objectName: "codeText"
            width: parent.width
            visible: panel.lens.code !== ""
            text: panel.lens.code
            color: Theme.text
            font: Theme.metrics.font
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 6
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Repeater {
            model: panel.lens.links

            ShellButton {
                id: linkButton
                required property string modelData
                objectName: "linkButton"
                width: Math.min(implicitWidth, column.width)
                text: qsTr("Open %1").arg(linkButton.modelData)
                description: linkButton.modelData
                Accessible.name: qsTr("Open link")
                onClicked: panel.lens.openLink(linkButton.modelData)
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.spacing / 2

            ShellButton {
                id: copyTextButton
                objectName: "copyTextButton"
                text: qsTr("Copy text")
                enabled: panel.lens.text !== ""
                opacity: enabled ? 1 : 0.5
                onClicked: panel.lens.copyText()
            }
            ShellButton {
                objectName: "copyCodeButton"
                visible: panel.lens.code !== ""
                text: qsTr("Copy code")
                onClicked: panel.lens.copyCode()
            }
            ShellButton {
                id: searchButton
                objectName: "searchButton"
                text: qsTr("Search the web")
                description: qsTr("Search for the text in your browser")
                enabled: panel.lens.text !== "" || panel.lens.code !== ""
                opacity: enabled ? 1 : 0.5
                onClicked: panel.lens.searchWeb()
            }
            ShellButton {
                id: copyImageButton
                objectName: "copyImageButton"
                text: qsTr("Copy image")
                onClicked: panel.lens.copyImage()
            }
            ShellButton {
                objectName: "saveImageButton"
                text: qsTr("Save image")
                description: qsTr("Save the selected area in Pictures/Star Lens")
                onClicked: panel.lens.saveImage()
            }
            ShellButton {
                objectName: "googleLensButton"
                text: qsTr("Search with Google Lens")
                description: qsTr("Sends the selected image to Google; asks first")
                onClicked: panel.lensSearchRequested()
            }
            ShellButton {
                objectName: "selectAgainButton"
                text: qsTr("Select again")
                onClicked: panel.lens.selectAgain()
            }
            ShellButton {
                objectName: "closeButton"
                text: qsTr("Close")
                onClicked: panel.closeRequested()
            }
        }

        Text {
            id: messageLabel
            objectName: "message"
            width: parent.width
            visible: text !== ""
            text: panel.lens.message
            color: Theme.text
            font: Theme.metrics.font
            wrapMode: Text.Wrap
            Accessible.role: Accessible.StaticText
            Accessible.name: text
            onTextChanged: {
                if (text !== "") {
                    messageLabel.Accessible.announce(text);
                }
            }
        }
    }
}
