// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import "weather.js" as Weather

// The desktop's Weather widget (ADR-0015). Until a place is chosen it asks
// for a city and sends nothing. Then it asks Open-Meteo for the place's
// weather now and every 30 minutes while 'active'. Offline, it keeps the
// last values and says when they are from.
//
// 'fetch' is function(url, callback(ok, text)): Weather.request in the
// session, a fake in tests. The host saves the place it gets from
// placeChosen and passes it back as 'place'.
WidgetCard {
    id: root

    property var place: null
    property var fetch: Weather.request
    property bool active: true
    property bool fahrenheit: Qt.locale().measurementSystem === Locale.ImperialUSSystem
    property date now: new Date()

    // Read-only for the host and tests.
    property var forecast: null
    property date updated: new Date(0)
    property bool loading: false
    property bool offline: false
    property bool changing: false
    property bool searching: false
    property var places: []
    property string message: ""

    readonly property bool choosing: root.place === null || root.changing
    readonly property var current: root.forecast ? Weather.describe(root.forecast.code, root.forecast.isDay) : null

    signal placeChosen(var place)

    title: qsTr("Weather")
    symbol: root.current ? root.current.symbol : "cloud-sun"
    Accessible.description: root.choosing ? qsTr("Choose a city")
        : root.forecast ? qsTr("%1: %2, %3").arg(Weather.placeLabel(root.place))
            .arg(Weather.degrees(root.forecast.temperature)).arg(root.current.text)
        : root.offline ? qsTr("Weather is unavailable offline") : qsTr("Loading the weather")

    function search(text) {
        const name = String(text).trim();
        if (name === "" || !root.fetch) {
            return;
        }
        root.searching = true;
        root.places = [];
        root.message = "";
        const language = Qt.locale().name.split("_")[0];
        root.fetch(Weather.geocodingUrl(name, /^[a-z]{2,3}$/.test(language) ? language : "en"), (ok, body) => {
            root.searching = false;
            if (!ok) {
                root.message = qsTr("Could not search: no connection to Open-Meteo.");
                return;
            }
            root.places = Weather.parsePlaces(body);
            if (root.places.length === 0) {
                root.message = qsTr("No place called “%1” was found.").arg(name);
            } else {
                Qt.callLater(() => placeList.forceActiveFocus(Qt.TabFocusReason));
            }
        });
    }

    function choose(index) {
        const chosen = root.places[index];
        if (!chosen) {
            return;
        }
        root.changing = false;
        root.places = [];
        root.message = "";
        root.placeChosen(chosen);
    }

    function refresh() {
        if (root.place === null || !root.fetch || root.loading) {
            return;
        }
        root.loading = true;
        const asked = root.place;
        root.fetch(Weather.forecastUrl(asked, root.fahrenheit), (ok, body) => {
            if (asked !== root.place) {
                return;
            }
            root.loading = false;
            const result = ok ? Weather.parseForecast(body) : null;
            if (result) {
                root.forecast = result;
                root.updated = new Date();
                root.offline = false;
            } else {
                root.offline = true;
            }
        });
    }

    function startChanging() {
        root.changing = true;
        root.places = [];
        root.message = "";
        cityField.text = "";
        cityField.forceActiveFocus(Qt.TabFocusReason);
    }

    onPlaceChanged: {
        root.forecast = null;
        root.offline = false;
        root.loading = false;
        if (root.active) {
            root.refresh();
        }
    }
    // Back on screen after half an hour or more: refresh at once.
    onActiveChanged: {
        if (root.active && (root.forecast === null || Date.now() - root.updated.getTime() >= refreshTimer.interval)) {
            root.refresh();
        }
    }
    Component.onCompleted: {
        if (root.active) {
            root.refresh();
        }
    }

    Timer {
        id: refreshTimer
        interval: 30 * 60 * 1000
        repeat: true
        running: root.active && root.place !== null
        onTriggered: root.refresh()
    }

    // --- choosing a place ---------------------------------------------------

    Text {
        objectName: "intro"
        width: parent.width
        visible: root.choosing
        text: qsTr("Type a city to see its weather. Star OS asks Open-Meteo only after you choose one.")
        color: Theme.textSecondary
        font.family: Theme.metrics.font.family
        font.pixelSize: Theme.smallPixelSize
        wrapMode: Text.Wrap
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    T.TextField {
        id: cityField
        objectName: "cityField"
        width: parent.width
        height: Math.round(Theme.searchHeight * 0.85)
        visible: root.choosing
        leftPadding: Theme.spacing
        rightPadding: Theme.spacing
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.text
        placeholderText: qsTr("City")
        placeholderTextColor: Theme.placeholder
        font: Theme.metrics.font
        Accessible.name: qsTr("City")

        background: Rectangle {
            radius: Theme.controlRadius
            color: Theme.glassButton
            border.width: 1
            border.color: cityField.activeFocus ? Theme.activeIndicator : Theme.glassBorder
        }

        Keys.onReturnPressed: event => {
            root.search(cityField.text);
            event.accepted = true;
        }
        Keys.onEnterPressed: event => {
            root.search(cityField.text);
            event.accepted = true;
        }
        Keys.onEscapePressed: event => {
            if (root.changing && root.place !== null) {
                root.changing = false;
                event.accepted = true;
            } else {
                event.accepted = false;
            }
        }

        FocusFrame {
            visible: cityField.activeFocus
            radius: Theme.controlRadius
        }
    }

    Row {
        visible: root.choosing
        spacing: Math.round(Theme.spacing / 2)

        ShellButton {
            objectName: "searchButton"
            height: Math.round(1.7 * Theme.gridUnit)
            radius: height / 2
            highlighted: true
            symbol: "search"
            text: root.searching ? qsTr("Searching…") : qsTr("Search")
            enabled: !root.searching && cityField.text.trim() !== ""
            onClicked: root.search(cityField.text)
        }

        ShellButton {
            objectName: "cancelButton"
            height: Math.round(1.7 * Theme.gridUnit)
            radius: height / 2
            visible: root.changing && root.place !== null
            text: qsTr("Cancel")
            onClicked: root.changing = false
        }
    }

    Text {
        objectName: "message"
        width: parent.width
        visible: root.message !== ""
        text: root.message
        color: Theme.textSecondary
        font.family: Theme.metrics.font.family
        font.pixelSize: Theme.smallPixelSize
        wrapMode: Text.Wrap
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    ListView {
        id: placeList
        objectName: "places"
        width: parent.width
        height: contentHeight
        visible: root.choosing && count > 0
        interactive: false
        model: root.places
        keyNavigationEnabled: true
        highlightMoveDuration: 0
        activeFocusOnTab: count > 0

        Accessible.role: Accessible.List
        Accessible.name: qsTr("Places")

        delegate: T.AbstractButton {
            id: placeRow

            required property var modelData
            required property int index

            width: placeList.width
            height: Math.round(1.9 * Theme.gridUnit)
            focus: placeRow.ListView.isCurrentItem
            focusPolicy: Qt.StrongFocus
            hoverEnabled: true
            text: Weather.placeLabel(placeRow.modelData)

            Accessible.role: Accessible.Button
            Accessible.name: placeRow.text

            Keys.onReturnPressed: event => {
                root.choose(placeRow.index);
                event.accepted = true;
            }
            onClicked: root.choose(placeRow.index)

            background: Rectangle {
                radius: Theme.controlRadius
                color: placeRow.down ? Theme.glassButtonPressed
                    : placeRow.hovered || placeRow.activeFocus ? Theme.glassButton : "transparent"
            }

            contentItem: Text {
                leftPadding: Math.round(Theme.spacing / 2)
                text: placeRow.text
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                Accessible.ignored: true
            }

            FocusFrame {
                visible: placeRow.activeFocus
                radius: Theme.controlRadius
            }
        }
    }

    // --- the weather --------------------------------------------------------

    Text {
        objectName: "placeName"
        width: parent.width
        visible: !root.choosing
        text: Weather.placeLabel(root.place)
        color: Theme.text
        font.family: Theme.metrics.font.family
        font.pixelSize: Math.round(Theme.fontSize)
        font.weight: Font.DemiBold
        elide: Text.ElideRight
        Accessible.ignored: true
    }

    Row {
        objectName: "now"
        visible: !root.choosing && root.forecast !== null
        spacing: Theme.spacing

        Symbol {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(2.6 * Theme.gridUnit)
            height: width
            name: root.current ? root.current.symbol : ""
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
                objectName: "temperature"
                text: root.forecast ? Weather.degrees(root.forecast.temperature) : ""
                color: Theme.text
                font.family: Theme.metrics.font.family
                font.pixelSize: Math.round(2.4 * Theme.gridUnit)
                font.weight: Font.Light
                Accessible.ignored: true
            }

            Text {
                objectName: "condition"
                text: root.current ? root.current.text : ""
                color: Theme.textSecondary
                font.family: Theme.metrics.font.family
                font.pixelSize: Theme.smallPixelSize
                Accessible.ignored: true
            }
        }
    }

    Row {
        objectName: "days"
        visible: !root.choosing && root.forecast !== null && root.forecast.days.length > 1
        width: parent.width

        Repeater {
            model: root.forecast ? root.forecast.days.slice(0, 4) : []

            Column {
                id: day

                required property var modelData
                required property int index

                width: parent.width / 4
                Accessible.role: Accessible.StaticText
                Accessible.name: (day.index === 0 ? qsTr("Today") : Qt.formatDate(day.modelData.date, "dddd")) + ": "
                    + Weather.describe(day.modelData.code, true).text + ", "
                    + qsTr("high %1, low %2").arg(Weather.degrees(day.modelData.high)).arg(Weather.degrees(day.modelData.low))

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: day.index === 0 ? qsTr("Today") : Qt.formatDate(day.modelData.date, "ddd")
                    color: Theme.textSecondary
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.smallPixelSize
                    Accessible.ignored: true
                }

                Symbol {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: Weather.describe(day.modelData.code, true).symbol
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Weather.degrees(day.modelData.high) + " " + Weather.degrees(day.modelData.low)
                    color: Theme.text
                    font.family: Theme.metrics.font.family
                    font.pixelSize: Theme.smallPixelSize
                    Accessible.ignored: true
                }
            }
        }
    }

    Text {
        objectName: "status"
        width: parent.width
        visible: !root.choosing
        text: root.forecast === null
            ? (root.offline ? qsTr("Weather is unavailable: no connection to Open-Meteo.") : qsTr("Loading the weather…"))
            : root.offline ? qsTr("Offline · from %1").arg(Qt.formatTime(root.updated, Qt.locale().timeFormat(Locale.ShortFormat)))
            : qsTr("Weather from Open-Meteo · %1").arg(Qt.formatTime(root.updated, Qt.locale().timeFormat(Locale.ShortFormat)))
        color: Theme.textTertiary
        font.family: Theme.metrics.font.family
        font.pixelSize: Theme.smallPixelSize
        wrapMode: Text.Wrap
        Accessible.role: Accessible.StaticText
        Accessible.name: text
    }

    Row {
        visible: !root.choosing
        spacing: Math.round(Theme.spacing / 2)

        ShellButton {
            objectName: "retryButton"
            height: Math.round(1.7 * Theme.gridUnit)
            radius: height / 2
            visible: root.offline
            symbol: "restart"
            text: qsTr("Try again")
            onClicked: root.refresh()
        }

        ShellButton {
            objectName: "changeButton"
            height: Math.round(1.7 * Theme.gridUnit)
            radius: height / 2
            text: qsTr("Change city")
            onClicked: root.startChanging()
        }
    }
}
