// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Desktop widgets (M0.5, ADR-0015): the four widgets and their order, the
// Widgets menu and what it saves, the System widget's rows, the clock and
// calendar, and the Weather widget against a fake Open-Meteo: nothing is
// asked before a place is chosen, searching, choosing, the forecast,
// offline, and that showing other widgets asks for nothing. weather.js's
// parsing is tested on Open-Meteo-shaped answers.
Item {
    id: root

    width: 1280
    height: 900

    readonly property date fixedNow: new Date(2026, 9, 25, 14, 30)
    readonly property string berlinSearch: JSON.stringify({
        results: [
            {id: 2950159, name: "Berlin", latitude: 52.52437, longitude: 13.41053, country: "Germany",
             admin1: "Land Berlin"},
            {id: 5083330, name: "Berlin", latitude: 44.46867, longitude: -71.18508, country: "United States",
             admin1: "New Hampshire"},
            {name: "Broken", country: "Nowhere"}
        ]
    })
    readonly property string berlinForecast: JSON.stringify({
        current_units: {temperature_2m: "°C"},
        current: {time: "2026-10-25T14:30", temperature_2m: 12.4, weather_code: 2, is_day: 1},
        daily: {
            time: ["2026-10-25", "2026-10-26", "2026-10-27", "2026-10-28"],
            weather_code: [2, 61, 3, 0],
            temperature_2m_max: [14.6, 11.2, 10.0, 13.3],
            temperature_2m_min: [7.1, 6.0, 4.4, 3.9]
        }
    })

    QtObject {
        id: fakeStore

        property var values: ({})

        function setValue(key, value) {
            const next = Object.assign({}, fakeStore.values);
            if (value === undefined || value === null) {
                delete next[key];
            } else {
                next[key] = value;
            }
            fakeStore.values = next;
        }
    }

    // Open-Meteo stand-in: answers on the next turn of the event loop.
    QtObject {
        id: fakeMeteo

        property var requests: []
        property bool online: true

        function fetch(url, callback) {
            fakeMeteo.requests = fakeMeteo.requests.concat([url]);
            const online = fakeMeteo.online;
            Qt.callLater(() => {
                if (!online) {
                    callback(false, "");
                } else if (url.indexOf("geocoding-api.open-meteo.com") >= 0) {
                    callback(true, url.indexOf("name=Berlin") >= 0 ? root.berlinSearch : "{}");
                } else {
                    callback(true, root.berlinForecast);
                }
            });
        }
    }

    readonly property var liveStatus: ({storageMode: "live", storageTotal: 2e9, storageFree: 1.5e9,
                                        memoryTotal: 4e9, memoryAvailable: 3e9, cpuUsage: 42,
                                        batteryPresent: false, batteryPercent: 0, charging: false})

    DesktopWidgets {
        id: widgets
        anchors.fill: parent
        store: fakeStore
        status: root.liveStatus
        fetch: fakeMeteo.fetch
        toolbarRight: 150
        now: root.fixedNow
        clockRunning: false
    }

    TestCase {
        name: "DesktopWidgets"
        when: windowShown

        property Item weather

        function initTestCase() {
            Theme.animationFactor = 0;
            weather = findChild(widgets, "weatherWidget");
            verify(weather);
        }

        function init() {
            fakeStore.values = {};
            fakeMeteo.requests = [];
            fakeMeteo.online = true;
            if (widgets.menuOpen) {
                widgets.closeMenu();
            }
            weather.changing = false;
            weather.places = [];
            weather.message = "";
            findChild(weather, "cityField").text = "";
            waitForRendering(widgets);
        }

        function shownWidgets() {
            const names = [];
            for (const name of ["clockWidget", "weatherWidget", "systemWidget", "calendarWidget"]) {
                if (findChild(widgets, name).visible) {
                    names.push(findChild(widgets, name).Accessible.name);
                }
            }
            return names;
        }

        function type(text) {
            for (const ch of text) {
                keyClick(ch);
            }
        }

        function choosePlace() {
            const field = findChild(weather, "cityField");
            field.forceActiveFocus();
            type("Berlin");
            keyClick(Qt.Key_Return);
            const places = findChild(weather, "places");
            tryVerify(() => places.visible && places.itemAtIndex(1) !== null, 3000, "the places are listed");
            tryVerify(() => places.itemAtIndex(0).activeFocus, 2000, "the first place has focus");
            compare(places.itemAtIndex(0).Accessible.name, "Berlin, Land Berlin, Germany");
            keyClick(Qt.Key_Return);
            tryVerify(() => weather.forecast !== null, 3000, "the forecast arrives");
            waitForRendering(widgets);
        }

        function test_all_widgets_shown_in_order() {
            compare(shownWidgets(), ["Clock", "Weather", "System", "Calendar"]);
            compare(widgets.Accessible.name, "Desktop widgets");
            const column = findChild(widgets, "widgetColumn");
            fuzzyCompare(column.x + column.width, root.width - Theme.spacing, 1);
            const button = findChild(widgets, "widgetsButton");
            fuzzyCompare(button.x + button.width, root.width - 150, 1);
            verify(column.y >= button.y + button.height);
            let previous = -1;
            for (const name of ["clockWidget", "weatherWidget", "systemWidget", "calendarWidget"]) {
                const item = findChild(widgets, name);
                verify(item.y > previous, name + " is below the one before");
                previous = item.y;
            }
        }

        function test_menu_hides_and_shows() {
            const button = findChild(widgets, "widgetsButton");
            mouseClick(button);
            verify(widgets.menuOpen);
            const menuList = findChild(widgets, "widgetsMenuList");
            tryVerify(() => menuList.itemAtIndex(3) !== null);
            waitForRendering(widgets);
            const calendarItem = menuList.itemAtIndex(3);
            compare(calendarItem.Accessible.name, "Calendar");
            compare(calendarItem.Accessible.role, Accessible.CheckBox);
            verify(calendarItem.checked);
            mouseClick(calendarItem);
            compare(fakeStore.values.shown.calendar, false);
            verify(!calendarItem.checked);
            compare(shownWidgets(), ["Clock", "Weather", "System"]);
            mouseClick(calendarItem);
            compare(fakeStore.values.shown.calendar, true);
            compare(shownWidgets(), ["Clock", "Weather", "System", "Calendar"]);
            // Keyboard: the first item has focus; Return toggles, Escape closes.
            tryVerify(() => menuList.itemAtIndex(0).activeFocus || calendarItem.activeFocus);
            menuList.currentIndex = 0;
            menuList.itemAtIndex(0).forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(fakeStore.values.shown.clock, false);
            keyClick(Qt.Key_Escape);
            verify(!widgets.menuOpen);
            tryVerify(() => button.activeFocus, 2000, "focus returns to the button");
            compare(fakeMeteo.requests, [], "nothing was asked of Open-Meteo");
        }

        function test_store_changes_from_outside() {
            fakeStore.values = {shown: {weather: false, system: false}};
            compare(shownWidgets(), ["Clock", "Calendar"]);
            fakeStore.values = {};
            compare(shownWidgets(), ["Clock", "Weather", "System", "Calendar"]);
        }

        function test_system_rows() {
            const system = findChild(widgets, "systemWidget");
            compare(findChild(system, "cpu").Accessible.name, "Processor: 42 %");
            compare(findChild(system, "memory").Accessible.name, "Memory: 1 GB of 4 GB");
            compare(findChild(system, "storage").Accessible.name, "Live session: 1.5 GB free");
            const cpuBar = findChild(findChild(system, "cpu"), "bar");
            fuzzyCompare(cpuBar.width / cpuBar.parent.width, 0.42, 0.02);
            widgets.status = {storageMode: "installed", storageTotal: 0, storageFree: 0, memoryTotal: 0,
                              memoryAvailable: 0, cpuUsage: -1};
            compare(findChild(system, "cpu").Accessible.name, "Processor: Measuring…");
            compare(findChild(system, "storage").Accessible.name, "Storage: 0 B free");
            widgets.status = root.liveStatus;
        }

        function test_clock_and_calendar() {
            const clock = findChild(widgets, "clockWidget");
            compare(findChild(clock, "time").text, Qt.formatTime(root.fixedNow, clock.timeFormat));
            verify(!findChild(clock, "time").text.includes(":00:"), "no seconds");
            compare(findChild(clock, "date").text, "Sunday, 25 October");
            const calendar = findChild(widgets, "calendarWidget");
            compare(findChild(calendar, "month").text, "October 2026");
            const today = findChild(calendar, "todayCell");
            verify(today);
            compare(today.Accessible.name, "Sunday 25 October 2026, today");
        }

        function test_weather_asks_for_a_city_first() {
            compare(weather.Accessible.description, "Choose a city");
            verify(findChild(weather, "intro").visible);
            verify(findChild(weather, "cityField").visible);
            verify(!findChild(weather, "searchButton").enabled, "nothing to search for yet");
            wait(200);
            compare(fakeMeteo.requests, []);
        }

        function test_weather_search_and_forecast() {
            choosePlace();
            compare(fakeMeteo.requests.length, 2);
            verify(fakeMeteo.requests[0].startsWith("https://geocoding-api.open-meteo.com/v1/search?name=Berlin&count=6"));
            verify(fakeMeteo.requests[1].startsWith("https://api.open-meteo.com/v1/forecast?latitude=52.5244&longitude=13.4105"));
            compare(fakeStore.values.weatherPlace.name, "Berlin");
            compare(fakeStore.values.weatherPlace.country, "Germany");
            compare(findChild(weather, "placeName").text, "Berlin, Land Berlin, Germany");
            compare(findChild(weather, "temperature").text, "12°");
            compare(findChild(weather, "condition").text, "Partly cloudy");
            compare(weather.symbol, "cloud-sun");
            compare(weather.Accessible.description, "Berlin, Land Berlin, Germany: 12°, Partly cloudy");
            verify(findChild(weather, "days").visible);
            verify(findChild(weather, "status").text.startsWith("Weather from Open-Meteo · "));
            verify(!findChild(weather, "intro").visible);
            verify(!findChild(weather, "retryButton").visible);
        }

        function test_other_widgets_ask_for_nothing() {
            choosePlace();
            const before = fakeMeteo.requests.length;
            widgets.setShown("calendar", false);
            widgets.setShown("calendar", true);
            wait(100);
            compare(fakeMeteo.requests.length, before);
            compare(findChild(weather, "temperature").text, "12°");
            // Hidden and shown again within half an hour: no new request.
            widgets.setShown("weather", false);
            widgets.setShown("weather", true);
            wait(100);
            compare(fakeMeteo.requests.length, before);
        }

        function test_unknown_city() {
            const field = findChild(weather, "cityField");
            field.forceActiveFocus();
            type("Nowhereville");
            keyClick(Qt.Key_Return);
            tryCompare(findChild(weather, "message"), "text", "No place called “Nowhereville” was found.");
            compare(fakeStore.values.weatherPlace, undefined);
            compare(fakeMeteo.requests.length, 1);
        }

        function test_offline() {
            fakeMeteo.online = false;
            const field = findChild(weather, "cityField");
            field.forceActiveFocus();
            type("Berlin");
            keyClick(Qt.Key_Return);
            tryCompare(findChild(weather, "message"), "text", "Could not search: no connection to Open-Meteo.");
            // A saved place without a connection.
            fakeStore.setValue("weatherPlace", {name: "Berlin", region: "", country: "Germany",
                                                latitude: 52.52437, longitude: 13.41053});
            tryVerify(() => weather.offline, 3000);
            compare(findChild(weather, "status").text, "Weather is unavailable: no connection to Open-Meteo.");
            verify(findChild(weather, "retryButton").visible);
            compare(weather.Accessible.description, "Weather is unavailable offline");
            // Back online: Try again.
            fakeMeteo.online = true;
            waitForRendering(widgets);
            mouseClick(findChild(weather, "retryButton"));
            tryVerify(() => weather.forecast !== null && !weather.offline, 3000);
            // Offline again later: the last values stay, with their time.
            fakeMeteo.online = false;
            weather.refresh();
            tryVerify(() => weather.offline, 3000);
            compare(findChild(weather, "temperature").text, "12°");
            verify(findChild(weather, "status").text.startsWith("Offline · from "));
        }

        function test_change_city() {
            choosePlace();
            waitForRendering(widgets);
            mouseClick(findChild(weather, "changeButton"));
            verify(weather.choosing);
            verify(findChild(weather, "cancelButton").visible);
            tryVerify(() => findChild(weather, "cityField").activeFocus);
            keyClick(Qt.Key_Escape);
            verify(!weather.choosing);
            compare(findChild(weather, "temperature").text, "12°");
        }

        // --- weather.js -----------------------------------------------------

        function test_parse_places() {
            const places = Weather.parsePlaces(root.berlinSearch);
            compare(places.length, 2, "the entry without coordinates is left out");
            compare(Weather.placeLabel(places[0]), "Berlin, Land Berlin, Germany");
            compare(Weather.placeLabel(places[1]), "Berlin, New Hampshire, United States");
            compare(Weather.parsePlaces("{}"), []);
            compare(Weather.parsePlaces("not json"), []);
            compare(Weather.placeLabel({name: "Monaco", region: "Monaco", country: "Monaco"}), "Monaco");
        }

        function test_parse_forecast() {
            const forecast = Weather.parseForecast(root.berlinForecast);
            compare(forecast.temperature, 12.4);
            compare(forecast.code, 2);
            verify(forecast.isDay);
            compare(forecast.unit, "°C");
            compare(forecast.days.length, 4);
            compare(forecast.days[1].date.getDate(), 26);
            compare(forecast.days[1].code, 61);
            compare(forecast.days[3].low, 3.9);
            compare(Weather.parseForecast("{}"), null);
            compare(Weather.parseForecast("<html>"), null);
        }

        function test_urls() {
            compare(Weather.geocodingUrl(" São Paulo ", "pt"),
                    "https://geocoding-api.open-meteo.com/v1/search?name=S%C3%A3o%20Paulo&count=6&language=pt&format=json");
            const url = Weather.forecastUrl({latitude: 52.52437, longitude: -71.185}, true);
            verify(url.startsWith("https://api.open-meteo.com/v1/forecast?latitude=52.5244&longitude=-71.1850&"));
            verify(url.endsWith("&temperature_unit=fahrenheit"));
            verify(!Weather.forecastUrl({latitude: 1, longitude: 2}, false).includes("fahrenheit"));
        }

        function test_describe_data() {
            return [
                {tag: "clear day", code: 0, day: true, text: "Clear", symbol: "sun"},
                {tag: "clear night", code: 0, day: false, text: "Clear", symbol: "night"},
                {tag: "overcast", code: 3, day: true, text: "Overcast", symbol: "cloud"},
                {tag: "fog", code: 48, day: true, text: "Fog", symbol: "fog"},
                {tag: "rain", code: 63, day: true, text: "Rain", symbol: "rain"},
                {tag: "heavy rain", code: 65, day: true, text: "Heavy rain", symbol: "rain"},
                {tag: "snow", code: 75, day: true, text: "Snow", symbol: "snow"},
                {tag: "storm", code: 99, day: true, text: "Thunderstorm with hail", symbol: "storm"},
                {tag: "unknown", code: 42, day: true, text: "Unknown", symbol: "cloud"}
            ];
        }

        function test_describe(data) {
            const result = Weather.describe(data.code, data.day);
            compare(result.text, data.text);
            compare(result.symbol, data.symbol);
            verify(Icons.symbols.indexOf(result.symbol) >= 0, "Star OS has the symbol " + result.symbol);
        }

        function test_degrees() {
            compare(Weather.degrees(12.5), "13°");
            compare(Weather.degrees(-0.4), "0°");
            compare(Weather.degrees(-3.6), "-4°");
        }
    }
}
