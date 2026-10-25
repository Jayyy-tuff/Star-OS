// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// Test double for StarOS.System's ApplicationsModel as the start menu uses
// it: model (rows with 'AppName', 'GenericName', 'AppId', 'decoration',
// 'IsNew' and 'Section'), count, filter, revision, recentlyInstalled,
// apps(ids), launch(row) and launchDesktopId(id). It matches names
// containing the filter, sorted by name, and records launches instead of
// starting anything.
Item {
    id: catalogue

    property string filter: ""
    // The installed apps: {AppName, GenericName, AppId, decoration, IsNew}.
    property var entries: []
    // What recentlyInstalled returns: app maps with InstalledAt and Source.
    property var recent: []
    property bool launchResult: true
    property var launched: []
    property int revision: 0

    readonly property var recentlyInstalled: catalogue.recent
    readonly property ListModel model: rows
    readonly property int count: rows.count

    ListModel {
        id: rows
    }

    function refresh() {
        rows.clear();
        const needle = catalogue.filter.toLowerCase().trim();
        const matches = catalogue.entries.filter(app => needle === "" || app.AppName.toLowerCase().includes(needle));
        matches.sort((a, b) => a.AppName.localeCompare(b.AppName));
        for (const app of matches) {
            rows.append({AppName: app.AppName, GenericName: app.GenericName ?? "", AppId: app.AppId ?? "",
                         decoration: app.decoration ?? "", IsNew: app.IsNew === true,
                         Section: app.AppName.charAt(0).toUpperCase(), display: app.AppName});
        }
    }

    function find(desktopId) {
        const app = catalogue.entries.find(entry => entry.AppId === desktopId);
        return app ? app : ({});
    }

    function apps(desktopIds) {
        return desktopIds.map(id => catalogue.find(id)).filter(app => app.AppName !== undefined);
    }

    function launch(row) {
        catalogue.launched = catalogue.launched.concat([rows.get(row).AppName]);
        return catalogue.launchResult;
    }

    function launchDesktopId(desktopId) {
        const app = catalogue.find(desktopId);
        if (app.AppName === undefined) {
            return false;
        }
        catalogue.launched = catalogue.launched.concat([app.AppName]);
        return catalogue.launchResult;
    }

    onFilterChanged: refresh()
    onEntriesChanged: {
        refresh();
        catalogue.revision += 1;
    }
}
