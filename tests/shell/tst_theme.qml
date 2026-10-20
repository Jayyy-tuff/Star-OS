// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import StarOS.Shell

// Design tokens: font-derived sizes and WCAG 2.2 contrast of the reserved
// colours (text 4.5:1, focus ring and field border 3:1).
TestCase {
    name: "Theme"

    function luminance(c) {
        const lin = v => v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }

    function contrast(a, b) {
        const la = luminance(a);
        const lb = luminance(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

    function test_sizes() {
        console.info("STAROS-TEST theme gridUnit=" + Theme.gridUnit
            + " fontHeight=" + Theme.metrics.height + " taskbarHeight=" + Theme.taskbarHeight);
        verify(Theme.gridUnit >= 16);
        compare(Theme.gridUnit % 2, 0);
        verify(Theme.gridUnit >= Theme.metrics.height);
        verify(Theme.taskbarHeight >= 40);
        verify(Theme.minTarget >= 32);
        // Taskbar buttons are taskbarHeight - spacing tall.
        verify(Theme.taskbarHeight - Theme.spacing >= Theme.minTarget);
        compare(Theme.focusRingWidth, 3);
        compare(Theme.animationDuration, 0);
    }

    function test_contrast_data() {
        return [
            {tag: "text/taskbar", fg: Theme.text, bg: Theme.taskbar, min: 4.5},
            {tag: "text/taskbarButton", fg: Theme.text, bg: Theme.taskbarButton, min: 4.5},
            {tag: "text/pressed", fg: Theme.text, bg: Theme.taskbarButtonPressed, min: 4.5},
            {tag: "text/tile", fg: Theme.text, bg: Theme.tile, min: 4.5},
            {tag: "text/monogram", fg: Theme.text, bg: Theme.monogram, min: 4.5},
            {tag: "text/searchField", fg: Theme.text, bg: Theme.searchField, min: 4.5},
            {tag: "text/launcherBackdrop", fg: Theme.text, bg: Theme.launcherBackdrop, min: 4.5},
            {tag: "placeholder/searchField", fg: Theme.placeholder, bg: Theme.searchField, min: 4.5},
            {tag: "ring/taskbar", fg: Theme.focusRing, bg: Theme.taskbar, min: 3},
            {tag: "ring/taskbarButton", fg: Theme.focusRing, bg: Theme.taskbarButton, min: 3},
            {tag: "ring/pressed", fg: Theme.focusRing, bg: Theme.taskbarButtonPressed, min: 3},
            {tag: "ring/tile", fg: Theme.focusRing, bg: Theme.tile, min: 3},
            {tag: "ring/launcherBackdrop", fg: Theme.focusRing, bg: Theme.launcherBackdrop, min: 3},
            {tag: "ring/searchField", fg: Theme.focusRing, bg: Theme.searchField, min: 3},
            {tag: "ring/desktop", fg: Theme.focusRing, bg: Theme.desktop, min: 3},
            {tag: "border/launcherBackdrop", fg: Theme.searchBorder, bg: Theme.launcherBackdrop, min: 3},
            {tag: "border/searchField", fg: Theme.searchBorder, bg: Theme.searchField, min: 3},
            {tag: "indicator/taskbarButton", fg: Theme.activeIndicator, bg: Theme.taskbarButton, min: 3}
        ];
    }

    function test_contrast(data) {
        const ratio = contrast(data.fg, data.bg);
        verify(ratio >= data.min, data.tag + " contrast " + ratio.toFixed(2) + " < " + data.min);
    }

    function test_reserved_colours_are_distinct() {
        const colours = [Theme.desktop, Theme.taskbar, Theme.taskbarButton, Theme.launcherBackdrop,
            Theme.tile, Theme.monogram, Theme.searchField, Theme.focusRing, Theme.activeIndicator];
        for (let i = 0; i < colours.length; ++i) {
            for (let j = i + 1; j < colours.length; ++j) {
                verify(!Qt.colorEqual(colours[i], colours[j]), "colours " + i + " and " + j);
            }
        }
    }
}
