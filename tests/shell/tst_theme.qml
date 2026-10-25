// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtTest
import StarOS.Shell

// Design tokens (M0.5 deep space): font-derived sizes, the floating taskbar's
// parts, motion, WCAG 2.2 contrast of the opaque colours (text 4.5:1, focus
// ring, borders and marks 3:1), and of the frosted glass in its worst cases:
// the panel and taskbar tints over the wallpaper's lightest and darkest
// colours, with each translucent fill that sits on glass.
TestCase {
    name: "Theme"

    function cleanup() {
        Theme.animationFactor = 1;
    }

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

    function glassOver(wallpaperColour, tintOpacity) {
        return over(Theme.glassTint, tintOpacity, wallpaperColour);
    }

    function test_sizes() {
        console.info("STAROS-TEST theme gridUnit=" + Theme.gridUnit
            + " fontHeight=" + Theme.metrics.height + " fontSize=" + Theme.fontSize
            + " taskbarHeight=" + Theme.taskbarHeight + " pill=" + Theme.taskbarPillHeight);
        verify(Theme.gridUnit >= 16);
        compare(Theme.gridUnit % 2, 0);
        verify(Theme.gridUnit >= Theme.metrics.height);
        verify(Theme.minTarget >= 32);
        compare(Theme.focusRingWidth, 3);
        // The pill, its gap and the shadow's room make the panel's thickness.
        compare(Theme.taskbarHeight, Theme.taskbarPillHeight + Theme.taskbarGap + Theme.taskbarShadowRoom);
        verify(Theme.taskbarButtonSize >= Theme.minTarget);
        verify(Theme.taskbarButtonSize < Theme.taskbarPillHeight);
        verify(Theme.taskIconSize < Theme.taskbarButtonSize);
        verify(Theme.tileIconSize < Theme.tileHeight);
        verify(Theme.rowHeight >= Theme.minTarget);
        verify(Theme.fontSize > 0);
        verify(Theme.smallPixelSize < Theme.headingPixelSize && Theme.headingPixelSize < Theme.titlePixelSize);
        verify(Theme.startMenuWidth >= 6 * Theme.tileWidth + 2 * Theme.panelPadding,
               "six pinned apps fit in a row");
    }

    function test_motion_follows_the_factor() {
        Theme.animationFactor = 1;
        compare(Theme.durationShort, 120);
        compare(Theme.durationMedium, 220);
        Theme.animationFactor = 0;
        compare(Theme.durationShort, 0);
        compare(Theme.durationMedium, 0);
        Theme.animationFactor = 0.5;
        compare(Theme.durationMedium, 110);
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
            {tag: "text/glassFallback", fg: Theme.text, bg: Theme.glassFallback, min: 4.5},
            {tag: "secondary/glassFallback", fg: Theme.textSecondary, bg: Theme.glassFallback, min: 4.5},
            {tag: "tertiary/glassFallback", fg: Theme.textTertiary, bg: Theme.glassFallback, min: 4.5},
            {tag: "placeholder/searchField", fg: Theme.placeholder, bg: Theme.searchField, min: 4.5},
            {tag: "accentText/accent", fg: Theme.accentText, bg: Theme.accent, min: 4.5},
            {tag: "accentText/accentEnd", fg: Theme.accentText, bg: Theme.accentEnd, min: 4.5},
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
        verify(Theme.taskbarTintOpacity > 0 && Theme.taskbarTintOpacity < 1);
        verify(Theme.glassBlur > 0 && Theme.glassBlur <= 1);
        verify(Theme.glassBlurMax >= 2 && Theme.glassBlurMax <= 64);
        verify(Theme.glassRadius >= 0);
        // Opaque colours, so the contrast arithmetic below holds.
        for (const c of [Theme.glassTint, Theme.glassFallback, Theme.wallpaperDarkest, Theme.wallpaperLightest,
                         Theme.text, Theme.textSecondary, Theme.textTertiary, Theme.focusRing, Theme.activeIndicator,
                         Theme.accent, Theme.accentEnd]) {
            compare(c.a, 1);
        }
        // Translucent fills, lightest last, and a translucent edge line.
        const fills = [Theme.tileGlass, Theme.glassButton, Theme.glassButtonActive, Theme.glassButtonPressed];
        for (let i = 0; i < fills.length; ++i) {
            verify(fills[i].a > 0 && fills[i].a < 1, "fill " + i + " is translucent");
            verify(i === 0 || fills[i].a > fills[i - 1].a, "fill " + i + " is lighter than the one before");
        }
        verify(Theme.glassBorder.a > 0 && Theme.glassBorder.a < 1);
        verify(Theme.scrim.a > 0 && Theme.scrim.a < 0.5, "the scrim only dims");
        verify(luminance(Theme.wallpaperDarkest) < luminance(Theme.wallpaperLightest));
        // The accent gradient runs between the two accent colours.
        const stops = Theme.accentGradient.stops;
        compare(stops.length, 2);
        verify(Qt.colorEqual(stops[0].color, Theme.accent));
        verify(Qt.colorEqual(stops[1].color, Theme.accentEnd));
    }

    // Every colour behind glass text: the panel and taskbar glass over the
    // wallpaper's lightest and darkest colours (blur only mixes wallpaper
    // colours, which stay between those two, channel by channel), and the
    // opaque fallback; each bare and under every translucent fill.
    function test_glass_contrast_data() {
        const glasses = [
            {name: "panel", opacity: Theme.glassTintOpacity},
            {name: "taskbar", opacity: Theme.taskbarTintOpacity}
        ];
        const fills = [
            {name: "glass", colour: Theme.glassTint, alpha: 0},
            {name: "tileGlass", colour: Theme.tileGlass, alpha: Theme.tileGlass.a},
            {name: "glassButton", colour: Theme.glassButton, alpha: Theme.glassButton.a},
            {name: "glassButtonActive", colour: Theme.glassButtonActive, alpha: Theme.glassButtonActive.a},
            {name: "glassButtonPressed", colour: Theme.glassButtonPressed, alpha: Theme.glassButtonPressed.a}
        ];
        const rows = [];
        for (const glass of glasses) {
            const backdrops = [
                {name: "lightest", colour: glassOver(Theme.wallpaperLightest, glass.opacity)},
                {name: "darkest", colour: glassOver(Theme.wallpaperDarkest, glass.opacity)},
                {name: "fallback", colour: Theme.glassFallback}
            ];
            for (const backdrop of backdrops) {
                for (const fill of fills) {
                    const bg = over(fill.colour, fill.alpha, backdrop.colour);
                    const where = glass.name + "/" + fill.name + "/" + backdrop.name;
                    rows.push({tag: "text/" + where, fg: Theme.text, bg: bg, min: 4.5});
                    rows.push({tag: "secondary/" + where, fg: Theme.textSecondary, bg: bg, min: 4.5});
                    // Tertiary text is used on panels; on the taskbar only as a mark.
                    rows.push({tag: "tertiary/" + where, fg: Theme.textTertiary, bg: bg,
                               min: glass.name === "panel" ? 4.5 : 3});
                    rows.push({tag: "ring/" + where, fg: Theme.focusRing, bg: bg, min: 3});
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
        const panel = over(Theme.glassButtonPressed, Theme.glassButtonPressed.a,
                           glassOver(Theme.wallpaperLightest, Theme.glassTintOpacity));
        const taskbar = over(Theme.glassButtonPressed, Theme.glassButtonPressed.a,
                             glassOver(Theme.wallpaperLightest, Theme.taskbarTintOpacity));
        console.info("STAROS-TEST glass panel pressed=" + panel + " text=" + contrast(Theme.text, panel).toFixed(2)
            + " taskbar pressed=" + taskbar + " text=" + contrast(Theme.text, taskbar).toFixed(2));
        fuzzyCompare(contrast(Theme.text, panel), 7.42, 0.01);
        fuzzyCompare(contrast(Theme.textSecondary, panel), 5.41, 0.01);
        fuzzyCompare(contrast(Theme.textTertiary, panel), 4.81, 0.01);
        fuzzyCompare(contrast(Theme.focusRing, panel), 4.57, 0.01);
        fuzzyCompare(contrast(Theme.text, taskbar), 6.34, 0.01);
        fuzzyCompare(contrast(Theme.textSecondary, taskbar), 4.63, 0.01);
        fuzzyCompare(contrast(Theme.focusRing, taskbar), 3.91, 0.01);
        fuzzyCompare(contrast(Theme.activeIndicator, taskbar), 3.86, 0.01);
        fuzzyCompare(contrast(Theme.textTertiary, taskbar), 4.11, 0.01);
    }

    function test_opaque_colours_are_distinct() {
        const colours = [Theme.desktop, Theme.taskbar, Theme.taskbarButton, Theme.launcherBackdrop,
            Theme.tile, Theme.monogram, Theme.searchField, Theme.focusRing, Theme.activeIndicator,
            Theme.glassFallback, Theme.accent, Theme.accentEnd];
        for (let i = 0; i < colours.length; ++i) {
            for (let j = i + 1; j < colours.length; ++j) {
                verify(!Qt.colorEqual(colours[i], colours[j]), "colours " + i + " and " + j);
            }
        }
    }
}
