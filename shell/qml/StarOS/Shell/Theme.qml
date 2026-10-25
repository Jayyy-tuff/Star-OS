// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton

import QtQuick

// Star OS design tokens, "deep space" (M0.5,
// docs/architecture/m05-deep-space-design.md section 1). Sizes are logical
// pixels derived from the application font, so a larger font grows the
// taskbar, tiles and touch targets. The opaque colours are kept apart so that
// states stay distinguishable; tst_theme.qml checks their contrast. The Star
// OS apps share these tokens, so they follow the shell's look.
QtObject {
    readonly property FontMetrics metrics: FontMetrics {}

    readonly property int gridUnit: Math.max(16, 2 * Math.ceil(metrics.height / 2))
    readonly property int spacing: Math.round(gridUnit / 2)
    readonly property int minTarget: Math.max(32, 2 * gridUnit)
    readonly property int focusRingWidth: 3
    readonly property int activeIndicatorHeight: 3

    // The floating taskbar: a pill taskbarPillHeight tall, taskbarGap above
    // the screen edge, with taskbarShadowRoom above it for its shadow. The
    // panel window is taskbarHeight thick, so windows maximise above all that.
    readonly property int taskbarPillHeight: Math.round(3.1 * gridUnit)
    readonly property int taskbarButtonSize: taskbarPillHeight - 2 * Math.round(gridUnit / 3)
    readonly property int taskbarGap: Math.round(gridUnit / 2)
    readonly property int taskbarShadowRoom: Math.round(0.75 * gridUnit)
    readonly property int taskbarHeight: taskbarPillHeight + taskbarGap + taskbarShadowRoom
    readonly property int taskbarRadius: gridUnit
    readonly property int startButtonWidth: taskbarButtonSize
    readonly property int taskButtonWidth: taskbarButtonSize
    readonly property int taskIconSize: 2 * Math.round(0.8 * gridUnit)
    readonly property int symbolSize: Math.round(1.05 * gridUnit)

    // Panels above the taskbar: the start menu and the tray's panels.
    readonly property int panelRadius: Math.round(1.25 * gridUnit)
    readonly property int panelPadding: Math.round(1.4 * gridUnit)
    readonly property int popupGap: Math.round(0.67 * gridUnit)
    readonly property int startMenuWidth: 37 * gridUnit
    readonly property int trayPanelWidth: 22 * gridUnit

    // Start menu tiles and rows.
    readonly property int tileWidth: Math.round(5.5 * gridUnit)
    readonly property int tileHeight: Math.round(5.25 * gridUnit)
    readonly property int tileIconSize: 2 * Math.round(1.2 * gridUnit)
    readonly property int rowIconSize: 2 * Math.round(0.95 * gridUnit)
    readonly property int rowHeight: Math.round(3 * gridUnit)
    readonly property int monogramSize: 3 * gridUnit
    readonly property int controlRadius: Math.round(0.67 * gridUnit)
    readonly property int searchHeight: Math.round(2.5 * gridUnit)
    readonly property int searchMaxWidth: 30 * gridUnit
    readonly property int launcherMargin: 2 * gridUnit

    // Type scale, from the application font.
    // Logical pixels: Qt uses 96 dpi for point sizes.
    readonly property real fontSize: metrics.font.pixelSize > 0 ? metrics.font.pixelSize : metrics.font.pointSize * 96 / 72
    readonly property int smallPixelSize: Math.max(10, Math.round(0.85 * fontSize))
    readonly property int headingPixelSize: Math.round(1.1 * fontSize)
    readonly property int titlePixelSize: Math.round(1.5 * fontSize)

    // Motion: the host sets animationFactor from the platform (0 with reduced
    // motion); unit tests set 0, so screenshots are deterministic.
    property real animationFactor: 1
    readonly property int durationShort: Math.round(120 * animationFactor)
    readonly property int durationMedium: Math.round(220 * animationFactor)

    // Opaque colours: fallbacks without a GPU scene graph and the apps' own
    // surfaces.
    readonly property color desktop: "#10123a"
    readonly property color taskbar: "#0f1130"
    readonly property color taskbarButton: "#1a1d42"
    readonly property color taskbarButtonPressed: "#262a58"
    readonly property color launcherBackdrop: "#090b1e"
    readonly property color tile: "#171a3e"
    readonly property color monogram: "#2f3270"
    readonly property color searchField: "#14173a"
    readonly property color searchBorder: "#8481c4"
    readonly property color text: "#f4f3ff"
    readonly property color textSecondary: "#d2cff2"
    readonly property color textTertiary: "#c6c3ea"
    readonly property color placeholder: "#a9a6cf"
    readonly property color activeIndicator: "#c4b8ff"
    readonly property color focusRing: "#ffb400"
    // The accent: a violet-to-blue gradient; white text on either end keeps
    // 4.5:1 (tst_theme.qml).
    readonly property color accent: "#6a5ae8"
    readonly property color accentEnd: "#4d6be8"
    readonly property color accentText: "#ffffff"
    readonly property Gradient accentGradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#6a5ae8" }
        GradientStop { position: 1; color: "#4d6be8" }
    }
    // Dims the screen behind the start menu and the tray's panels.
    readonly property color scrim: "#33000010"
    readonly property color shadow: "#a0020310"

    // Frosted glass (M0.3): a glass surface shows the Star OS wallpaper behind
    // it, blurred, under glassTint at an opacity (panels glassTintOpacity, the
    // taskbar taskbarTintOpacity). Blur only mixes wallpaper colours, so the
    // glass is never lighter than the tint over wallpaperLightest, which every
    // wallpaper colour stays below channel by channel
    // (check_shell_sources.py). Worst cases, the pressed fill on the glass
    // over wallpaperLightest (tst_theme.qml):
    //   panel #4d4d69: text 7.42:1, secondary 5.41:1, tertiary 4.81:1,
    //   focus ring 4.57:1;
    //   taskbar #575776: text 6.34:1, secondary 4.63:1, focus ring 3.91:1,
    //   active indicator 3.86:1 (tertiary marks only, 4.11:1).
    readonly property url wallpaper: Qt.resolvedUrl("wallpaper/star-os-glass.svg")
    readonly property color wallpaperDarkest: "#04071a"
    readonly property color wallpaperLightest: "#a49ee6"
    // When true, every glass surface is drawn opaque in glassFallback.
    property bool reduceTransparency: false
    readonly property color glassTint: "#0c0e26"
    readonly property real glassTintOpacity: 0.80
    readonly property real taskbarTintOpacity: 0.72
    readonly property color glassBorder: "#24ffffff"
    readonly property color glassHighlight: "#14ffffff"
    readonly property real glassBlur: 1.0
    readonly property int glassBlurMax: 64
    readonly property int glassRadius: panelRadius
    readonly property color glassFallback: "#14163a"
    // Translucent fills on glass, lightest last: hover, button, selected,
    // pressed.
    readonly property color tileGlass: "#0fffffff"
    readonly property color glassButton: "#14ffffff"
    readonly property color glassButtonActive: "#1fffffff"
    readonly property color glassButtonPressed: "#29ffffff"
}
