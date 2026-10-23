// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import org.kde.kitemmodels as KItemModels
import org.kde.taskmanager as TaskManager

// Star OS app catalogue adapter (M0.2): a curated list through public API only.
// Phase 1 replaces this backend (a Star OS KService model, or a recorded kicker
// exception), not the StarOS.Shell views.
//
// Interface used by StarOS.Shell's Launcher: model (with libtaskmanager's
// roles, among them AppName, GenericName and AppId), count, filter (writable),
// launch(row) returning true when a launch was requested.
Item {
    id: catalogue

    property string filter: ""
    readonly property var model: searchable
    readonly property int count: searchable.count

    // KDE applications that the iteration-0 probe found installed and visible
    // at the pinned snapshot, then the Star OS applications (M0.3 packages).
    // Tests never assume their order or number.
    // M0.4 adds Star Lens, Star Storage and the preinstalled apps.
    readonly property list<string> desktopIds: [
        "org.kde.konsole.desktop",
        "systemsettings.desktop",
        "org.staros.files.desktop",
        "org.staros.sunstore.desktop",
        "org.staros.lens.desktop",
        "org.staros.storage.desktop",
        "firefox.desktop",
        "vlc.desktop",
        "org.kde.okular.desktop",
        "org.kde.gwenview.desktop",
        "org.kde.ark.desktop",
        "org.kde.kwrite.desktop",
        "org.kde.kcalc.desktop"
    ]

    visible: false

    onCountChanged: console.info("STAROS-SHELL catalogue=" + count)

    // LauncherTasksModel is not exposed to QML; a TasksModel with a launcher
    // list and separate launchers is the public route. Launcher rows stay
    // visible while their application runs (hideActivatedLaunchers false).
    TaskManager.TasksModel {
        id: launchers
        launcherList: catalogue.desktopIds.map(id => "applications:" + id)
        separateLaunchers: true
        hideActivatedLaunchers: false
        groupMode: TaskManager.TasksModel.GroupDisabled
    }

    // Launcher rows only. A callable filterRowCallback disables filterString,
    // so the search is a second proxy.
    KItemModels.KSortFilterProxyModel {
        id: launcherRows
        sourceModel: launchers
        filterRowCallback: (row, parent) => launchers.data(launchers.index(row, 0, parent),
            TaskManager.AbstractTasksModel.IsLauncher) === true
    }

    KItemModels.KSortFilterProxyModel {
        id: searchable
        sourceModel: launcherRows
        filterRoleName: "AppName"
        filterString: catalogue.filter
        filterCaseSensitivity: Qt.CaseInsensitive
        sortRoleName: "AppName"
        sortCaseSensitivity: Qt.CaseInsensitive
    }

    // Launches a catalogue app by desktop id (with or without ".desktop").
    function launchDesktopId(desktopId) {
        const wanted = String(desktopId).replace(/\.desktop$/, "");
        for (let row = 0; row < launcherRows.count; ++row) {
            const source = launcherRows.mapToSource(launcherRows.index(row, 0));
            const appId = String(launchers.data(source, TaskManager.AbstractTasksModel.AppId) ?? "");
            if (appId.replace(/\.desktop$/, "") === wanted) {
                console.info("STAROS-SHELL launch=" + appId);
                launchers.requestNewInstance(source);
                return true;
            }
        }
        console.warn("STAROS-SHELL not in the catalogue: " + desktopId);
        return false;
    }

    function launch(row) {
        if (row < 0 || row >= searchable.count) {
            return false;
        }
        const source = launcherRows.mapToSource(searchable.mapToSource(searchable.index(row, 0)));
        console.info("STAROS-SHELL launch=" + launchers.data(source, TaskManager.AbstractTasksModel.AppId));
        launchers.requestNewInstance(source);
        return true;
    }
}
