// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick

// Test double for the launcher catalogue interface (model, count, filter,
// launch(row)). It uses libtaskmanager's role names, and records launches
// instead of starting anything.
Item {
    id: catalogue

    property string filter: ""
    property var apps: []
    property bool launchResult: true
    property var launched: []

    readonly property ListModel model: rows
    readonly property int count: rows.count

    ListModel {
        id: rows
    }

    function refresh() {
        rows.clear();
        const needle = catalogue.filter.toLowerCase();
        const matches = catalogue.apps.filter(app => app.AppName.toLowerCase().includes(needle));
        matches.sort((a, b) => a.AppName.localeCompare(b.AppName));
        for (const app of matches) {
            rows.append({AppName: app.AppName, GenericName: app.GenericName, display: app.AppName});
        }
    }

    function launch(row) {
        catalogue.launched = catalogue.launched.concat([rows.get(row).AppName]);
        return catalogue.launchResult;
    }

    onFilterChanged: refresh()
    onAppsChanged: refresh()
}
