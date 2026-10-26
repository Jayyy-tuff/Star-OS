// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import "weather.js" as Weather

// The desktop's widgets (M0.5): Clock, Weather, System and Calendar in a
// column at the top right, under a "Widgets" button whose menu shows or
// hides each one. What is shown and the weather's place are kept in
// 'store': StarOS.System's WidgetStore (values, setValue(key, value)) in the
// session, a fake in tests. Every widget is shown until hidden.
Item {
    id: root

    property var store: null
    property var status: null
    property var fetch: Weather.request
    // The board's top-left in screen coordinates and the screen size, for the
    // glass.
    property point boardOrigin: Qt.point(0, 0)
    property size screenSize: Qt.size(root.width, root.height)
    // Room left free at the right of the button row (the notes' button).
    property real toolbarRight: Theme.spacing
    property date now: new Date()
    property bool clockRunning: true

    readonly property var kinds: [
        {key: "clock", name: qsTr("Clock")},
        {key: "weather", name: qsTr("Weather")},
        {key: "system", name: qsTr("System")},
        {key: "calendar", name: qsTr("Calendar")}
    ]
    readonly property var shownMap: root.store && root.store.values && root.store.values.shown
        ? root.store.values.shown : ({})
    // The weather's place; replaced only when it changes, so that showing or
    // hiding a widget does not ask for the weather again.
    property var place: null
    readonly property alias menuOpen: menu.visible

    Accessible.role: Accessible.Pane
    Accessible.name: qsTr("Desktop widgets")

    function isShown(key) {
        return root.shownMap[key] !== false;
    }

    function setShown(key, on) {
        const shown = Object.assign({}, root.shownMap);
        shown[key] = on;
        root.store.setValue("shown", shown);
        console.info("STAROS-SHELL widget=" + key + " shown=" + on);
    }

    function syncPlace() {
        const next = root.store && root.store.values && root.store.values.weatherPlace
            ? root.store.values.weatherPlace : null;
        if (JSON.stringify(next) !== JSON.stringify(root.place)) {
            root.place = next;
        }
    }

    onStoreChanged: root.syncPlace()
    Component.onCompleted: root.syncPlace()

    Connections {
        target: root.store
        ignoreUnknownSignals: true

        function onValuesChanged() {
            root.syncPlace();
        }
    }

    function openMenu() {
        menu.visible = true;
        menuList.currentIndex = 0;
        menuList.forceActiveFocus(Qt.OtherFocusReason);
    }

    function closeMenu() {
        menu.visible = false;
        widgetsButton.forceActiveFocus(Qt.OtherFocusReason);
    }

    // The minute changes the clock; nothing redraws in between.
    Timer {
        interval: 1000
        repeat: true
        running: root.clockRunning
        onTriggered: {
            const now = new Date();
            if (now.getMinutes() !== root.now.getMinutes() || now.getDate() !== root.now.getDate()) {
                root.now = now;
            }
        }
    }

    GlassSurface {
        anchors.fill: widgetsButton
        radius: Theme.controlRadius
        wallpaperOrigin: Qt.point(root.boardOrigin.x + widgetsButton.x, root.boardOrigin.y + widgetsButton.y)
        screenSize: root.screenSize
    }

    ShellButton {
        id: widgetsButton
        objectName: "widgetsButton"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.spacing
        anchors.rightMargin: root.toolbarRight
        height: Theme.minTarget
        symbol: "grid"
        text: qsTr("Widgets")
        description: qsTr("Show or hide desktop widgets")
        highlighted: menu.visible
        onClicked: menu.visible ? root.closeMenu() : root.openMenu()
    }

    Column {
        id: column
        objectName: "widgetColumn"
        anchors.top: widgetsButton.bottom
        anchors.topMargin: Theme.spacing
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing
        width: Math.round(15 * Theme.gridUnit)
        spacing: Theme.spacing

        ClockWidget {
            id: clock
            objectName: "clockWidget"
            width: column.width
            visible: root.isShown("clock")
            now: root.now
            wallpaperOrigin: Qt.point(root.boardOrigin.x + column.x + clock.x, root.boardOrigin.y + column.y + clock.y)
            screenSize: root.screenSize
        }

        WeatherWidget {
            id: weather
            objectName: "weatherWidget"
            width: column.width
            visible: root.isShown("weather")
            active: weather.visible
            place: root.place
            fetch: root.fetch
            now: root.now
            wallpaperOrigin: Qt.point(root.boardOrigin.x + column.x + weather.x, root.boardOrigin.y + column.y + weather.y)
            screenSize: root.screenSize
            onPlaceChosen: chosen => {
                root.store.setValue("weatherPlace", chosen);
                console.info("STAROS-SHELL weather=place");
            }
        }

        SystemWidget {
            id: system
            objectName: "systemWidget"
            width: column.width
            visible: root.isShown("system")
            status: root.status
            wallpaperOrigin: Qt.point(root.boardOrigin.x + column.x + system.x, root.boardOrigin.y + column.y + system.y)
            screenSize: root.screenSize
        }

        CalendarWidget {
            id: calendar
            objectName: "calendarWidget"
            width: column.width
            visible: root.isShown("calendar")
            now: root.now
            wallpaperOrigin: Qt.point(root.boardOrigin.x + column.x + calendar.x, root.boardOrigin.y + column.y + calendar.y)
            screenSize: root.screenSize
        }
    }

    // The menu under the button: a check box per widget.
    GlassPanel {
        id: menu
        objectName: "widgetsMenu"
        visible: false
        z: 10
        anchors.top: widgetsButton.bottom
        anchors.topMargin: Math.round(Theme.spacing / 2)
        anchors.right: widgetsButton.right
        width: Math.round(13 * Theme.gridUnit)
        height: menuList.height + 2 * Math.round(Theme.spacing * 0.75)
        wallpaperOrigin: Qt.point(root.boardOrigin.x + menu.x, root.boardOrigin.y + menu.y)
        screenSize: root.screenSize

        Accessible.role: Accessible.PopupMenu
        Accessible.name: qsTr("Widgets")

        ListView {
            id: menuList
            objectName: "widgetsMenuList"
            x: Math.round(Theme.spacing * 0.75)
            y: Math.round(Theme.spacing * 0.75)
            width: menu.width - 2 * x
            height: contentHeight
            interactive: false
            model: root.kinds
            keyNavigationEnabled: true
            highlightMoveDuration: 0

            Keys.onEscapePressed: event => {
                root.closeMenu();
                event.accepted = true;
            }

            delegate: T.AbstractButton {
                id: item

                required property var modelData
                required property int index

                width: menuList.width
                height: Theme.rowHeight
                focus: item.ListView.isCurrentItem
                focusPolicy: Qt.StrongFocus
                hoverEnabled: true
                checkable: false
                checked: root.isShown(item.modelData.key)
                text: item.modelData.name

                Accessible.role: Accessible.CheckBox
                Accessible.name: item.text
                Accessible.checkable: true
                Accessible.checked: item.checked

                Keys.onReturnPressed: event => {
                    item.clicked();
                    event.accepted = true;
                }
                onClicked: root.setShown(item.modelData.key, !item.checked)

                background: Rectangle {
                    radius: Theme.controlRadius
                    color: item.down ? Theme.glassButtonPressed
                        : item.hovered || item.activeFocus ? Theme.glassButton : "transparent"
                }

                contentItem: Item {
                    Rectangle {
                        id: box
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(Theme.spacing / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(1.2 * Theme.gridUnit)
                        height: width
                        radius: Math.round(width / 4)
                        color: item.checked ? Theme.accent : "transparent"
                        border.width: item.checked ? 0 : 1
                        border.color: Theme.textSecondary

                        Symbol {
                            anchors.centerIn: parent
                            width: Math.round(parent.width * 0.8)
                            height: width
                            visible: item.checked
                            name: "check"
                        }
                    }

                    Text {
                        anchors.left: box.right
                        anchors.leftMargin: Theme.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: item.text
                        color: Theme.text
                        font: Theme.metrics.font
                        Accessible.ignored: true
                    }
                }

                FocusFrame {
                    visible: item.activeFocus
                    radius: Theme.controlRadius
                }
            }
        }
    }
}
