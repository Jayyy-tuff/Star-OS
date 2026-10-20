# M0.2 shell prototype — design specification

Status: accepted with [ADR-0008](../decisions/0008-m02-shell-hosting-and-live-session.md) (2026-10-20).

This is the engineering specification behind ADR-0008. It was produced by three
independent designs, two independent reviews and a synthesis, checked against
upstream source at the baseline tags (KWin/Plasma 6.7.5, Qt 6.12.0, KF 6.31.0,
archiso 91) and against CI probes of the pinned 2026-10-15 snapshot. Items in
"Open unknowns" are not facts yet; iteration 0 and later CI runs settle them,
and this document is updated when they do.

Code sketches below are design intent, not the shipped files. The repository
files are authoritative once they exist.

## Session chain

BOOT → AUTOLOGIN → SESSION START → SHELL

1) Boot
- Boot entries and the M0.1 staros-boot-check (STAROS-LIVE-BOOT-OK) are unchanged.
- default.target resolves to graphical.target, which the policy check asserts. graphical.target Wants display-manager.service, which the overlay links to our unit:
  airootfs/etc/systemd/system/display-manager.service -> /etc/systemd/system/staros-live-session.service
- build-iso.sh removes these releng paths, listed in distro/archiso/staros/releng-remove.txt. The build fails if a listed path no longer exists.
  airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf
  airootfs/etc/systemd/system/multi-user.target.wants/sshd.service
- sshd is also masked: airootfs/etc/systemd/system/sshd.service -> /dev/null.

2) Autologin: airootfs/etc/systemd/system/staros-live-session.service. This is live medium only; the installer must never copy it.
# SPDX-License-Identifier: GPL-3.0-or-later
# Star OS live medium only (M0.2, ADR-0008): logs the unprivileged live user into the
# Star OS prototype session on tty1 without a display manager. Modelled on KDE's
# plasma-mobile.service. The display manager is chosen in Phase 1.
[Unit]
Description=Star OS live session on tty1 (prototype)
Conflicts=getty@tty1.service
After=getty@tty1.service systemd-user-sessions.service plymouth-quit-wait.service systemd-logind.service
Wants=dbus.socket
After=dbus.socket
Before=graphical.target
OnFailure=getty@tty1.service
StartLimitIntervalSec=120
StartLimitBurst=3
ConditionPathExists=/dev/tty0
[Service]
User=liveuser
PAMName=login
WorkingDirectory=~
# systemd v262 passes these to PAM before pam_open_session; pam_systemd then records
# a wayland session on seat0, VT 1 (XDG_VTNR must be a number).
Environment=LANG=C.UTF-8 XDG_SESSION_TYPE=wayland XDG_SESSION_CLASS=user XDG_SESSION_DESKTOP=KDE XDG_SEAT=seat0 XDG_VTNR=1
ExecStart=/usr/local/bin/startstaros
Restart=always
RestartSec=5s
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty-fail
StandardOutput=journal
StandardError=journal
UtmpIdentifier=tty1
UtmpMode=user
[Install]
Alias=display-manager.service

How the unit behaves:
- pam_systemd starts user@1000.service and sets XDG_RUNTIME_DIR and DBUS_SESSION_BUS_ADDRESS, so no dbus-run-session wrapper is needed.
- A logout ends startplasma, and the unit starts a new session after 5 s; that is live-ISO behaviour.
- If the session fails three times within 120 s, getty@tty1 shows a plain login prompt. It has no autologin, because releng's drop-in is gone.

3) Session script: airootfs/usr/local/bin/startstaros (file_permissions 0:0:755)
#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Star OS prototype session (M0.2, ADR-0004 option A, ADR-0008): Plasma's Wayland
# startup with plasmashell loading the Star OS shell package (Plasma Mobile pattern).
# Sets no test or permission-bypass variables (scripts/ci/check-image-policy.sh).
export PLASMA_DEFAULT_SHELL=org.staros.shell
# archiso 'speech' boot entries (accessibility=on): kaccess starts Orca at login when
# kaccessrc [ScreenReader] Enabled=true. Applied once per boot so that a later
# Meta+Alt+S toggle-off survives a re-login.
if grep -qw accessibility=on /proc/cmdline && [ ! -e /tmp/staros-a11y-applied ]; then
    kwriteconfig6 --file kaccessrc --group ScreenReader --key Enabled true && : >/tmp/staros-a11y-applied
fi
exec /usr/bin/startplasma-wayland

4) startplasma-wayland (plasma-workspace 6.7.5)
- It syncs the environment, including PLASMA_DEFAULT_SHELL, into D-Bus activation and systemd --user.
- It starts ksplash only if ksplashrc Engine is KSplashQML. Live config sets Engine=none, so no splash can hide a startup hang.
- It starts plasma-workspace-wayland.target:
  - plasma-kwin_wayland.service: kwin_wayland_wrapper --xwayland, on DRM through the logind seat0 session; kglobalaccel runs inside KWin.
  - plasma-core.target: plasmashell --no-respawn (no -p), kded6, ksmserver and kcminit.
  - plasma-workspace.target: kaccess, polkit agent, powerdevil, and kde-baloo, which is skipped by its ExecCondition because Indexing-Enabled=false.

5) plasmashell
- ShellCorona::defaultShell() reads plasmashellrc [Shell] ShellPackage. None exists, which the policy check and the session report verify. It then uses PLASMA_DEFAULT_SHELL = org.staros.shell.
- load() waits for kactivitymanagerd. The package is listed explicitly, because without it plasmashell logs 'Aborting shell load'.
- On first run (the home is fresh every boot):
  - addOutput() creates org.staros.desktop per screen, from contents/defaults;
  - contents/layout.js runs, because no look-and-feel package ships org.staros.shell-layout.js;
  - the layout is saved in ~/.config/plasma-org.staros.shell-appletsrc.

Shell package files (shell/plasma/shells/org.staros.shell/):
- metadata.json; its licence is in metadata.json.license, which is not copied into the image:
  {'KPackageStructure': 'Plasma/Shell', 'KPlugin': {'Id': 'org.staros.shell', 'Name': 'Star OS shell (prototype)', 'License': 'GPL-3.0-or-later', 'Version': '0.2', 'Authors': [{'Name': 'Star OS project'}]}, 'X-KDE-ParentApp': 'org.kde.plasmashell', 'X-Plasma-APIVersion': '2', 'X-Plasma-FallbackPackage': 'org.kde.plasma.desktop'}
  The real file is JSON with double quotes. The fallback is libplasma's default, made explicit. APIVersion 2 lets kscreenlocker's package check accept the package.
- contents/defaults:
  # SPDX-License-Identifier: GPL-3.0-or-later
  [Desktop]
  Containment=org.staros.desktop
  ToolBox=
  [Desktop][ContainmentActions]
  [Panel]
  Containment=org.staros.taskbar
  ToolBox=
  [Panel][ContainmentActions]
  With no containment actions there is no Plasma right-click or edit-mode menu. The empty ToolBox logs a known warning, which CI whitelists.
- contents/layout.js:
  // SPDX-License-Identifier: GPL-3.0-or-later
  // First-run layout of the Star OS prototype shell (M0.2).
  for (const desk of desktopsForActivity(currentActivity())) {
      desk.wallpaperPlugin = 'org.kde.color';   // valid pure-QML plugin: avoids the 6.7 missing-wallpaper hang
      desk.currentConfigGroup = ['Wallpaper', 'org.kde.color', 'General'];
      desk.writeConfig('Color', '#24364a');      // Theme.desktop, matched by the CI screen check
      desk.locked = true;                        // writable property at 6.7.5: UserImmutable
  }
  const panel = new Panel('org.staros.taskbar');
  panel.location = 'bottom';
  panel.height = Math.round(2.5 * gridUnit);    // seed only; views/Panel.qml sets Theme.taskbarHeight
  panel.lengthMode = 'fill';
  panel.hiding = 'none';
  panel.floating = false;                        // PanelView floats by default on Wayland
  panel.locked = true;
- contents/views/Desktop.qml and contents/views/Panel.qml are original, following plasma-nano's contract:
  // SPDX-License-Identifier: GPL-3.0-or-later
  import QtQuick
  import StarOS.Shell
  Item {
      id: root
      property Item containment
      onContainmentChanged: {
          if (!containment) return;
          containment.parent = root;
          containment.anchors.fill = root;
          containment.visible = true;
          panel.backgroundHints = containment.plasmoid.backgroundHints;  // NoBackground (Panel.qml only)
          panel.thickness = Theme.taskbarHeight;                         // font-derived (Panel.qml only)
      }
  }

6) Live-only user configuration in airootfs/home/liveuser/.config/ (not /etc/skel). mkarchiso copies skel with --update=none and chowns the home to 1000:1000. Each file starts with an SPDX comment.
- ksplashrc: [KSplash] Engine=none
- kscreenlockerrc: [Daemon] Autolock=false, LockOnResume=false
- kdeglobals: [KDE Action Restrictions] action/lock_screen=false. ksldapp and interface check KAuthorized 'lock_screen'.
- powerdevilrc: [AC][Display] DimDisplayWhenIdle=false, TurnOffDisplayWhenIdle=false; [AC][SuspendAndShutdown] AutoSuspendAction=0
- kwalletrc: [Wallet] Enabled=false
- baloofilerc: [Basic Settings] Indexing-Enabled=false. This makes kde-baloo.service's ExecCondition skip the indexer.

7) Serial session report. airootfs/etc/systemd/system/staros-session-report.service is enabled by a graphical.target.wants symlink, the same pattern as M0.1. ExecStart=/usr/local/libexec/staros-session-report runs as root, read-only, under python3 -I with only the standard library.
- Phase 1, ready (up to 300 s):
  - runs loginctl for the liveuser session: Type, Seat, VTNr;
  - as liveuser (runuser with XDG_RUNTIME_DIR=/run/user/1000 and DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus), reads org.kde.PlasmaShell.shell over busctl --user and calls evaluateScript with print(JSON.stringify({panels: panels().map(p => ({type: p.type, location: p.location, height: p.height, floating: p.floating})), desktops: desktops().map(d => ({type: d.type, wallpaper: d.wallpaperPlugin}))}));
  - reads the renderer from org.kde.KWin supportInformation;
  - reads MainPID and NRestarts of plasma-plasmashell (user) and staros-live-session (system);
  - checks the grant precondition: org.kde.plasmashell.desktop lists org_kde_plasma_window_management;
  - prints the STAROS-SHELL ready line from journalctl _UID=1000 when present.
  It prints 'STAROS-SESSION-CHECK seconds=.. user=liveuser logind_type=wayland seat=seat0 vt=1 shell=org.staros.shell layout={...} renderer=... grant=ok' and then STAROS-SESSION-OK or STAROS-SESSION-FAIL reason=...
- Phase 2, idle: from ready+240 s it samples for 60 s, then prints 'STAROS-IDLE-REPORT {json}' and STAROS-IDLE-DONE.
- Phase 3, stable (ready+330 s): it compares PIDs and restart counts and prints STAROS-SESSION-STABLE or STAROS-SESSION-UNSTABLE reason=...
- Output goes to the journal and, if /dev/ttyS0 is a character device, to the serial port (with a timeout). It is identical in QEMU and VMware.

