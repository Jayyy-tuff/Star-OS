// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton

import QtQuick

// Star OS application icons: original artwork in icons/, looked up by desktop
// file id or Wayland app id. libtaskmanager gives launcher rows the storage id
// ("org.kde.konsole.desktop") and windows the bare id, so ".desktop" is ignored.
QtObject {
    id: icons

    // Resolved here, against this file's location, whoever calls source().
    readonly property url directory: Qt.resolvedUrl("icons/")

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
}
