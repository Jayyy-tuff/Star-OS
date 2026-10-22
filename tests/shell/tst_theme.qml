// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import StarOS.Shell

// Design tokens: font-derived sizes, WCAG 2.2 contrast of the opaque colours
// (text 4.5:1, focus ring and field border 3:1), and of the frosted glass in
// its worst cases: the tint over the wallpaper's lightest and darkest colours,
// with each translucent fill that sits on glass.
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

    // Source-over compositing of a colour with opacity alpha on an opaque one.
    function over(fg, alpha, bg) {
        return Qt.rgba(fg.r * alpha + bg.r * (1 - alpha), fg.g * alpha + bg.g * (1 - alpha),
                       fg.b * alpha + bg.b * (1 - alpha), 1);
    }

    function glassOver(wallpaperColour) {
        return over(Theme.glassTint, Theme.glassTintOpacity, wallpaperColour);
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

    function test_glass_tokens() {
        verify(String(Theme.wallpaper).endsWith("/wallpaper/star-os-glass.svg"), String(Theme.wallpaper));
        compare(Theme.reduceTransparency, false);
        verify(Theme.glassTintOpacity > 0 && Theme.glassTintOpacity < 1);
        verify(Theme.glassBlur > 0 && Theme.glassBlur <= 1);
        verify(Theme.glassBlurMax >= 2 && Theme.glassBlurMax <= 64);
        verify(Theme.glassRadius >= 0);
        // Opaque colours, so the contrast arithmetic below holds.
        for (const c of [Theme.glassTint, Theme.glassFallback, Theme.wallpaperDarkest,
                         Theme.wallpaperLightest, Theme.text, Theme.focusRing, Theme.activeIndicator]) {
            compare(c.a, 1);
        }
        // Translucent fills, lightest last, and a translucent edge line.
        const fills = [Theme.tileGlass, Theme.glassButton, Theme.glassButtonActive, Theme.glassButtonPressed];
        for (let i = 0; i < fills.length; ++i) {
            verify(fills[i].a > 0 && fills[i].a < 1, "fill " + i + " is translucent");
            verify(i === 0 || fills[i].a > fills[i - 1].a, "fill " + i + " is lighter than the one before");
        }
        verify(Theme.glassBorder.a > 0 && Theme.glassBorder.a < 1);
        verify(luminance(Theme.wallpaperDarkest) < luminance(Theme.wallpaperLightest));
    }

    // Every colour behind glass text: the glass over the wallpaper's lightest
    // and darkest colours (blur only mixes wallpaper colours, which stay
    // between those two, channel by channel), and the opaque fallback; each
    // bare and under every translucent fill.
    function test_glass_contrast_data() {
        const backdrops = [
            {name: "lightest", colour: glassOver(Theme.wallpaperLightest)},
            {name: "darkest", colour: glassOver(Theme.wallpaperDarkest)},
            {name: "fallback", colour: Theme.glassFallback}
        ];
        const fills = [
            {name: "glass", colour: Theme.glassTint, alpha: 0},
            {name: "tileGlass", colour: Theme.tileGlass, alpha: Theme.tileGlass.a},
            {name: "glassButton", colour: Theme.glassButton, alpha: Theme.glassButton.a},
            {name: "glassButtonActive", colour: Theme.glassButtonActive, alpha: Theme.glassButtonActive.a},
            {name: "glassButtonPressed", colour: Theme.glassButtonPressed, alpha: Theme.glassButtonPressed.a}
        ];
        const rows = [];
        for (const backdrop of backdrops) {
            for (const fill of fills) {
                const bg = over(fill.colour, fill.alpha, backdrop.colour);
                const where = fill.name + "/" + backdrop.name;
                rows.push({tag: "text/" + where, fg: Theme.text, bg: bg, min: 4.5});
                rows.push({tag: "ring/" + where, fg: Theme.focusRing, bg: bg, min: 3});
                if (fill.name.startsWith("glassButton")) {
                    rows.push({tag: "indicator/" + where, fg: Theme.activeIndicator, bg: bg, min: 3});
                }
            }
        }
        return rows;
    }

    function test_glass_contrast(data) {
        const ratio = contrast(data.fg, data.bg);
        verify(ratio >= data.min, data.tag + " contrast " + ratio.toFixed(2) + " < " + data.min);
    }

    // The numbers documented in Theme.qml.
    function test_glass_worst_case_is_documented() {
        const glass = glassOver(Theme.wallpaperLightest);
        const pressed = over(Theme.glassButtonPressed, Theme.glassButtonPressed.a, glass);
        console.info("STAROS-TEST glass lightest=" + glass + " text=" + contrast(Theme.text, glass).toFixed(2)
            + " ring=" + contrast(Theme.focusRing, glass).toFixed(2) + " pressed=" + pressed
            + " text=" + contrast(Theme.text, pressed).toFixed(2)
            + " ring=" + contrast(Theme.focusRing, pressed).toFixed(2)
            + " indicator=" + contrast(Theme.activeIndicator, pressed).toFixed(2));
        fuzzyCompare(contrast(Theme.text, glass), 9.43, 0.01);
        fuzzyCompare(contrast(Theme.focusRing, glass), 5.79, 0.01);
        fuzzyCompare(contrast(Theme.text, pressed), 5.86, 0.01);
        fuzzyCompare(contrast(Theme.focusRing, pressed), 3.60, 0.01);
        fuzzyCompare(contrast(Theme.activeIndicator, pressed), 3.14, 0.01);
    }

    function test_opaque_colours_are_distinct() {
        const colours = [Theme.desktop, Theme.taskbar, Theme.taskbarButton, Theme.launcherBackdrop,
            Theme.tile, Theme.monogram, Theme.searchField, Theme.focusRing, Theme.activeIndicator,
            Theme.glassFallback];
        for (let i = 0; i < colours.length; ++i) {
            for (let j = i + 1; j < colours.length; ++j) {
                verify(!Qt.colorEqual(colours[i], colours[j]), "colours " + i + " and " + j);
            }
        }
    }
}