## Shell architecture

PROCESSES
No Star OS process runs. All of these run as liveuser and are started by Plasma's own units:
- kwin_wayland, under kwin_wayland_wrapper --xwayland. KGlobalAccelD runs inside KWin; the plasma-kglobalaccel unit's kglobalacceld exits at once on Wayland. Xwayland starts on demand.
- plasmashell, which hosts every Star OS surface.
- kactivitymanagerd, ksmserver, kded6, kaccess, polkit-kde-authentication-agent-1 and powerdevil. The CI probe showed these packages are pulled in by plasma-workspace and plasma-desktop dependencies.
- On demand only: xdg-desktop-portal(-kde), pipewire/wireplumber user units, and the at-spi bus plus Orca when accessibility is on.
- baloo is installed but skipped by its ExecCondition.
The idle report lists every process, so the number is the cost of a full option-A session, not only the shell.

INSTALLED TREE (build-iso.sh copies it from shell/; no package owns these paths)
- /usr/lib/qt6/qml/StarOS/Shell/: qmldir, Theme.qml (singleton), FocusFrame.qml, ShellButton.qml, TaskButton.qml, Taskbar.qml, LauncherTile.qml, Launcher.qml. These import only QtQuick and QtQuick.Templates, and have no Kirigami, Plasma or QQC2 style.
- /usr/share/plasma/shells/org.staros.shell/: metadata.json, contents/{defaults, layout.js, views/Desktop.qml, views/Panel.qml}.
- /usr/share/plasma/plasmoids/org.staros.taskbar/: metadata.json, contents/ui/{main.qml, AppCatalogue.qml, LauncherWindow.qml}. These are the only Star OS files that import Plasma or KDE modules.
- /usr/share/plasma/plasmoids/org.staros.desktop/: metadata.json, contents/ui/main.qml (an empty ContainmentItem; libplasma draws the org.kde.color wallpaper at z -1000).

FALLBACK FILES
Anything not shipped (lockscreen/, applet error UI, activitymanager/) falls back to org.kde.plasma.desktop from plasma-desktop. The logout greeter is not a shell-package file: at 6.7.5 it loads the Look-and-Feel package (Breeze).

METADATA OF THE PANEL CONTAINMENT (org.staros.taskbar/metadata.json, licence in .license)
{'KPackageStructure': 'Plasma/Applet', 'KPlugin': {'Id': 'org.staros.taskbar', 'Name': 'Star OS taskbar', 'Description': 'Star OS prototype taskbar and full-screen launcher', 'License': 'GPL-3.0-or-later', 'Version': '0.2', 'Authors': [{'Name': 'Star OS project'}]}, 'X-Plasma-API-Minimum-Version': '6.0', 'X-Plasma-ContainmentType': 'Panel', 'X-Plasma-Provides': ['org.kde.plasma.launchermenu'], 'NoDisplay': true}
- The real file is JSON with double quotes.
- libplasma 6.7.5 creates a Plasma::Containment for a pure KPackage whose metadata has X-Plasma-ContainmentType, and reads the type from that key. plasma-desktop's own org.kde.panel is the same class plus a generated trivial subclass, so a pure Panel package is low risk.
- org.staros.desktop has the same shape, with type Desktop and no Provides.

PLASMA ADAPTER: org.staros.taskbar contents/ui/main.qml (sketch)
// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager
import StarOS.Shell
ContainmentItem {
    id: root
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    TaskManager.TasksModel {                       // open windows (startup placeholders included)
        id: windows
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        onCountChanged: console.info('STAROS-SHELL tasks=' + count)
    }
    AppCatalogue { id: catalogue }
    Taskbar {
        anchors.fill: parent
        tasksModel: windows
        onLauncherRequested: launcherWindow.toggleLauncher()
        onActivateRequested: row => {
            const idx = windows.makeModelIndex(row)
            if (windows.data(idx, TaskManager.AbstractTasksModel.IsActive) === true) windows.requestToggleMinimized(idx)
            else windows.requestActivate(idx)
        }
        onLeaveRequested: DBus.SessionBus.asyncCall({service: 'org.kde.LogoutPrompt', path: '/LogoutPrompt', iface: 'org.kde.LogoutPrompt', member: 'promptAll'})
    }
    LauncherWindow { id: launcherWindow; catalogue: catalogue }
    Plasmoid.onActivated: launcherWindow.toggleLauncher()   // Meta / Alt+F1 (X-Plasma-Provides launchermenu)
    Component.onCompleted: console.info('STAROS-SHELL ready shell=org.staros.shell gridUnit=' + Theme.gridUnit + ' taskbarHeight=' + Theme.taskbarHeight + ' focusRing=' + Theme.focusRingWidth)
}

LauncherWindow.qml (sketch)
import QtQuick
import QtQuick.Window
import org.kde.layershell as LayerShell
import StarOS.Shell
Window {
    id: win
    required property Item catalogue
    property bool hadFocus: false
    visible: false
    transientParent: null
    title: qsTr('Star OS applications')
    color: Theme.launcherBackdrop
    LayerShell.Window.scope: 'staros-launcher'                   // unknown scope: KWin type Normal
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityExclusive  // KWin 6.7.5 keeps only 'accepts focus'
    LayerShell.Window.activateOnShow: true
    function toggleLauncher() { visible ? hideLauncher() : showLauncher() }
    function showLauncher() { launcher.reset(); hadFocus = false; visible = true; console.info('STAROS-SHELL launcher=open') }
    function hideLauncher() { if (!visible) return; visible = false; console.info('STAROS-SHELL launcher=closed') }
    onActiveChanged: { if (active) hadFocus = true; else if (visible && hadFocus) hideLauncher() }  // Alt+Tab or a click elsewhere
    Launcher { id: launcher; anchors.fill: parent; catalogue: win.catalogue; onCloseRequested: win.hideLauncher() }
}

STAROS.SHELL (host-independent, unit-tested; outlines)
- Theme.qml (pragma Singleton, a QtObject):
  - readonly property FontMetrics metrics: FontMetrics {}
  - gridUnit = max(16, 2*ceil(metrics.height/2)), in logical px, so it follows the user's font size
  - spacing = gridUnit/2; taskbarHeight = max(40, round(2.5*gridUnit)); minTarget = max(32, 2*gridUnit)
  - startButtonWidth 8gu, taskButtonWidth 12gu (shrinks to fit), tileWidth 9gu, tileHeight 7gu, monogramSize 3gu, searchHeight 2.5gu, launcherMargin 2gu
  - focusRingWidth 3, animationDuration 0
  - Reserved colours, matched by the CI screen analysis and not used elsewhere: desktop #24364a, taskbar #16202c, taskbarButton #1f2b3a, launcherBackdrop #0e141b, tile #223041, monogram #2c4058, searchField #1a2531, searchBorder #7d8fa3, text #f2f5f8, placeholder #a9b6c4, activeIndicator #5cc8a8, focusRing #ffb400
- FocusFrame.qml: a transparent Rectangle with border.width Theme.focusRingWidth, border.color Theme.focusRing, radius 0 and z 100. Its visibility is bound by the parent to activeFocus.
- ShellButton.qml and TaskButton.qml: T.AbstractButton (non-checkable, so QAccessible::Button) with an own background and contentItem, Keys.onReturnPressed and onEnterPressed calling clicked(), and a FocusFrame. TaskButton also takes required appName, title and isActive; Accessible.description is 'Active window' or 'Window'; a 3 px activeIndicator bar shows when active.
- Taskbar.qml: a FocusScope (Accessible.role ToolBar, name 'Taskbar') containing:
  - ShellButton 'Applications', the first item in the tab chain, which PanelView focuses on Meta+Alt+P;
  - a horizontal ListView 'Open windows' (Accessible.role List; description 'No open windows' when empty; activeFocusOnTab: count > 0; keyNavigationEnabled; KeyNavigation.priority AfterItem);
  - ShellButton 'Leave' (description 'Log out, restart or shut down').
  It emits launcherRequested(), activateRequested(row) and leaveRequested(). It does not handle Escape, so PanelView's Escape restores the previous window.
- Launcher.qml: a FocusScope (Accessible.role Pane, name 'Application launcher'). Its interface is required property Item catalogue (model with role AppName, GenericName and display; count; filter, writable; launch(row) returning bool) and signal closeRequested(). It contains:
  - T.TextField 'Search applications' with a searchField background, a 1 px searchBorder and a FocusFrame; it gets focus on reset();
  - a GridView 'Applications' (role List, keyNavigationEnabled, clip) with LauncherTile delegates (T.AbstractButton: monogram plus label; Accessible.name is AppName and Accessible.description is GenericName);
  - a 'No applications match' text.
  Keys: typing filters; Down or Tab moves to the grid; Up on the first row returns to search; printable keys in the grid go to search; Return in search launches the first match; Escape closes. launch(row) calls catalogue.launch(row) and closes on true.

WHY NO C++
- Pure KPackage containments load without compiled code (libplasma 6.7.5 pluginloader).
- plasma-mobile 6.7.5 creates LayerShell QML Windows inside plasmashell and uses Plasmoid.onActivated on containments.
- TasksModel, KSortFilterProxyModel and the layer-shell attached type are installed QML modules.
- The grants come from org.kde.plasmashell.desktop.
- The only gap is a full app catalogue, which is deferred to Phase 1.

PLASMA SURFACES STILL REACHABLE (inventory for ADR-0004; nothing copied)
- the logout greeter (Breeze Look-and-Feel);
- the Plasma lock screen QML from the fallback package (locking is disabled for the live user);
- the activity switcher on Meta+Q;
- KWin's Alt+Tab and Overview;
- the getty prompt as failure fallback.

CONTINGENCIES
- If the pure Panel containment misbehaves in PanelView: use plasma-desktop's org.kde.panel holding two Star OS pure-QML applets, with X-Plasma-Provides moved to the launcher applet.
- If Meta+Alt+P focus misbehaves: an 'Open windows' row in the launcher.

## App catalogue

M0.2 uses a curated catalogue through public API only. The adapter interface keeps the views independent of the backend.

Interface consumed by StarOS.Shell's Launcher:
- model: rows with the roles AppName, GenericName and display;
- count;
- filter: a writable string;
- launch(row): returns bool.
Tests use FakeCatalogue (a ListModel plus a JS filter), so unit tests exercise the same bindings.

