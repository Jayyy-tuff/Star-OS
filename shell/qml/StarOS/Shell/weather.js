// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library

// Open-Meteo for the desktop's Weather widget (ADR-0015): the two request
// URLs, reading their JSON, and words and symbols for the WMO weather codes
// Open-Meteo reports. Nothing here sends anything; the widget calls its
// fetch function only after the person chose a place.

const geocodingBase = "https://geocoding-api.open-meteo.com/v1/search";
const forecastBase = "https://api.open-meteo.com/v1/forecast";

function geocodingUrl(name, language) {
    return geocodingBase + "?name=" + encodeURIComponent(String(name).trim()) + "&count=6&language="
        + encodeURIComponent(language || "en") + "&format=json";
}

function forecastUrl(place, fahrenheit) {
    return forecastBase + "?latitude=" + Number(place.latitude).toFixed(4)
        + "&longitude=" + Number(place.longitude).toFixed(4)
        + "&current=temperature_2m,weather_code,is_day"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        + "&timezone=auto&forecast_days=4"
        + (fahrenheit ? "&temperature_unit=fahrenheit" : "");
}

function parse(text) {
    try {
        return JSON.parse(text);
    } catch (error) {
        return null;
    }
}

// Places matching a search, as {name, region, country, latitude, longitude}.
function parsePlaces(text) {
    const data = parse(text);
    if (!data || !Array.isArray(data.results)) {
        return [];
    }
    return data.results.filter(r => typeof r.latitude === "number" && typeof r.longitude === "number" && r.name)
        .map(r => ({
            name: String(r.name),
            region: r.admin1 ? String(r.admin1) : "",
            country: r.country ? String(r.country) : "",
            latitude: r.latitude,
            longitude: r.longitude
        }));
}

function placeLabel(place) {
    if (!place) {
        return "";
    }
    return [place.name, place.region, place.country].filter((part, i, all) => part && all.indexOf(part) === i)
        .join(", ");
}

// The current weather and the next days, or null when the answer is not
// a forecast: {temperature, code, isDay, unit, days: [{date, code, high, low}]}.
function parseForecast(text) {
    const data = parse(text);
    if (!data || !data.current || typeof data.current.temperature_2m !== "number") {
        return null;
    }
    const daily = data.daily || {};
    const times = Array.isArray(daily.time) ? daily.time : [];
    const days = [];
    for (let i = 0; i < times.length; ++i) {
        const high = daily.temperature_2m_max ? daily.temperature_2m_max[i] : undefined;
        const low = daily.temperature_2m_min ? daily.temperature_2m_min[i] : undefined;
        if (typeof high !== "number" || typeof low !== "number") {
            continue;
        }
        const parts = String(times[i]).split("-").map(Number);
        days.push({
            date: new Date(parts[0], parts[1] - 1, parts[2]),
            code: daily.weather_code ? Number(daily.weather_code[i]) : -1,
            high: high,
            low: low
        });
    }
    return {
        temperature: data.current.temperature_2m,
        code: Number(data.current.weather_code),
        isDay: data.current.is_day !== 0,
        unit: data.current_units && data.current_units.temperature_2m ? String(data.current_units.temperature_2m) : "°C",
        days: days
    };
}

function degrees(value) {
    return Math.round(value) + "°";
}

// Words and a StarOS.Shell symbol for a WMO weather code.
function describe(code, isDay) {
    const sun = isDay === false ? "night" : "sun";
    switch (Number(code)) {
    case 0:
        return {text: qsTr("Clear"), symbol: sun};
    case 1:
        return {text: qsTr("Mainly clear"), symbol: isDay === false ? "night" : "cloud-sun"};
    case 2:
        return {text: qsTr("Partly cloudy"), symbol: "cloud-sun"};
    case 3:
        return {text: qsTr("Overcast"), symbol: "cloud"};
    case 45:
    case 48:
        return {text: qsTr("Fog"), symbol: "fog"};
    case 51:
    case 53:
    case 55:
        return {text: qsTr("Drizzle"), symbol: "rain"};
    case 56:
    case 57:
        return {text: qsTr("Freezing drizzle"), symbol: "rain"};
    case 61:
    case 63:
    case 65:
        return {text: Number(code) === 65 ? qsTr("Heavy rain") : qsTr("Rain"), symbol: "rain"};
    case 66:
    case 67:
        return {text: qsTr("Freezing rain"), symbol: "rain"};
    case 71:
    case 73:
    case 75:
    case 77:
        return {text: qsTr("Snow"), symbol: "snow"};
    case 80:
    case 81:
    case 82:
        return {text: qsTr("Rain showers"), symbol: "rain"};
    case 85:
    case 86:
        return {text: qsTr("Snow showers"), symbol: "snow"};
    case 95:
        return {text: qsTr("Thunderstorm"), symbol: "storm"};
    case 96:
    case 99:
        return {text: qsTr("Thunderstorm with hail"), symbol: "storm"};
    default:
        return {text: qsTr("Unknown"), symbol: "cloud"};
    }
}

// GET through XMLHttpRequest; calls back with (ok, text).
function request(url, callback) {
    const xhr = new XMLHttpRequest();
    xhr.onreadystatechange = () => {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            callback(xhr.status === 200, xhr.responseText);
        }
    };
    xhr.open("GET", url);
    xhr.send();
}
