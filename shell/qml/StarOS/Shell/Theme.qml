// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton

import QtQuick

// Star OS design tokens. Sizes are logical pixels derived from the application
// font, so a larger font grows the taskbar, tiles and touch targets. The opaque
// colours are kept apart so that states stay distinguishable; tst_theme.qml
// checks their contrast.
QtObject {
    readonly property FontMetrics metrics: FontMetrics {}

    readonly property int gridUnit: Math.max(16, 2 * Math.ceil(metrics.height / 2))
    readonly property int spacing: Math.round(gridUnit / 2)
    readonly property int taskbarHeight: Math.max(40, Math.round(2.5 * gridUnit))
    readonly property int minTarget: Math.max(32, 2 * gridUnit)
    readonly property int startButtonWidth: 8 * gridUnit
    readonly property int taskButtonWidth: 12 * gridUnit
    readonly property int tileWidth: 9 * gridUnit
    readonly property int tileHeight: 7 * gridUnit
    readonly property int monogramSize: 3 * gridUnit
    readonly property int tileIconSize: Math.round(3.5 * gridUnit)
    readonly property int taskIconSize: Math.round(1.25 * gridUnit)
    readonly property int controlRadius: spacing
    readonly property int searchHeight: Math.round(2.5 * gridUnit)
    readonly property int searchMaxWidth: 30 * gridUnit
    readonly property int launcherMargin: 2 * gridUnit
    readonly property int focusRingWidth: 3
    readonly property int activeIndicatorHeight: 3
    // No animations yet: reduced motion holds trivially and screenshots are
    // deterministic. Phase 1 binds durations to the platform motion preference.
    readonly property int animationDuration: 0

    readonly property color desktop: "#24364a"
    readonly property color taskbar: "#16202c"
    readonly property color taskbarButton: "#1f2b3a"
    readonly property color taskbarButtonPressed: "#2a3a4e"
    readonly property color launcherBackdrop: "#0e141b"
    readonly property color tile: "#223041"
    readonly property color monogram: "#2c4058"
    readonly property color searchField: "#1a2531"
    readonly property color searchBorder: "#7d8fa3"
    readonly property color text: "#f2f5f8"
    readonly property color placeholder: "#a9b6c4"
    readonly property color activeIndicator: "#5cc8a8"
    readonly property color focusRing: "#ffb400"

    // Frosted glass (M0.3): a glass surface shows the Star OS wallpaper behind
    // it, blurred, under glassTint at glassTintOpacity. Blur only mixes
    // wallpaper colours, so the glass is never lighter than the tint over
    // wallpaperLightest, which every wallpaper colour stays below channel by
    // channel (check_shell_sources.py). Worst cases (tst_theme.qml):
    //   glass over wallpaperLightest, #3b3d61: text 9.43:1, focus ring 5.79:1;
    //   glassButtonPressed on it, #5b5d7a: text 5.86:1, ring 3.60:1,
    //   active indicator 3.14:1;
    //   glass over wallpaperDarkest, #080d1f: text 17.6:1, ring 10.8:1.
    readonly property url wallpaper: Qt.resolvedUrl("wallpaper/star-os-glass.svg")
    readonly property color wallpaperDarkest: "#04071a"
    readonly property color wallpaperLightest: "#a49ee6"
    // When true, every glass surface is drawn opaque in glassFallback.
    property bool reduceTransparency: false
    readonly property color glassTint: "#0a1022"
    readonly property real glassTintOpacity: 0.68
    readonly property color glassBorder: "#2effffff"
    readonly property real glassBlur: 1.0
    readonly property int glassBlurMax: 64
    readonly property int glassRadius: gridUnit
    readonly property color glassFallback: "#151c33"
    // Translucent fills on glass, lightest last.
    readonly property color tileGlass: "#12ffffff"
    readonly property color glassButton: "#14ffffff"
    readonly property color glassButtonActive: "#1fffffff"
    readonly property color glassButtonPressed: "#29ffffff"
}