Backend: org.staros.taskbar/contents/ui/AppCatalogue.qml (sketch)
// SPDX-License-Identifier: GPL-3.0-or-later
// Star OS app catalogue adapter (M0.2): curated and public-API only. Phase 1 replaces
// this backend (Star OS KService model, or a recorded kicker exception), not the views.
import QtQuick
import org.kde.taskmanager as TaskManager
import org.kde.kitemmodels as KItemModels
Item {
    id: catalogue
    visible: false
    property string filter: ''
    readonly property var model: searchable
    readonly property int count: searchable.count
    // Desktop ids confirmed installed and visible by iteration 0; tests never assume order or number.
    readonly property list<string> desktopIds: ['org.kde.konsole.desktop', 'systemsettings.desktop', 'org.kde.kmenuedit.desktop']
    TaskManager.TasksModel {
        id: launchers
        launcherList: catalogue.desktopIds.map(id => 'applications:' + id)
        separateLaunchers: true
        hideActivatedLaunchers: false          // default true would hide a tile while its app runs
        groupMode: TaskManager.TasksModel.GroupDisabled
    }
    KItemModels.KSortFilterProxyModel {        // launcher rows only
        id: launcherRows
        sourceModel: launchers
        filterRowCallback: (row, parent) => launchers.data(launchers.index(row, 0, parent), TaskManager.AbstractTasksModel.IsLauncher) === true
    }
    KItemModels.KSortFilterProxyModel {        // a callable filterRowCallback disables filterString, so search is a second proxy
        id: searchable
        sourceModel: launcherRows
        filterRoleName: 'AppName'
        filterString: catalogue.filter
        filterCaseSensitivity: Qt.CaseInsensitive
        sortRoleName: 'AppName'
    }
    function launch(row) {
        if (row < 0 || row >= searchable.count) return false
        const src = launcherRows.mapToSource(searchable.mapToSource(searchable.index(row, 0)))
        console.info('STAROS-SHELL launch=' + launchers.data(src, TaskManager.AbstractTasksModel.AppId))
        launchers.requestNewInstance(src)
        return true
    }
}

Why this shape
- LauncherTasksModel is not exposed to QML at 6.7.5; only TasksModel, VirtualDesktopInfo, ActivityInfo and a few others are. A TasksModel launcherList with separateLaunchers is therefore the public route.
- 'applications:systemsettings.desktop' is KDE's own default launcher id (plasma-desktop main.xml).
- libtaskmanager resolves AppName, GenericName and AppId through KService.
- requestNewInstance launches through KIO with an xdg-activation token. plasmashell is privileged for activation in 6.7.5 (requestedInterfaces), and by executable name in 6.8.
- orca.desktop is NoDisplay=true, so it is not a catalogue entry. Orca is started by Meta+Alt+S.
- If systemsettings or kmenuedit is missing or hidden (iteration 0 checks), the fallback is fewer tiles plus a second Konsole window for the list and switch checks. The harness requires at least 2 launchable tiles and reads names from the AT-SPI walk.

Not used
- org.kde.plasma.private.kicker: private and unstable, needs an owner exception, and its contract test would need KActivities in a container. A CI gate fails on any 'org.kde.plasma.private' import.
- Qt.labs FolderListModel over /usr/share/applications: it shows NoDisplay and OnlyShowIn entries.
- KRunner/Milou: the services runner returns nothing for an empty query.

Phase 1
The full catalogue (all applications, categories, icons) needs a small Star OS C++ model over KService/KApplicationTrader and KIO::ApplicationLauncherJob, which brings in a C++ build path, or a recorded kicker exception. ADR-0008 records that 'no C++' is an M0.2 property only, and that a C++ build path in Phase 1 reduces B's extra cost.

## Window list and focus

WINDOW LIST
- TasksModel (org.kde.taskmanager) runs inside plasmashell.
- KWin 6.7.5 offers org_kde_plasma_window_management only to the executable whose installed desktop file lists it. /usr/share/applications/org.kde.plasmashell.desktop (Exec=/usr/bin/plasmashell) lists it, together with activation_feedback and lockscreen_overlay. No new grant and no bypass are needed.
- The serial report checks that precondition, and the container probe asserts KWin's debug line 'authorized /usr/bin/plasmashell org_kde_plasma_window_management'.
- Model settings: GroupDisabled gives one button per window; SortDisabled keeps creation order.
- Layer-shell surfaces are skipTaskbar, skipSwitcher and skipPager in KWin, so the panel and launcher never appear in the list.
- Click, Return or Space on a task: requestActivate if inactive, requestToggleMinimized if active.
- Startup placeholders appear briefly, because plasmashell holds activation_feedback.

DETECTING A MISSING GRANT
In option A no QML-visible signal separates 'no grant' from 'no windows'. Instead:
- the empty list is announced as 'No open windows';
- the serial report checks the grant precondition;
- the session test fails with reason 'window list not granted' when the KWin oracle lists normal windows while the shell logs tasks=0.

ACTIVATION
- In 6.7.5, KWin grants privileged xdg-activation tokens to clients whose requestedInterfaces include window management (plasmashell). Launched apps and requestActivate therefore focus without a fresh input serial.
- A newly mapped surface that wants input is activated under the default focus-stealing level Low (workspace.cpp).
- A 4-edge-anchored Top or Overlay layer surface may be activated on its output (activation.cpp).
- KWIN_WAYLAND_NO_PERMISSION_CHECKS would skip the requestedInterfaces bookkeeping and change this path. That is one more reason it is banned everywhere.

FOCUS SURFACES
Panel (PanelView, unchanged Plasma code):
- layer-shell scope 'dock', LayerTop, KeyboardInteractivityNone.
- Meta+Alt+P ('cycle-panels') sets AcceptingInputStatus. KWin activates the panel when its acceptsFocus changes (handleAcceptsFocusChanged), and PanelView calls forceActiveFocus(Qt.TabFocusReason) on the first tab-focusable item, our 'Applications' button.
- Escape is not consumed by Taskbar. PanelView handles it and restores the previous window.
- The exclusive zone equals the thickness, so maximised windows stay above the panel.
- floating=false is set explicitly, because PanelView's default floats on Wayland.

Launcher (QML Window plus LayerShell attached type):
- LayerOverlay, all four anchors, exclusionZone -1, activateOnShow true, scope 'staros-launcher'.
- keyboardInteractivity is Exclusive. KWin 6.7.5 stores only a bool, so it behaves like OnDemand.
- KWin recreates the layer window on every map, so each opening is a new surface and is activated.
- On show: search.text='' and focus goes to the search field. When the launcher deactivates (Alt+Tab, click) it hides. Escape or a launch hides it, and KWin re-activates the previous window from its focus chain (S6 asserts this).

KEYBOARD MAP (built into Plasma; nothing to register)
- Meta (modifier-only) and Alt+F1: ShellCorona 'activate application launcher'. It asks KWin for activeOutputName, then emits activated() on the panel containment providing org.kde.plasma.launchermenu, which toggles the launcher.
- Meta+Alt+P: focus the taskbar. Left and Right move between Applications, tasks and Leave; Return or Space activates.
- In the launcher: type to search; Down or Tab to the grid; arrows move; Up on the first row returns to search; Return, Enter or Space launches; Escape closes.
- Ctrl+Alt+Del opens the logout prompt (kded session-shortcuts). Meta+Alt+S toggles Orca (kaccess). Meta+L does nothing (kiosk).
- Alt+Tab never reaches layer surfaces (skipSwitcher), which is why the two shortcuts are the documented entry points.
- Meta+1..9 is not supported: ShellCorona sends activateTaskAtIndex only to panel applets that provide org.kde.plasma.multitasking.

INDEPENDENT VERIFICATION
The session test passes C2 and C3 only when three views agree:
- KWin's: a test-time KWin script oracle. It reports activeWindow.resourceClass and windowList() over callDBus to a test listener, because kwin_scripting logs at warning level by default.
- The shell's: the STAROS-SHELL tasks= and launcher= lines, and the 'Active window' descriptions over AT-SPI.
- The user's: AT-SPI focus events and focus-ring pixels.

CONTINGENCIES
- If launched apps do not get focus: keep the launcher mapped until the new task appears in TasksModel (or 3 s), then hide.
- If Meta+Alt+P focus fails: an 'Open windows' row inside the launcher.

## Accessibility

SEMANTICS
These are Qt Quick Accessible attached properties, exposed by QtGui's AT-SPI bridge on the wayland platform. AT-SPI role names follow Qt's map.
- Taskbar: FocusScope, ToolBar ('tool bar'), name 'Taskbar'.
- 'Applications': T.AbstractButton ('push button'), description 'Open the application launcher'.
- 'Open windows': ListView, List ('list'), description 'No open windows' when empty.
- TaskButton: Button, name = window title or else AppName, description 'Active window' or 'Window'.
- 'Leave': Button, description 'Log out, restart or shut down'.
- Launcher window title: 'Star OS applications' (the frame name).
- Launcher root: Pane ('panel'), name 'Application launcher'.
- Search: T.TextField, EditableText ('text'), name 'Search applications'.
- GridView: List, name 'Applications'. Item views are invisible to AT-SPI unless annotated.
- LauncherTile: Button, name AppName, description GenericName. The monogram and label Text items set Accessible.ignored, so nothing is read twice.
The module uses no Kirigami or QQC2 style, so roles and focus behaviour are identical in unit tests and in the session.

FOCUS IS REAL FOCUS
Qt reports focus to AT-SPI only through activeFocus, and that exists only while KWin has given the surface keyboard focus. That is why:
- the launcher is an activated Overlay surface;
- the panel relies on PanelView's None-to-OnDemand switch.
An empty window list is never focusable (activeFocusOnTab: count > 0), so focus never lands on an invisible target.

VISIBLE FOCUS
- FocusFrame is 3 logical px of #ffb400 with radius 0, bound to activeFocus.
- It is not bound to visualFocus: visualFocus is true only for Tab, Backtab and Shortcut reasons, while item views focus their current item with setFocus(true).
- Computed WCAG contrast:
  - ring: 9.22:1 on the taskbar, 8.04 on task buttons, 7.52 on tiles, 10.38 on the launcher backdrop, 8.71 on the search field, 6.92 on the desktop;
  - text #f2f5f8: 15.03 on the taskbar, 12.25 on tiles, 14.19 on the search field;
  - placeholder: 7.52 on the search field;
  - search border #7d8fa3: 5.58 on the backdrop and 4.68 on the field. This fixes the field's 1.19:1 boundary; WCAG 1.4.11 asks for 3:1.
- tst_theme asserts text at least 4.5:1 and ring and border at least 3:1.

