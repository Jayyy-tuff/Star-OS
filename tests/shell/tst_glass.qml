// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Frosted glass: the opaque fallback under the software scene graph (which the
// CI unit tests use) and with reduceTransparency, the geometry the taskbar
// passes to its glass, and the wallpaper rendering between the darkest and
// lightest colours that the contrast checks assume.
Item {
    id: root

    width: 640
    height: 720

    GlassSurface {
        id: glass
        x: 0
        y: 0
        width: 200
        height: 100
    }

    ListModel {
        id: noWindows
    }

    Taskbar {
        id: taskbar
        x: 0
        y: 120
        width: 300
        height: Theme.taskbarHeight
        tasksModel: noWindows
    }

    Image {
        id: wallpaper
        x: 0
        y: 200
        width: 192
        height: 108
        source: Theme.wallpaper
        sourceSize: Qt.size(192, 108)
    }

    Component {
        id: taskbarComponent

        Taskbar {
            width: 300
            height: Theme.taskbarHeight
        }
    }

    TestCase {
        name: "Glass"
        when: windowShown

        function cleanup() {
            Theme.reduceTransparency = false;
        }

        // Device pixels of the window, as grabImage(root) returns them (see
        // tst_launcher.qml); the point must lie inside that crop.
        function expectColour(img, x, y, colour, what) {
            const dpr = Screen.devicePixelRatio;
            const dx = Math.floor(x * dpr);
            const dy = Math.floor(y * dpr);
            verify(dx < img.width && dy < img.height, what + " inside the grabbed image");
            const ok = Math.abs(img.red(dx, dy) - colour.r * 255) <= 2
                && Math.abs(img.green(dx, dy) - colour.g * 255) <= 2
                && Math.abs(img.blue(dx, dy) - colour.b * 255) <= 2;
            verify(ok, what + ": " + img.pixel(dx, dy) + ", expected " + colour);
        }

        function gpu() {
            return glass.GraphicsInfo.api !== GraphicsInfo.Software
                && glass.GraphicsInfo.api !== GraphicsInfo.Unknown;
        }

        function test_defaults() {
            console.info("STAROS-TEST glass api=" + glass.GraphicsInfo.api
                + " blurAvailable=" + glass.blurAvailable);
            compare(glass.radius, Theme.glassRadius);
            compare(glass.screenSize.width, glass.width);
            compare(glass.screenSize.height, glass.height);
            compare(glass.wallpaperOrigin.x, 0);
            compare(glass.wallpaperOrigin.y, 0);
            compare(glass.Accessible.ignored, true);
            compare(glass.blurAvailable, gpu());
        }

        function test_software_scene_graph_draws_the_fallback() {
            if (glass.GraphicsInfo.api !== GraphicsInfo.Software) {
                skip("not the software scene graph");
            }
            verify(!glass.blurAvailable);
            const fallback = findChild(glass, "glassFallback");
            verify(fallback !== null && fallback.visible);
            verify(Qt.colorEqual(fallback.color, Theme.glassFallback));
            compare(fallback.radius, glass.radius);
            waitForRendering(root);
            const img = grabImage(root);
            expectColour(img, 100, 50, Theme.glassFallback, "glass centre");
            expectColour(img, glass.radius, 2, Theme.glassFallback, "glass top edge");
        }

        function test_reduce_transparency() {
            Theme.reduceTransparency = true;
            verify(!glass.blurAvailable);
            verify(findChild(glass, "glassFallback").visible);
            waitForRendering(root);
            expectColour(grabImage(root), 100, 50, Theme.glassFallback, "glass centre");
            Theme.reduceTransparency = false;
            compare(glass.blurAvailable, gpu());
            compare(findChild(glass, "glassFallback").visible, !gpu());
        }

        // The taskbar's glass sticks out by a pixel left, right and below, so
        // only its top edge shows at the screen edges; its wallpaper origin
        // moves with it.
        function test_taskbar_glass_geometry() {
            compare(taskbar.glassOrigin.x, 0);
            compare(taskbar.glassOrigin.y, Screen.height - taskbar.height);
            compare(taskbar.glassScreenSize.width, Screen.width);
            compare(taskbar.glassScreenSize.height, Screen.height);
            const surface = findChild(taskbar, "glass");
            verify(surface !== null);
            compare(surface.radius, 0);
            compare(surface.x, -1);
            compare(surface.y, 0);
            compare(surface.width, taskbar.width + 2);
            compare(surface.height, taskbar.height + 1);
            compare(surface.wallpaperOrigin.x, taskbar.glassOrigin.x - 1);
            compare(surface.wallpaperOrigin.y, taskbar.glassOrigin.y);
            compare(surface.screenSize.width, Screen.width);
            compare(surface.screenSize.height, Screen.height);

            const placed = createTemporaryObject(taskbarComponent, root,
                {glassOrigin: Qt.point(12, 700), glassScreenSize: Qt.size(1280, 800)});
            const placedGlass = findChild(placed, "glass");
            compare(placedGlass.wallpaperOrigin.x, 11);
            compare(placedGlass.wallpaperOrigin.y, 700);
            compare(placedGlass.screenSize.width, 1280);
            compare(placedGlass.screenSize.height, 800);
        }

        function test_taskbar_background_pixels() {
            if (gpu()) {
                skip("the blurred wallpaper has no fixed colour");
            }
            waitForRendering(root);
            const img = grabImage(root);
            // Corners left free by the Applications and Leave buttons.
            expectColour(img, 1, taskbar.y + 1, Theme.glassFallback, "taskbar top left");
            expectColour(img, taskbar.width - 2, taskbar.y + 1, Theme.glassFallback, "taskbar top right");
        }

        // Qt's SVG plugin renders the wallpaper, and every rendered colour lies
        // between wallpaperDarkest and wallpaperLightest, channel by channel.
        function test_wallpaper_stays_between_its_bounds() {
            tryCompare(wallpaper, "status", Image.Ready, 10000, "the wallpaper loads");
            waitForRendering(root);
            const img = grabImage(root);
            const dpr = Screen.devicePixelRatio;
            const low = Theme.wallpaperDarkest;
            const high = Theme.wallpaperLightest;
            let minBlue = 255;
            let maxBlue = 0;
            for (let gx = 0; gx < 12; ++gx) {
                for (let gy = 0; gy < 6; ++gy) {
                    // Inner points only: the image's own edge pixels are blended
                    // with the window background.
                    const x = Math.floor((wallpaper.x + 4 + gx * (wallpaper.width - 8) / 11) * dpr);
                    const y = Math.floor((wallpaper.y + 4 + gy * (wallpaper.height - 8) / 5) * dpr);
                    verify(x < img.width && y < img.height, "sample inside the grabbed image");
                    const r = img.red(x, y);
                    const g = img.green(x, y);
                    const b = img.blue(x, y);
                    const where = "(" + x + ", " + y + ") " + img.pixel(x, y);
                    verify(r >= low.r * 255 - 2 && r <= high.r * 255 + 2, "red at " + where);
                    verify(g >= low.g * 255 - 2 && g <= high.g * 255 + 2, "green at " + where);
                    verify(b >= low.b * 255 - 2 && b <= high.b * 255 + 2, "blue at " + where);
                    minBlue = Math.min(minBlue, b);
                    maxBlue = Math.max(maxBlue, b);
                }
            }
            // Not a flat colour: the artwork itself was drawn.
            verify(maxBlue - minBlue > 20, "the wallpaper varies: blue " + minBlue + ".." + maxBlue);
        }
    }
}
