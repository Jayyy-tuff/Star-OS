// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton

import QtQuick

// Star OS artwork: application icons in icons/, looked up by desktop file id
// or Wayland app id (libtaskmanager gives launcher rows the storage id,
// "org.kde.konsole.desktop", and windows the bare id, so ".desktop" is
// ignored); line symbols in symbols/ (24x24, white); the Star OS logo.
QtObject {
    id: icons

    // Resolved here, against this file's location, whoever calls source().
    readonly property url directory: Qt.resolvedUrl("icons/")
    readonly property url symbolDirectory: Qt.resolvedUrl("symbols/")
    readonly property url logo: Qt.resolvedUrl("brand/star.svg")

    // Every symbol in symbols/, by name.
    readonly property var symbols: ["search", "wifi", "wifi-off", "wired", "volume", "volume-low", "volume-mute",
        "battery", "brightness", "night", "bell", "bell-off", "power", "lock", "logout", "restart", "settings",
        "chevron-right", "chevron-left", "chevron-up", "chevron-down", "close", "clipboard", "gamepad", "grid", "pin",
        "plus", "trash", "copy", "check", "sun", "cloud", "cloud-sun", "rain", "snow", "storm", "fog", "cpu", "memory",
        "disk", "airplane", "bolt", "calendar", "user", "screenshot"]

    // The icon's url, or an empty string when Star OS has no icon for the id.
    function source(appId) {
        switch (String(appId).replace(/\.desktop$/, "")) {
        case "org.kde.konsole":
            return icons.directory + "terminal.svg";
        case "systemsettings":
        case "org.kde.systemsettings":
            return icons.directory + "settings.svg";
        case "org.staros.files":
            return icons.directory + "files.svg";
        case "org.staros.sunstore":
            return icons.directory + "sun-store.svg";
        case "org.staros.lens":
            return icons.directory + "lens.svg";
        case "org.staros.storage":
            return icons.directory + "storage.svg";
        case "org.staros.games":
            return icons.directory + "games.svg";
        case "org.staros.welcome":
            return icons.directory + "welcome.svg";
        // Prepared for the owner's Moon Browser; no browser ships yet.
        case "moon":
        case "moon-browser":
        case "org.staros.moon":
        case "org.staros.moonbrowser":
            return icons.directory + "moon-browser.svg";
        default:
            return "";
        }
    }

    // A symbol's url; an empty string for a name that is not in symbols.
    function symbol(name) {
        return icons.symbols.indexOf(name) >= 0 ? icons.symbolDirectory + name + ".svg" : "";
    }
}