SCREEN READER PATH
Packages:
- added: orca 51.1, speech-dispatcher, python-gobject (normally via orca), pipewire, pipewire-pulse (not pulled in by default; speech-dispatcher's pulse output needs it) and wireplumber;
- already present: espeak-ng, at-spi2-core and gsettings-desktop-schemas.
Start paths:
- Meta+Alt+S: kaccess runs 'gsettings set org.gnome.desktop.a11y.applications screen-reader-enabled true' and starts 'orca --replace' only if gsettings exits 0.
- The archiso 'speech' boot entries: startstaros writes kaccessrc [ScreenReader] Enabled=true once per boot, and kaccess starts Orca at login.
Orca uses KWin's KeyboardMonitor on Wayland. The image never sets QT_LINUX_ACCESSIBILITY_ALWAYS_ON, because Qt's bridge follows org.a11y.Status at runtime. releng's speech entry also runs console espeakup over ALSA; the owner checks for contention with PipeWire.

EVIDENCE
CI, QEMU, on the real session:
- The harness sets org.a11y.Status IsEnabled=true as liveuser, exactly as Orca does.
- An AT-SPI walker checks roles, names, descriptions and window-coordinate extents.
- A focus listener (object:state-changed:focused) asserts the focused role and name after every real QMP key.
- Meta+Alt+S must start an orca process.
- Orca 51.1 is then restarted with --debug --debug-file. Because it logs SPEECH OUTPUT: '<text>' at INFO even with no speech server, the log proves what would be spoken for each focused tile and button. This starts informational and is promoted after three green runs.
Unit: roles, names, focus order and ring visibility (grabImage pixels). The offscreen platform has no AT-SPI bridge, so AT-SPI itself is checked only in the session.
Owner, VMware: audible speech through both start paths.

## Scaling and motion

SCALING
- All sizes are logical and derived from Theme.gridUnit, which is based on the application font. Larger fonts therefore grow the taskbar, tiles and touch targets.
- views/Panel.qml sets panel.thickness = Theme.taskbarHeight, so the PanelView thickness and the QML agree. PanelView clamps it to minThickness.
- The launcher fills the output.
- Task buttons shrink to fit, labels elide, and the full name stays in Accessible.name.
- The image sets no QT_SCALE_FACTOR, no QT_SCREEN_SCALE_FACTORS and no rounding policy. Qt keeps PassThrough and uses wp_fractional_scale_v1 with viewporter against KWin.
- The layer surfaces follow scale changes without a restart.

Three layers:
1) Unit (shell-checks job):
   - run-qml-tests.sh runs qmltestrunner with QT_QPA_PLATFORM=offscreen:configfile=tests/shell/screen-1920x1080.json, QT_QUICK_BACKEND=software and QT_SCALE_FACTOR 1, 1.5 and 2. That gives logical screens of 1920x1080, 1280x720 and 960x540.
   - tst_scaling first logs and asserts Screen.width, Screen.height and devicePixelRatio, so a misread configuration fails loudly. It also logs Theme.gridUnit.
   - With six fixture apps, some with long names, it asserts:
     - the grid has at least 1 column;
     - all tiles are inside the launcher and pairwise non-overlapping;
     - tiles are at least Theme.minTarget;
     - names of 20 characters or fewer are not truncated;
     - the search field is inside the window;
     - the taskbar fits one row with Applications, at least 3 task buttons and Leave at 960 px;
     - grabImage of the focused tile contains ring pixels at least focusRingWidth thick.
2) Session (ci-qemu, scenario S11):
   - KWin runs on bochs-drm at 1920x1080 (or 1280x800 if iteration 0 shows the VGA xres and yres properties are missing).
   - As liveuser, the harness runs kscreen-doctor -j to find the output name, then output.<name>.scale.1.5, .2 and .1.
   - Gating: an AT-SPI walk of the open launcher shows every tile inside the launcher window and no two tiles overlapping, and the taskbar buttons inside the panel window.
   - Informational until stable: the screendump band height equals round(taskbarHeight * s) plus or minus 1 physical rows, and the ring thickness equals round(3 * s) plus or minus 1. taskbarHeight comes from the STAROS-SHELL ready line or the panel height in the serial report.
   - A PNG per scale is uploaded for the owner.
3) Owner (VMware): the same kscreen-doctor scales. The owner judges clipping, blur and overlap from screenshots recorded in the manual test log.

MOTION
- M0.2 has no animations: Theme.animationDuration is 0, highlightMoveDuration is 0, and there are no Behaviors. Reduced motion is satisfied trivially, and screendumps are deterministic.
- KWin turns its own animation effects off on software rendering, so QEMU and VMware with 3D off behave alike. Idle and smoothness figures carry the renderer string and are not hardware claims.
- Phase 1: bind durations to Qt's motionPreference or kdeglobals AnimationDurationFactor.

## Build pipeline changes

