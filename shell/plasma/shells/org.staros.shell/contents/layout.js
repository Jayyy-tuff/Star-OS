// SPDX-License-Identifier: GPL-3.0-or-later
// First-run layout of the Star OS prototype shell (M0.2). The live user's home
// is fresh on every boot, so this runs at every live session start.

for (const desk of desktopsForActivity(currentActivity())) {
    // org.kde.color is a pure-QML wallpaper in plasma-workspace; a valid
    // wallpaper plugin avoids the 6.7 startup hang on a missing one. The
    // org.staros.desktop containment draws the Star OS wallpaper over it.
    desk.wallpaperPlugin = "org.kde.color";
    desk.currentConfigGroup = ["Wallpaper", "org.kde.color", "General"];
    desk.writeConfig("Color", "#24364a"); // Theme.desktop, until the SVG is drawn
    desk.locked = true;
}

const panel = new Panel("org.staros.taskbar");
panel.location = "bottom";
panel.height = Math.round(2.5 * gridUnit); // seed; views/Panel.qml applies Theme.taskbarHeight
panel.lengthMode = "fill";
panel.hiding = "none";
panel.floating = false; // PanelView floats by default on Wayland
panel.locked = true;
