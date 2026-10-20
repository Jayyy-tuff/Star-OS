// SPDX-License-Identifier: GPL-3.0-or-later
pragma Singleton

import QtQuick

// Star OS prototype design tokens (M0.2). Sizes are logical pixels derived from
// the application font, so a larger font grows the taskbar, tiles and touch
// targets. The colours are reserved: CI screen analysis looks for them, so they
// are not reused for other purposes.
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
    readonly property int searchHeight: Math.round(2.5 * gridUnit)
    readonly property int searchMaxWidth: 30 * gridUnit
    readonly property int launcherMargin: 2 * gridUnit
    readonly property int focusRingWidth: 3
    readonly property int activeIndicatorHeight: 3
    // No animations in M0.2: reduced motion holds trivially and screenshots are
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
}