1) scripts/build-iso.sh. It still runs as root in the pinned Arch container. assemble_profile becomes:
   a. Copy releng (unchanged).
   b. remove_releng_paths: delete each path in distro/archiso/staros/releng-remove.txt; die if one does not exist.
   c. Copy the overlay (unchanged; cp -a keeps symlinks).
   d. append_packages: append lines of packages.x86_64.append that are not in releng's list, and log those that already were.
   e. install_shell_files:
      - shell/qml/StarOS → airootfs/usr/lib/qt6/qml/StarOS
      - shell/plasma/shells/* → airootfs/usr/share/plasma/shells/
      - shell/plasma/plasmoids/* → airootfs/usr/share/plasma/plasmoids/
      *.license sidecars are skipped. All targets are new paths, so pacstrap cannot hit a file conflict.
   f. Profiledef append, repository pinning and boot-entry renaming (unchanged).
   After mkarchiso:
   - write_records also records iso_bytes and staros_shell_sha256 (a hash of the installed shell tree).
   - scripts/ci/check-image-policy.sh build/work/x86_64/airootfs prints POLICY lines, writes out/image-policy.txt and fails the build on any FAIL.

2) check-image-policy.sh asserts on the built airootfs:
   - No name from forbidden-env.txt appears in etc/, usr/local/, home/, usr/lib/qt6/qml/StarOS, the org.staros Plasma packages, or staros.desktop.
   - No plasmashellrc with [Shell] ShellPackage exists in etc/xdg or home/liveuser/.config.
   - root is locked.
   - liveuser has UID and GID 1000, /bin/bash (listed in etc/shells), and no wheel membership. System groups (e.g. wheel) exist, which proves the sysusers hook ran.
   - The sudoers file is 0440 root:root and passes visudo -cf.
   - sshd is masked and has no wants link; there is no getty autologin drop-in.
   - display-manager.service points to staros-live-session.service, and default.target resolves to graphical.target.
   - staros.desktop passes desktop-file-validate.
   - The Star OS shell files exist, and no 'org.kde.plasma.private' import appears in them.
   - Every overlay path is either unowned or a backup file of its owning package (pacman --root ... -Qo / -Qii).
   - Informational lines: whether kwriteconfig6, kscreen-doctor and gsettings are present, and qemu-guest-agent's udev rule.
   The build job's host packages gain sudo and desktop-file-utils.

3) profiledef.append.sh: file_permissions for /etc/gshadow, /etc/sudoers.d, /etc/sudoers.d/10-staros-live, startstaros and staros-session-report.

4) Package manifest (T0-05): the first M0.2 build differs on purpose. check-package-manifest.sh prints the full new list, and the implementer commits it to distro/baseline/packages.x86_64.txt in the same PR, as building.md already describes.

5) .github/workflows/iso.yml. Actions stay pinned to the existing SHAs; permissions stay contents: read; no secrets.
   - lint (ubuntu-24.04):
     - shellcheck also covers startstaros, check-image-policy.sh, check-forbidden-env.sh, run-qml-tests.sh and the tests/probe scripts;
     - python3 -m unittest for tests/iso and tests/session;
     - py_compile of staros-session-report and the guest helpers;
     - check-forbidden-env.sh (a repository grep excluding docs/ and the list file);
     - apt-get install desktop-file-utils, then desktop-file-validate on every .desktop file.
   - shell-checks (new; archlinux container; needs lint; parallel to build):
     - prepare-arch-build-host.sh qt6-declarative kpackage plasma-workspace libplasma kitemmodels layer-shell-qt noto-fonts;
     - tests/shell/check_shell_sources.py, then run-qml-tests.sh;
     - uploads JUnit XML and grabImage PNGs.
   - session-probe (new; archlinux container --privileged; needs lint; continue-on-error until promoted; timeout-minutes 15):
     - prepare host with kwin plasma-workspace plasma-desktop kactivitymanagerd layer-shell-qt kitemmodels konsole systemsettings at-spi2-core python-gobject;
     - copies the shell trees into /usr/share and /usr/lib in the container, creates the user 'probe', then runs tests/probe/run-session-probe.sh.
   - build: needs lint, as now; its log adds POLICY lines.
   - package-manifest: unchanged.
   - boot-test (uefi, bios):
     - the T0-09 self-test stays;
     - the boot step adds --session --profile graphical --session-timeout 420;
     - uploads session-<fw>.png and the result JSON.
   - idle (new; uefi; matrix run [1, 2, 3]; fail-fast false): boot_test.py --session --profile graphical --wait-idle. It has no guest-agent port and no input, and parses STAROS-IDLE-REPORT.
   - idle-summary (new; if: always()): idle_summary.py writes medians, minimum and maximum to the log and $GITHUB_STEP_SUMMARY, labelled 'CI QEMU/KVM, llvmpipe, 4 vCPU, 4 GiB, not a performance claim'.
   - session-test (new; uefi; needs build; timeout-minutes 45): python3 tests/session/session_test.py. With if: always() it uploads the serial log, journal export (as root via QGA), AT-SPI JSON, oracle JSONL, orca-debug.out, PNGs and the result JSON.

6) Iteration 0: inspect-kde.sh and inspect-kde.yml get the probes listed in iterations, plus a second job on ubuntu-24.04 that prints the QEMU version and the VGA and virtserialport device properties.

CI COST
- Two container jobs (about 5 and 8 minutes) run in parallel with the build.
- After the build, in parallel: boot tests about 8 minutes, idle about 10 minutes each, session-test about 20 minutes.
- The critical path grows by about 20 minutes.
- The ISO grows by roughly 1 GB (estimate; iteration 0 prints the installed-size sum, build-info records the real size). The build logs df -h, because runner disk is a risk.

## Live user and security

ACCOUNTS
Overlay files are copied after releng, so they replace releng's passwd and shadow. filesystem lists passwd, group, shadow and gshadow as backup files, so pacstrap keeps ours.
- etc/passwd: root:x:0:0:root:/root:/usr/bin/zsh (as releng) and liveuser:x:1000:1000:Star OS live user:/home/liveuser:/bin/bash
- etc/shadow (0400): root:!*:14871:::::: (locked) and liveuser::14871:::::: (empty password, live medium only)
- etc/group: root:x:0:root and liveuser:x:1000:
- etc/gshadow (0400): root:::root and liveuser:!::
- This matches Arch's filesystem model: root only, with system groups added by the systemd-sysusers pacman hook. The policy check proves the hook ran.
- liveuser has no supplementary groups:
  - not wheel, so the polkit admin rule does not apply;
  - no device groups, because logind uaccess grants access to the active session;
  - never 'empower'.
- mkarchiso v91 creates /home/liveuser with mode 0750, copies skel with --update=none and chowns the home to 1000:1000.

PRIVILEGE
- etc/sudoers.d/10-staros-live contains an SPDX line, the comment 'Live medium only; the Phase 2 installer must not copy this file.' and 'liveuser ALL=(ALL:ALL) NOPASSWD: ALL'. Its mode is 0440, the directory is 0750, and visudo -cf runs in the policy check.
- With root locked, this is the owner's only elevation path; the owner needs it for diagnostics. A narrower alternative is to allow only journalctl and staros-session-report.
- No polkit rule is added. Admin-only polkit actions fail on the live medium, which is acceptable for M0.2. logind lets the active session power off and reboot.

LOGIN AND REMOTE ACCESS
- releng's root autologin drop-in is removed via releng-remove.txt (the build fails if releng drifts), so nothing autologins root. /root/.zlogin's script= automation no longer runs; this is documented.
- The live session unit logs in liveuser with PAMName=login and no password prompt. Its OnFailure getty prompt has no autologin.
- sshd's wants link is removed and the unit is masked. releng's PermitRootLogin and PasswordAuthentication drop-in stays inert.
- Locking is disabled for the live user:
  - kdeglobals [KDE Action Restrictions] action/lock_screen=false; kscreenlocker's ksldapp and interface check KAuthorized 'lock_screen';
  - Autolock=false and LockOnResume=false.
  An empty-password user can therefore never be locked out.

NO CI-ONLY BYPASSES
- The image never sets KWIN_WAYLAND_NO_PERMISSION_CHECKS, KWIN_SCREENSHOT_NO_PERMISSION_CHECKS, QT_LINUX_ACCESSIBILITY_ALWAYS_ON or KWIN_COMPOSE.
- Two checks read one list file: a repository-wide lint grep (excluding docs/ and the list) and the image policy grep. The container probe and every CI step that runs the shell also omit these variables.
- The taskbar gets the window list only through plasmashell's packaged grant. No new desktop file with X-KDE-Wayland-Interfaces is added.
- The session test adds input through QMP (a virtual keyboard and tablet) and observes through the guest agent. Its helpers live in /run/staros-test (tmpfs) and disappear on reboot. The debug Orca writes its log with mode 0600.

DIAGNOSTICS
staros-session-report is a prototype-only, read-only root service, like M0.1's staros-boot-check:
- It reads /proc, loginctl, systemctl, the journal, and the liveuser's session bus through runuser for read-only queries plus evaluateScript printing the layout.
- It writes only to the journal and ttyS0.
- Hardening: NoNewPrivileges=yes, PrivateNetwork=yes, ProtectSystem=strict, ProtectHome=read-only. It is added in the same iteration only if CI shows the report is still produced.
- Phase 1 removes it or makes it opt-in.

GUEST AGENT
- releng already installs qemu-guest-agent 11.1.2. Arch's package (2023 packaging) adds a udev rule that starts qemu-guest-agent.service when a virtio port named org.qemu.guest_agent.0 appears. Iteration 0 re-checks this at the 2026-10-15 snapshot.
- If the rule is present, the shipped image does not change. CI only attaches the port. The threat model records that a hypervisor offering the port gets root command execution, the same class as releng's already-enabled vmtoolsd guest operations; the hypervisor already controls the VM.
- If the rule is absent, an identical overlay rule needs owner approval. Otherwise checks 2–5 lose their QEMU evidence and become owner-only. Checks 1 and 6 do not depend on it.

DOCUMENTATION
- The threat-model accepted risk 'root console autologin' becomes: 'live user with empty password, autologin and NOPASSWD sudo on the live medium; root locked; sshd masked'. The guest-agent and diagnostics notes are added. Upstream observation: KWin 6.7.5's EIS RemoteDesktop D-Bus method has no caller check (threat #3, Phase 3+).
- Installer requirement (Phase 2): never copy sudoers.d/10-staros-live, staros-live-session.service, the display-manager link, the sshd mask, the passwd/shadow/group overrides, /home/liveuser or the diagnostics units.

## Files

- shell/qml/StarOS/Shell/qmldir: Module StarOS.Shell: singleton Theme plus FocusFrame, ShellButton, TaskButton, Taskbar, LauncherTile, Launcher (installed to /usr/lib/qt6/qml/StarOS/Shell)
- shell/qml/StarOS/Shell/Theme.qml: Font-derived gridUnit sizes, reserved colours used by the CI screen analysis, focusRingWidth 3, animationDuration 0
- shell/qml/StarOS/Shell/FocusFrame.qml: 3 px amber, radius-0 focus ring bound to activeFocus
- shell/qml/StarOS/Shell/ShellButton.qml: Templates button used for 'Applications' and 'Leave' (accessible name and description, Return/Enter/Space)
- shell/qml/StarOS/Shell/TaskButton.qml: One window: title or app name, 'Active window' description, active indicator, elides
- shell/qml/StarOS/Shell/Taskbar.qml: ToolBar FocusScope: Applications, Open windows list, Leave; keyboard navigation; signals launcherRequested, activateRequested(row), leaveRequested
- shell/qml/StarOS/Shell/LauncherTile.qml: Launcher entry button (monogram plus label), Accessible name and description
- shell/qml/StarOS/Shell/Launcher.qml: Full-screen launcher content: search field, Applications grid, empty state; catalogue interface (model, count, filter, launch(row)); closeRequested
- shell/plasma/shells/org.staros.shell/metadata.json (+ metadata.json.license): Plasma/Shell metadata, X-Plasma-APIVersion 2, explicit fallback org.kde.plasma.desktop
- shell/plasma/shells/org.staros.shell/contents/defaults: Desktop org.staros.desktop, Panel org.staros.taskbar, no toolboxes, no containment actions
- shell/plasma/shells/org.staros.shell/contents/layout.js: First-run layout: org.kde.color wallpaper in Theme.desktop, bottom non-floating fill panel, locked
- shell/plasma/shells/org.staros.shell/contents/views/Desktop.qml: Own minimal desktop view (parents and fills the containment)
- shell/plasma/shells/org.staros.shell/contents/views/Panel.qml: Own minimal panel view: NoBackground hint, panel.thickness = Theme.taskbarHeight
- shell/plasma/plasmoids/org.staros.taskbar/metadata.json (+ .license): Pure-QML Panel containment, API minimum 6.0, provides org.kde.plasma.launchermenu, NoDisplay
- shell/plasma/plasmoids/org.staros.taskbar/contents/ui/main.qml: Plasma adapter: windows TasksModel, AppCatalogue, Taskbar wiring, LogoutPrompt call, Plasmoid.onActivated, STAROS-SHELL log lines
- shell/plasma/plasmoids/org.staros.taskbar/contents/ui/AppCatalogue.qml: Curated public-API catalogue: TasksModel launchers, launcher-only proxy, search proxy, launch(row)
- shell/plasma/plasmoids/org.staros.taskbar/contents/ui/LauncherWindow.qml: Layer-shell Overlay Window hosting Launcher; hides on deactivation; launcher=open/closed log lines
- shell/plasma/plasmoids/org.staros.desktop/metadata.json (+ .license), contents/ui/main.qml: Pure-QML Desktop containment that only shows the wallpaper
- tests/shell/tst_taskbar.qml, tst_launcher.qml, tst_scaling.qml, tst_theme.qml, FakeCatalogue.qml: Qt Quick Test: keyboard order, signals, search, empty states, focus-ring pixels, layout invariants at 3 scales, WCAG contrast; ListModel fixtures with libtaskmanager role names
- tests/shell/screen-1920x1080.json, tests/shell/run-qml-tests.sh: Offscreen screen config; runner: qmllint (fatal for StarOS.Shell), qmltestrunner x3 scales with JUnit output, kpackagetool6 install into a scratch HOME
- tests/shell/check_shell_sources.py: Metadata JSON and id/directory match, SPDX header or .license sidecar, gate on 'org.kde.plasma.private' anywhere under shell/
- tests/probe/run-session-probe.sh, tests/probe/probe-session.sh: Headless container probe: unprivileged kwin_wayland --virtual (no bypass) + plasmashell with the Star OS packages; prints PROBE lines (shell, layout, KWin grant line, tasks, AT-SPI, launcher focus)
- tests/session/session_test.py: QEMU/KVM harness for the CI ISO: QMP keys/mouse/screendump, QGA, scenario S0-S12, EVIDENCE lines, result JSON, step summary
- tests/session/qga.py, tests/session/screen.py, tests/session/idle_summary.py: Guest-agent client; PPM parsing, band and ring detection, stdlib PNG writer; idle medians from serial STAROS-IDLE-REPORT lines
- tests/session/guest/runas.py, atspi_probe.py, oracle_listener.py, kwin_oracle.js: Test-time helpers pushed to /run/staros-test (tmpfs), never shipped: drop to liveuser with plasmashell's environment; AT-SPI walk/listen/enable; D-Bus listener for the KWin oracle; KWin script reporting via callDBus. atspi_probe.py is shared with the container probe
- tests/session/test_screen.py, test_qga.py, test_idle_summary.py, test_session_report.py: Harness self-tests in the lint job (synthetic images including wrong ones, QGA framing, aggregation, session-report parsers)
- tests/iso/boot_test.py (+ test_boot_test.py): --session (wait for STAROS-SESSION-OK/FAIL, require logind_type=wayland and shell=org.staros.shell), --wait-idle, --profile graphical (4 vCPU, 4096 MiB, VGA resolution), PNG screendump and band check; default M0.1 command unchanged
- distro/archiso/staros/packages.x86_64.append: Explicit M0.2 packages appended to releng's list
- distro/archiso/staros/releng-remove.txt: releng paths removed from the assembled profile (root autologin drop-in, sshd wants link); build fails if one is missing
- distro/archiso/staros/profiledef.append.sh: file_permissions: /etc/gshadow 0:0:400, /etc/sudoers.d 0:0:750, sudoers file 0:0:440, startstaros and staros-session-report 0:0:755
- distro/archiso/staros/airootfs/etc/passwd, shadow, group, gshadow: root (locked) plus liveuser 1000:1000 with /bin/bash and an empty password; group/gshadow root and liveuser only, system groups from sysusers (Arch filesystem model)
- distro/archiso/staros/airootfs/etc/sudoers.d/10-staros-live: liveuser ALL=(ALL:ALL) NOPASSWD: ALL, live medium only
- distro/archiso/staros/airootfs/etc/systemd/system/staros-live-session.service: Display-manager-less autologin into the Star OS session on tty1 (wayland logind session)
- distro/archiso/staros/airootfs/etc/systemd/system/display-manager.service (symlink): Points to /etc/systemd/system/staros-live-session.service
- distro/archiso/staros/airootfs/etc/systemd/system/sshd.service (symlink to /dev/null): Masks sshd on the desktop live ISO
- distro/archiso/staros/airootfs/etc/systemd/system/staros-session-report.service + graphical.target.wants/staros-session-report.service: Read-only serial and journal session report (checks 1 and 6), enabled like M0.1's boot check
- distro/archiso/staros/airootfs/usr/local/libexec/staros-session-report: python3 -I, stdlib only, root, read-only: session facts, OK/FAIL, idle PSS/CPU JSON, STABLE
- distro/archiso/staros/airootfs/usr/local/bin/startstaros: Exports PLASMA_DEFAULT_SHELL, applies the accessibility=on hook once per boot, execs startplasma-wayland
- distro/archiso/staros/airootfs/usr/share/wayland-sessions/staros.desktop: Session entry for the Phase 1 display manager (Exec via plasma-dbus-run-session-if-needed, DesktopNames=KDE); validated, unused by the live unit
- distro/archiso/staros/airootfs/home/liveuser/.config/ksplashrc, kscreenlockerrc, kdeglobals, powerdevilrc, kwalletrc, baloofilerc: Live-only defaults: no splash, no locking (kiosk), no dimming or suspend, no wallet, no indexing
- distro/archiso/staros/airootfs/etc/staros-release, etc/motd: Say 'prototype M0.2'
- distro/archiso/staros/airootfs/etc/udev/rules.d/99-staros-qemu-guest-agent.rules (conditional): Only if iteration 0 shows Arch no longer ships 99-qemu-guest-agent.rules, and only with owner approval
- scripts/build-iso.sh: remove_releng_paths, append_packages, install_shell_files (skip *.license), image policy check after mkarchiso, iso_bytes and shell tree hash in build-info
- scripts/ci/check-image-policy.sh: POLICY lines on build/work/x86_64/airootfs; fails the build on any violation
- scripts/ci/forbidden-env.txt, scripts/ci/check-forbidden-env.sh: Single list of banned variables (KWin permission bypasses, QT_LINUX_ACCESSIBILITY_ALWAYS_ON, KWIN_COMPOSE); repository grep (lint) and image grep (policy) both read it
- scripts/ci/check-package-manifest.sh: On mismatch also print the full new list so it can be copied from the log
- scripts/ci/inspect-kde.sh, .github/workflows/inspect-kde.yml: Iteration 0 probes: package closure and sizes, qemu-guest-agent files, binary owners, desktop ids, shells/PAM/sysusers, KWin virtual smoke without spectacle, runner QEMU device properties
- .github/workflows/iso.yml: New jobs shell-checks, session-probe, idle (x3), idle-summary, session-test; boot-test gains --session; lint gains new scripts and checks
- docs/decisions/0008-m02-shell-hosting-and-live-session.md, docs/decisions/README.md: ADR-0008 (Proposed) and index row
- docs/decisions/0004-compositor-and-shell-foundation.md: M0.2 results and the A/B decision, after the owner run
- docs/development/test-plan.md, phase-0-plan.md, building.md: T0-20..T0-25 methods, EVIDENCE line meanings, owner VMware procedure, new jobs and build steps
- docs/security/threat-model.md: Accepted risk changes from root console autologin to the live-user posture; guest-agent and diagnostics notes; installer must not copy live files

## Checks and evidence

- [unit, auto, in-logs] C1 (T0-20) StarOS.Shell components load and render at 100/150/200%: shell-checks: qmllint clean for StarOS.Shell; qmltestrunner offscreen (software backend) instantiates Taskbar and Launcher in every test at QT_SCALE_FACTOR 1, 1.5 and 2 and prints Totals per scale; JUnit uploaded
- [ci-container, auto, in-logs] C1 Plasma packages, sources and session file are valid; no private import; no bypass variable: check_shell_sources.py (JSON, ids, SPDX or .license, 'org.kde.plasma.private' gate), kpackagetool6 --install of the three packages into a scratch HOME, desktop-file-validate, check-forbidden-env.sh
- [ci-container, auto, in-logs] C1/C2/C4 fast probe: plasmashell loads org.staros.shell under real KWin without bypass; window list fills; AT-SPI tree; launcher activation and focus: session-probe job:
- unprivileged dbus-run-session kwin_wayland --virtual --no-lockscreen --width 1280 --height 800 --exit-with-session probe-session.sh, with QT_LOGGING_RULES=kwin_core.debug=true and QT_QUICK_BACKEND=software for clients (no permission variables);
- asserts: shell property; evaluateScript layout; KWin 'authorized /usr/bin/plasmashell org_kde_plasma_window_management'; 'STAROS-SHELL tasks=1' after starting konsole; AT-SPI Taskbar toolbar with a task button named after Konsole; org.kde.PlasmaShell.activateLauncherMenu gives launcher=open and an AT-SPI focused 'text: Search applications';
- informational until promoted
- [ci-qemu, auto, in-logs] C1 (T0-20) KWin and plasmashell with the Star OS shell start on the booted ISO (UEFI and BIOS): staros-session-report on ttyS0 prints STAROS-SESSION-CHECK with logind_type=wayland, shell=org.staros.shell, the layout JSON (bottom non-floating org.staros.taskbar panel, org.staros.desktop with org.kde.color), renderer, grant=ok, then STAROS-SESSION-OK; boot_test.py --session asserts these; QMP screendump PNG uploaded; taskbar-band and desktop-colour line (informational until promoted)
- [ci-qemu, auto, in-logs] C1 the session stays up (serial): STAROS-SESSION-STABLE at ready+330 s: same plasmashell and kwin PIDs, NRestarts 0 for plasma-plasmashell and staros-live-session (idle runs and boot tests)
- [ci-qemu, auto, in-logs] C1 the session stays up through the whole scenario: session-test S12: unchanged PIDs, NRestarts 0, coredumpctl empty for kwin and plasmashell, no 'TypeError|ReferenceError|is not a type|Cannot assign|Error loading' journal lines mentioning org.staros or StarOS (known benign lines such as the empty-toolbox warning are whitelisted and printed)
- [vmware] C1 owner: renders and stays up in VMware with 3D on and off for 30 minutes: Owner boots the CI ISO (4 vCPU, 4 GB), confirms taskbar, desktop colour and cursor, waits 30 min, then runs sudo journalctl -b -u staros-session-report -o cat; records VMware and hardware versions
- [unit, auto, in-logs] C2 Taskbar lists windows and emits activation; Launcher filters and launches: tst_taskbar and tst_launcher with ListModel fixtures (AppName, display, IsActive, GenericName) and FakeCatalogue: delegate counts, click/Return emit activateRequested(row), search 'kon' leaves 1 tile, Return in search launches row 0, launch true closes
- [ci-qemu, auto, in-logs] C2 (T0-21 path) launch, list and switch windows on the booted ISO by keyboard: session-test S5-S8:
- launch Konsole and System Settings from the launcher with QMP keys;
- the KWin oracle reports both windows and the active one;
- the shell logs tasks=2;
- the AT-SPI walk of 'Open windows' shows two buttons named after them;
- Meta+Alt+P, Right and Return switch, and the oracle's active window equals the chosen app while the 'Active window' description agrees;
- a 'window list not granted' failure is reported if the oracle lists windows but tasks=0
- [ci-qemu, auto, in-logs] C2 mouse switching on the booted ISO: session-test S9: usb-tablet click at the centre of the other task button (AT-SPI extents within the panel window placed at the output bottom); the oracle's active window changes; informational until promoted
- [vmware] C2 owner: T0-21 with the mouse in VMware: Open Konsole and System Settings from the launcher, see both in the taskbar, switch by clicking, minimise and restore by clicking the active button
- [unit, auto, in-logs] C3 keyboard traversal and visible focus in the components: tst_taskbar and tst_launcher with when: windowShown: Tab, arrow, Return, Escape sequences assert the activeFocus order, edge behaviour, the empty list never focused, search to grid and back, printable keys returning to search; grabImage of the focused item contains ring pixels at each scale
- [ci-qemu, auto, in-logs] C3 (T0-22 path) keyboard-only operation through KWin on the booted ISO: session-test S5-S8 use only QMP send-key:
- every key gives an AT-SPI focus event with the expected role and a non-empty name within 5 s: Meta gives 'text Search applications' (one recorded retry with Alt+F1); Down gives 'push button Konsole'; Meta+Alt+P gives 'push button Applications';
- Escape returns KWin's active window to the previous app (oracle);
- focus-ring pixel bounding box versus AT-SPI extents x scale within 3 px (informational until promoted)
- [vmware] C3 owner: T0-22 without a mouse in VMware: Repeat T0-21 with Meta, typing, arrows, Return, Escape, Meta+Alt+P, Ctrl+Alt+Del; confirm the amber ring is visible at every step; note any lost focus
- [ci-qemu, auto, in-logs] C4 launcher entries and taskbar items are exposed to AT-SPI with names and roles: atspi_probe walk of plasmashell after enabling org.a11y.Status: frame 'Star OS applications', pane 'Application launcher', text 'Search applications', list 'Applications' with at least 2 push-button children each named with the app name and described with GenericName; toolbar 'Taskbar' with 'Applications', 'Open windows' and 'Leave'; JSON lines in the log
- [ci-qemu, auto, in-logs] C4 (T0-24 path) Orca reads launcher entries: session-test S10:
- Meta+Alt+S makes an orca process appear (kaccess path);
- the harness restarts Orca 51.1 as liveuser with --replace --debug --debug-file;
- it sends Meta, Down, Right, Escape and prints every SPEECH OUTPUT line;
- passes when each focused tile name appears after its key press;
- informational until three consecutive green runs, then gating via a reviewed commit
- [vmware] C4 owner: audible speech in VMware: spd-say test must be audible; Meta+Alt+S; open the launcher, arrow through entries and the taskbar; record spoken phrases; repeat once from a 'speech' boot entry and note any espeakup/PipeWire conflict
- [unit, auto, in-logs] C5 layout invariants at 100/150/200%: tst_scaling at QT_SCALE_FACTOR 1, 1.5, 2 on a 1920x1080 offscreen screen: logs gridUnit, asserts logical size and dpr, tiles inside and non-overlapping, minimum target size, no truncation for names up to 20 characters, taskbar fits at 960 px, focus ring present
- [ci-qemu, auto, in-logs] C5 (T0-23 path) real fractional scaling under KWin: session-test S11: kscreen-doctor scale 1.5, 2, 1 as liveuser; AT-SPI: all tiles inside the launcher window and non-overlapping, taskbar buttons inside the panel (gating); band height round(taskbarHeight*s)+-1 and ring round(3*s)+-1 from screendumps (informational until promoted); PNG per scale
- [vmware] C5 owner: visual layout judgement at 100/150/200% in VMware: Set each scale with kscreen-doctor, screenshot the taskbar and the open launcher with focus on a tile, confirm nothing is clipped, blurry or overlapping
- [ci-qemu, auto, in-logs] C6 (T0-25) idle RAM and CPU in CI: idle job, three UEFI boots without guest agent or input:
- staros-session-report samples 60 s starting 240 s after ready;
- reports per-process PSS (smaps_rollup), session_pss_mib, plasmashell_pss_mib, kwin_pss_mib, MemTotal minus MemAvailable, and session CPU percent of one CPU from utime+stime deltas, plus nproc, virt, renderer and package versions;
- idle-summary prints median, min and max; no threshold
- [vmware] C6 owner: idle RAM and CPU in VMware: Three cold boots each with 3D on and off: wait for the taskbar, do not touch the VM for 6 minutes, then open Konsole and run sudo journalctl -b -u staros-session-report -o cat; paste the STAROS-IDLE-REPORT lines into the manual test log
- [ci-container, auto, in-logs] Image policy: no CI-only bypass, least-privilege live user, live-only files, unowned overlay paths: check-image-policy.sh on the built airootfs; POLICY lines in the build log; build fails on violation
- [ci-qemu, auto, in-logs] Logout path: session-test (informational): Ctrl+Alt+Del and the Leave button make the logout greeter appear in the AT-SPI desktop, then Escape. Owner: log out, see the session return after about 5 s (unit restart); try Shut Down
- [unit, auto, in-logs] Harness self-tests: lint job: PPM parser, band and ring detection on synthetic images including deliberately wrong ones that must fail, QGA framing against a fake socket, idle aggregation, session-report parsers

## Iterations

0. 0. Probe the pinned baseline and the CI runner (no ISO change)
   GOAL: Settle the facts the design depends on:
- pacman -Si of every explicit package, and the closure of the planned list against the baseline list (new packages and summed installed size);
- pacman -Ql qemu-guest-agent, and whether 99-qemu-guest-agent.rules exists (plus its contents);
- pacman -Qo of kscreen-doctor, kwriteconfig6, kpackagetool6, qmltestrunner, qmllint and gsettings;
- org.kde.konsole.desktop, systemsettings.desktop and org.kde.kmenuedit.desktop, with any NoDisplay lines;
- /etc/shells, /etc/pam.d/login, filesystem's group/gshadow and sysusers, the default.target link;
- a 45 s unprivileged kwin_wayland --virtual session that only echoes a marker (checks the 'spectacle hung' reading);
- on ubuntu-24.04: QEMU version and the VGA (xres/yres/edid) and virtserialport properties
   CI: inspect-kde job log sections. Any MISSING, NoDisplay=true, absent udev rule or failed KWIN-SESSION-RAN line changes the package list, catalogue ids or guest-agent plan before any ISO work
1. 1. Spike shell packages and a headless session probe (container; no ISO change)
   GOAL: - Add shell/plasma packages with a spike UI (Applications button, task list, layer-shell launcher with a search field, two launchers) and tests/probe;
- run plasmashell with PLASMA_DEFAULT_SHELL=org.staros.shell under unprivileged kwin_wayland --virtual with no permission variables (setcap -r on kwin_wayland only in this throwaway container, and only if exec fails);
- hard timeouts, QT_FORCE_STDERR_LOGGING=1, logs dumped on any failure;
- the job stays informational, and is dropped after two unexplained hangs (the QEMU path is authoritative)
   CI: PROBE lines: shell=org.staros.shell; layout JSON; KWin 'authorized /usr/bin/plasmashell org_kde_plasma_window_management'; tasks=1 after konsole; AT-SPI Taskbar and Konsole task button; activateLauncherMenu gives launcher=open and focus 'text Search applications'
2. 2. Graphical live ISO with the spike shell and the serial session report
   GOAL: - Packages; liveuser, root lock and sudoers; releng-remove.txt; sshd mask;
- staros-live-session.service and the display-manager link; startstaros; staros.desktop; live config files;
- staros-session-report (ready phase); install_shell_files; check-image-policy.sh;
- boot_test.py --session --profile graphical in UEFI and BIOS;
- regenerate and commit the package manifest
   CI: POLICY ... PASS lines and iso_bytes in the build log; serial 'STAROS-SESSION-CHECK ... logind_type=wayland shell=org.staros.shell layout=... renderer=...' and STAROS-SESSION-OK in both firmware jobs (STAROS-LIVE-BOOT-OK still present); SCREEN band line (informational); full new package list printed, then green after commit
3. 3. Idle report and stability from the serial port
   GOAL: Add the idle and stable phases to staros-session-report; add the idle matrix (3 UEFI boots, no guest agent) and idle-summary; add service hardening only if the report is still produced
   CI: STAROS-IDLE-REPORT JSON per run, STAROS-SESSION-STABLE, and a median/min/max table in the step summary (re-measured on every later push; the final number comes from the final commit)
4. 4. Guest-agent channel and session facts (S0-S4)
   GOAL: - session_test.py with the QGA client and a virtio-serial port. If iteration 0 found no Arch udev rule, add the overlay rule after owner approval, or stop here and mark C2-C5 owner-only;
- S0-S2: boot marker, guest-sync, plasmashell environ, appletsrc name, no ShellPackage override, renderer and Mesa libraries mapped;
- S4: push helpers, enable a11y, load the KWin oracle, walk the taskbar
   CI: 'EVIDENCE C1 ...' lines with PIDs, seconds to ready and renderer; the AT-SPI JSON of the taskbar; oracle 'loaded' event in the log
5. 5. StarOS.Shell UI module, catalogue adapter and unit tests
   GOAL: - Theme (font-derived), FocusFrame, ShellButton, TaskButton, Taskbar with Leave, LauncherTile, Launcher with search;
- AppCatalogue with two proxies; LauncherWindow with hide on deactivate; views/Panel.qml thickness;
- shell-checks job: unit tests at 3 scales, qmllint, kpackagetool6, private-import gate, forbidden-env grep;
- the probe and ISO session must stay green
   CI: qmltestrunner Totals with 0 failed for QT_SCALE_FACTOR 1, 1.5 and 2; check_shell_sources PASS; PROBE and STAROS-SESSION-OK unchanged; STAROS-SHELL ready line shows gridUnit and taskbarHeight
6. 6. Keyboard, window list and switching end to end (S5-S9)
   GOAL: QMP keys and tablet, the AT-SPI focus listener, the oracle listener; launch two apps from the launcher, list them, switch by keyboard; mouse and ring-pixel checks informational
   CI: 'EVIDENCE C2 ... PASS' and 'EVIDENCE C3 ... PASS (focused: <role> <name>)' lines; oracle active-window lines; on failure, AT-SPI dump, journal tail and KWin supportInformation
7. 7. Orca (S10)
   GOAL: Meta+Alt+S path and a debug Orca reading tiles and taskbar buttons; informational until three consecutive green runs, then gating via a reviewed commit
   CI: printed SPEECH OUTPUT lines and 'EVIDENCE C4 orca PASS|INFO'
8. 8. Scaling, stays-up and logout (S11, S12)
   GOAL: kscreen-doctor 1.5, 2, 1 with AT-SPI geometry (gating) and pixel sizes (informational); end-of-scenario stability and QML-error grep; logout prompt check (informational)
   CI: 'EVIDENCE C5 scale=1.5|2 ... PASS' with extents and band rows; 'EVIDENCE C1 stays-up PASS'; all CI jobs green
9. 9. Documentation and owner VMware run
   GOAL: - Update test-plan (T0-20..T0-25 methods and EVIDENCE meanings), phase-0-plan, building and threat model;
- the owner approves ADR-0008 and runs T0-20..T0-25 with 3D on and off;
- ADR-0004 records the A/B decision with CI and VMware idle numbers, the Plasma-surface inventory and the catalogue consequence
   CI: none (owner report); the CI run links of the same commit are cited in the manual test log

## Risks

- plasmashell does not load the Star OS package (kactivitymanagerd, wallpaper wait, metadata, pure Panel containment in PanelView, views contract) [medium/high: blank session] -> kactivitymanagerd explicit, org.kde.color wallpaper, ksplash off, kpackagetool6 in CI, container probe first, serial report with layout JSON and FAIL reason; contingency org.kde.panel hosting Star OS applets
- The display-manager-less unit does not give a usable session (PAM stack, seat/VT, type not wayland) [low-medium/high] -> KDE plasma-mobile.service precedent; systemd v262 env-to-PAM path verified; the serial report prints logind type, seat and VT; OnFailure getty for debugging; fallback vehicle SDDM autologin (DisplayServer=wayland), recorded in ADR-0008
- Arch no longer ships the qemu-guest-agent udev rule, or the owner declines the channel [low/medium: C2-C5 lose QEMU evidence] -> Iteration 0 checks; identical overlay rule only with owner approval; C1 and C6 come from the serial report regardless; C2-C5 fall back to unit tests, the container probe and the owner
- Container KWin --virtual probe hangs or behaves differently from the ISO (QPainter path, capabilities) [medium/low (non-gating)] -> Unprivileged user, no spectacle, hard timeouts, stderr logging; dropped after two unexplained hangs; QEMU is authoritative
- Orca does not present focus from plasmashell's layer-shell launcher or PanelView [medium/high for C4] -> The debug log shows why; try requestActivate on show, a Dialog root role, or an xdg_toplevel fullscreen launcher; AT-SPI evidence still proves names and roles; record as an M0.2 finding (B would face the same)
- A Meta tap through QMP is not recognised as a modifier-only shortcut [low-medium/medium] -> One recorded retry with Alt+F1 (same action); the owner tests Meta in VMware; the container probe exercises the same handler through activateLauncherMenu
- Pixel checks flaky (KWin colour pipeline, llvmpipe rounding) or interaction timing flaky [medium/medium] -> Pixel, mouse and Orca checks are informational until three consecutive green runs; event-driven waits with timeouts; one recorded retry per key step; AT-SPI geometry is authoritative; never weakened silently
- Larger ISO strains runner disk or build time [medium/medium] -> Iteration 0 prints the closure size; build logs df -h and iso_bytes; free host space or adjust compression in a reviewed change if needed
- The curated catalogue under-represents a real launcher; Phase 1 needs a C++ path or the kicker exception [certain/medium] -> ADR-0008 states it; the adapter interface lets Phase 1 replace only the backend; the decision rule weighs it
- Plasma surfaces and conventions leak (Breeze logout greeter, fallback lock screen, activity switcher, KWin switcher) [high/low for a prototype] -> Inventory recorded in ADR-0004; empty toolbox and containment actions; own views and Plasma-free UI module; nothing copied
- Hidden dependency on plasma-desktop's fallback package [certain/low] -> Explicit X-Plasma-FallbackPackage and package entry; Phase 1 decides whether Star OS ships lockscreen/
- Baseline moves to Plasma/KWin 6.8 (desktop-file gating gone, privileged activation by executable name, kaccess toggle moved to kded, QPainter removed) [certain eventually/medium] -> Pinned snapshot; option A keeps the plasmashell executable; re-run every M0.2 check and the owner run on any bump
- Idle numbers mistaken for hardware claims (llvmpipe, VM, the measuring service itself) [high/low-medium] -> Fixed method, median of 3, per-process breakdown, renderer and environment in every report; QEMU and VMware never mixed
- No notification server in the Star OS shell [high/low for M0.2] -> Documented gap; launch errors from requestNewInstance may be lost; Phase 1 adds one (NotificationManager in QML)
- VMware vmwgfx problems (3D on or off), cursor, memory growth [medium/medium] -> Owner tests both 3D settings for 30 minutes; never set KWIN_COMPOSE; workarounds recorded separately, never in the image
- Audio contention between console espeakup (speech entry) and PipeWire [medium/medium for T0-24] -> Owner tests the normal entry with Meta+Alt+S first, then a speech entry; Phase 1 may stop espeakup when the graphical session starts
- Live-user posture (empty password, NOPASSWD sudo) leaks into an installed system [low/high if it happens] -> Live files only in /etc and /home/liveuser (no /etc/skel), listed in the threat model as must-not-copy for the Phase 2 installer; policy check documents them

## Claims verified against upstream source

- plasma-workspace@v6.7.5:shell/scripting/containment.h and panel.h: 'locked' is a writable Q_PROPERTY on containments and panels; applet.cpp setLocked sets UserImmutable; appinterface.h 'locked' is READ coronaLocked WRITE lockCorona (corrects plasma-native's 'getter-only'; verification-first's desk.locked/panel.locked are valid)
- plasma-workspace@v6.7.5:shell/scripting/scriptengine_v1.cpp: gridUnit = QFontMetrics(application font) 'M' bounding height, rounded up to even; scriptengine.cpp exposes lockCorona, desktopsForActivity, currentActivity, gridUnit
- plasma-workspace@v6.7.5:shell/panelview.cpp: defaultFloating() returns true unless isUnsupportedEnvironment(), so panels float by default (layout.js must set floating=false; verification-first omitted it); default lengthMode FillAvailable; setThickness writable with minThickness clamp, no immutability check; context property 'panel'; panelview.h backgroundHints is writable
- plasma-workspace@v6.7.5:shell/scripting/panel.cpp: Panel.height returns PanelView thickness; setHiding accepts autohide/dodgewindows/windowsgobelow, anything else is NormalPanel; floating setter exists
- plasma-workspace@v6.7.5:shell/dbus/org.kde.PlasmaShell.xml and shell/shellcorona.cpp: property 'shell', evaluateScript returns the print buffer and is refused only under SystemImmutable or kiosk; object /PlasmaShell; plasma-plasmashell.service.in BusName=org.kde.plasmashell
- plasma-workspace@v6.7.5:shell/shellcorona.cpp: activateLauncherMenu() asks org.kde.KWin activeOutputName, then emits activated() on panel applets, then the panel containment itself, whose X-Plasma-Provides contains org.kde.plasma.launchermenu; shortcut Meta and Alt+F1; 'cycle-panels' Meta+Alt+P; 'Aborting shell load' when kactivitymanagerd is not running
- plasma-workspace@v6.7.5:libtaskmanager/*.h: QML elements are TasksModel, VirtualDesktopInfo, ActivityInfo, AbstractTasksModel (uncreatable), ScreencastingRequest; LauncherTasksModel is not exposed to QML
- kitemmodels@v6.31.0:src/qml/ksortfilterproxymodel.cpp: when filterRowCallback is callable, filterAcceptsRow returns only its result (filterString ignored), so search needs a second proxy; setFilterRowCallback invalidates the filter; filterString uses setFilterFixedString
- plasma-desktop@v6.7.5:applets/taskmanager/main.xml: default launchers include 'applications:systemsettings.desktop'
- libplasma@v6.7.5:src/plasma/pluginloader.cpp: a pure KPackage whose metadata has X-Plasma-ContainmentType becomes a Plasma::Containment; src/plasma/containment.cpp reads the type from that key; plasma-desktop@v6.7.5:containments/desktop is plasma_install_package (pure) and containments/panel is plasma_add_applet with GENERATE_CONTAINMENT_CLASS
- plasma-nano@v6.7.5:shell/contents/views/Panel.qml: view contract 'property Item containment', reparent and fill, panel.backgroundHints = containment.plasmoid.backgroundHints
- libplasma@v6.7.5:src/plasmaquick/plasmoid/plasmoiditem.cpp: Applet::activated sets expanded; plasma-mobile@v6.7.5:containments/homescreens/{folio,halcyon}/qml/main.qml use Plasmoid.onActivated on containments
- plasma-mobile@v6.7.5:plasma-mobile.service: display-manager-less unit (Conflicts and After getty@tty1, OnFailure=getty@tty1, PAMName=login, User=1000, TTYPath=/dev/tty1, Restart=always, Alias=display-manager.service); it does not set XDG_SESSION_TYPE and uses XDG_VTNR=tty1; bin/startplasmamobile.in exports PLASMA_DEFAULT_SHELL then runs startplasma-wayland
- systemd@v262:src/core/exec-invoke.c: the unit environment is pam_putenv'd before pam_open_session; src/login/pam_systemd.c reads XDG_SESSION_TYPE, CLASS, DESKTOP and SEAT via getenv_harder and XDG_VTNR via getenv_harder_uint32 (so 'tty1' is not a valid value; use 1)
- orca@51.1:src/orca/speech_presenter.py: "SPEECH OUTPUT: '<text>'" is logged at LEVEL_INFO both with and without a speech server; src/orca/orca_bin.py.in: --debug sets LEVEL_ALL, --debug-file exists; orca.desktop.in has NoDisplay=true; orca.service is PartOf/WantedBy graphical-session.target, ExecStart=orca --replace
- qemu@v11.1.2:contrib/systemd/qemu-guest-agent.service: BindTo the virtio port device, empty [Install] (enabling it does nothing)
- archlinux/svntogit-packages@a671ac6 (branch packages/qemu, 2023-04-25):trunk/PKGBUILD and 99-qemu-guest-agent.rules: Arch's qemu-guest-agent installs a udev rule with TAG+=systemd and SYSTEMD_WANTS=qemu-guest-agent.service for org.qemu.guest_agent.0, plus qemu-ga.conf with no blacklist; to be re-checked at the 2026-10-15 snapshot
- archlinux/svntogit-packages (branch packages/filesystem, 2023-02-05):trunk: /etc/group and gshadow contain only root; passwd, group, gshadow and shadow are backup files; system groups come from usr/lib/sysusers.d/arch.conf; /etc/shells lists /bin/bash
- kwin@v6.7.5:src/globalshortcuts.cpp creates KGlobalAccelD in-process (KGLOBALACCELD_PLATFORM=org.kde.kwin); kglobalacceld@v6.7.5:src/main.cpp exits when XDG_SESSION_TYPE=wayland (corrects verification-first's process list)
- kwin@v6.7.5:src/wayland/layershell_v1.cpp stores keyboard_interactivity as a bool acceptsFocus (Exclusive behaves like OnDemand); src/layershellv1window.cpp handleAcceptsFocusChanged activates Top/Overlay surfaces that want input and sets skipSwitcher, skipPager and skipTaskbar
- kwin@v6.7.5:src/xdgactivationv1.cpp isPrivilegedInWindowManagement uses the client's requestedInterfaces (window management or lockscreen overlay); src/wayland_server.cpp skips the check and the requestedInterfaces bookkeeping under KWIN_WAYLAND_NO_PERMISSION_CHECKS; src/workspace.cpp activates new windows at focus-stealing level Low or below; src/activation.cpp special-cases 4-edge-anchored layer surfaces
- kwin@v6.7.5:src/scripting/scripting.h and scripting.cpp: org.kde.kwin.Scripting.loadScript on /Scripting, scripts exported at /Scripting/Script<N> with run(); callDBus is available to scripts; workspace_wrapper.h has activeWindow, windowAdded, windowRemoved, windowActivated and windowList(); scripting_logging.cpp kwin_scripting defaults to QtWarningMsg (so the oracle reports over D-Bus)
- plasma-workspace@v6.7.5:startkde/systemd/plasma-workspace.target and plasma-core.target: workspace Wants powerdevil, polkit-agent, kde-baloo, kglobalaccel, kaccess, xdg-desktop-autostart; core Wants plasmashell, kcminit, kded6, ksmserver
- baloo@v6.31.0:src/file/kde-baloo.service.in: ExecCondition on 'baloofilerc:Basic Settings:Indexing-Enabled:true'; src/lib/baloosettings.kcfg key Indexing-Enabled
- plasma-desktop@v6.7.5:kaccess/kaccess.cpp: reads kaccessrc [ScreenReader] Enabled at start and calls setScreenReaderEnabled; Meta+Alt+S toggles and writes it; Orca is started only if 'gsettings set org.gnome.desktop.a11y.applications screen-reader-enabled true' exits 0
- kscreenlocker@v6.7.5:ksldapp.cpp and interface.cpp gate locking on KAuthorized::authorizeAction('lock_screen'); kconfig@v6.31.0:src/core/kauthorized.cpp prefixes 'action/'
- plasma-workspace@v6.7.5:logout-greeter/main.cpp loads the Plasma/LookAndFeel package named by kdeglobals LookAndFeelPackage, not the shell package (corrects verification-first)
- plasma-workspace@v6.7.5:startkde/startplasma.cpp: ksplash starts only if ksplashrc Engine is KSplashQML; syncDBusEnvironment pushes the environment; startplasma-wayland.cpp calls it
- archiso@v91:configs/releng/airootfs: getty@tty1.service.d/autologin.conf (root), multi-user.target.wants/sshd.service, passwd and shadow with root only and an empty password; configs/releng/packages.x86_64 includes qemu-guest-agent, open-vm-tools and espeakup; archiso/mkarchiso _make_customize_airootfs copies skel for UID 1000-59999 from the profile passwd with --update=none, chmod 0750, chown -hR
- qtdeclarative@v6.12.0:src/quicktemplates/qquickabstractbutton.cpp (non-checkable is QAccessible::Button) and src/quick/items/qquicktextinput.cpp (EditableText); qtbase@v6.12.0:src/gui/accessible/linux/qspiaccessiblebridge.cpp maps ToolBar to 'tool bar', List to 'list', PushButton to 'push button', EditableText to 'text', Pane to 'panel', Heading to 'heading'
- Star-OS CI probe log (inspect-kde run 2, scripts at bc4fb29): installing kwin, plasma-workspace, plasma-desktop and the probe list into the pinned container pulled in kactivitymanagerd, kglobalacceld, powerdevil, polkit-kde-agent, xdg-desktop-portal-kde, baloo, libkscreen, systemsettings, kmenuedit, kscreenlocker, python-gobject, gsettings-desktop-schemas, pipewire and wireplumber, but not pipewire-pulse; the earlier KWin smoke shows exit 124 with an empty kwin.log and a created but empty spectacle.log (session script ran; spectacle likely hung)
- Star-OS working tree (read-only): build-iso.sh copies the overlay after releng with cp -a; boot_test.py build_qemu_command uses -vga std, 2048 MiB, -smp 2; M0.1 overlay files motd and staros-release carry no SPDX line (precedent for passwd/shadow/group/gshadow); the baseline already has gsettings-desktop-schemas, at-spi2-core, python, sudo, qemu-guest-agent 11.1.2 and open-vm-tools

## Open unknowns

- Whether the 2026-10-15 Arch qemu-guest-agent package still ships the udev auto-start rule (iteration 0)
- Exact dependency closure and size of the explicit package list; runner disk headroom for the larger ISO
- Whether an unprivileged kwin_wayland --virtual with plasmashell runs reliably in the GitHub Arch container (the earlier hang is attributed to spectacle by inference only)
- Whether the PAM 'login' stack on Arch plus Environment=XDG_SESSION_TYPE=wayland yields a logind 'wayland' session from a system unit as the source suggests (asserted by the serial report)
- Whether Orca 51.1 presents focus changes from plasmashell's layer-shell launcher and PanelView
- Whether a QMP Meta tap triggers KWin's modifier-only launcher shortcut inside the VM
- Whether KWin on llvmpipe and bochs-drm reproduces the reserved colours exactly enough for pixel checks
- Whether QEMU on ubuntu-24.04 accepts -device VGA,xres=1920,yres=1080 and offers it as the preferred mode
- Whether plasmashell's QML console.info lines reach the journal at default logging rules (the checks use evaluateScript and AT-SPI as authority)
- Whether the kiosk action/lock_screen=false in the user's kdeglobals is honoured by the KSldApp hosted in kwin_wayland (owner checks that Meta+L does nothing)
- Whether org.kde.kmenuedit.desktop is installed and visible, and which package ships kwriteconfig6
- Whether plasmashell launched apps get focus from the launcher in practice (asserted by the oracle; contingency ready)
- Whether empty-password console login works on the getty fallback (pam_unix nullok in Arch pambase)
- VMware behaviour: vmwgfx with 3D on and off, cursor, auto-resize, memory growth, speech output through PipeWire
- The idle RAM and CPU numbers themselves, and how they would compare with an option-B session (B is not built)
