// SPDX-License-Identifier: GPL-3.0-or-later
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import StarOS.Shell

// Icons: the app id to artwork mapping, every artwork file loading through
// Qt's SVG image plugin, and AppIcon's artwork or monogram fallback.
Item {
    id: root

    width: 400
    height: 300

    AppIcon {
        id: icon
        x: 0
        y: 0
        width: 64
        height: 64
    }

    Component {
        id: fallbackComponent

        Rectangle {
            objectName: "fallbackIcon"
            property var iconData
            color: "magenta"
        }
    }

    Component {
        id: imageComponent

        Image {
            width: 64
            height: 64
            sourceSize: Qt.size(64, 64)
        }
    }

    TestCase {
        name: "Icons"
        when: windowShown

        // One id per artwork file.
        readonly property var artworkIds: ["org.kde.konsole", "systemsettings", "org.staros.files",
            "org.staros.sunstore", "moon-browser", "org.staros.lens", "org.staros.storage"]

        function init() {
            icon.fallback = null;
            icon.iconData = undefined;
            icon.appId = "";
            icon.name = "";
        }

        function test_source_data() {
            return [
                {tag: "org.kde.konsole", id: "org.kde.konsole", file: "terminal.svg"},
                {tag: "org.kde.konsole.desktop", id: "org.kde.konsole.desktop", file: "terminal.svg"},
                {tag: "systemsettings", id: "systemsettings", file: "settings.svg"},
                {tag: "systemsettings.desktop", id: "systemsettings.desktop", file: "settings.svg"},
                {tag: "org.kde.systemsettings", id: "org.kde.systemsettings", file: "settings.svg"},
                {tag: "org.staros.files", id: "org.staros.files", file: "files.svg"},
                {tag: "org.staros.files.desktop", id: "org.staros.files.desktop", file: "files.svg"},
                {tag: "org.staros.sunstore", id: "org.staros.sunstore", file: "sun-store.svg"},
                {tag: "org.staros.sunstore.desktop", id: "org.staros.sunstore.desktop", file: "sun-store.svg"},
                {tag: "org.staros.lens.desktop", id: "org.staros.lens.desktop", file: "lens.svg"},
                {tag: "org.staros.storage", id: "org.staros.storage", file: "storage.svg"},
                {tag: "org.staros.games.desktop", id: "org.staros.games.desktop", file: "games.svg"},
                {tag: "org.staros.welcome.desktop", id: "org.staros.welcome.desktop", file: "welcome.svg"},
                {tag: "firefox.desktop (theme icon)", id: "firefox.desktop", file: ""},
                {tag: "moon", id: "moon", file: "moon-browser.svg"},
                {tag: "moon-browser", id: "moon-browser", file: "moon-browser.svg"},
                {tag: "org.staros.moon", id: "org.staros.moon", file: "moon-browser.svg"},
                {tag: "org.staros.moonbrowser.desktop", id: "org.staros.moonbrowser.desktop",
                 file: "moon-browser.svg"},
                {tag: "unknown id", id: "org.kde.kmenuedit.desktop", file: ""},
                {tag: "empty id", id: "", file: ""},
                {tag: "only the suffix", id: ".desktop", file: ""},
                {tag: "suffix not at the end", id: "org.kde.konsole.desktop.old", file: ""},
                {tag: "longer id", id: "x.org.kde.konsole", file: ""},
                {tag: "different case", id: "Org.KDE.Konsole", file: ""},
                {tag: "object key", id: "constructor", file: ""},
                {tag: "undefined", id: undefined, file: ""}
            ];
        }

        function test_source(data) {
            const url = String(Icons.source(data.id));
            if (data.file === "") {
                compare(url, "");
            } else {
                verify(url.endsWith("/StarOS/Shell/icons/" + data.file), url);
            }
        }

        // Qt's SVG plugin parses and renders every artwork file.
        function test_every_artwork_loads() {
            for (const id of artworkIds) {
                const image = createTemporaryObject(imageComponent, root, {source: Icons.source(id)});
                verify(image !== null);
                tryCompare(image, "status", Image.Ready, 5000, id + " artwork loads");
                verify(image.implicitWidth > 0 && image.implicitWidth === image.implicitHeight,
                       id + " artwork is square: " + image.implicitWidth + "x" + image.implicitHeight);
            }
        }

        // Every line symbol and the logo load through Qt's SVG plugin.
        function test_every_symbol_loads() {
            verify(Icons.symbols.length >= 40);
            for (const name of Icons.symbols) {
                const url = String(Icons.symbol(name));
                verify(url.endsWith("/StarOS/Shell/symbols/" + name + ".svg"), url);
                const image = createTemporaryObject(imageComponent, root, {source: url});
                tryCompare(image, "status", Image.Ready, 5000, name + " symbol loads");
                compare(image.implicitWidth, image.implicitHeight);
            }
            const logo = createTemporaryObject(imageComponent, root, {source: Icons.logo});
            tryCompare(logo, "status", Image.Ready, 5000, "the logo loads");
        }

        function test_unknown_symbols() {
            compare(String(Icons.symbol("no-such-symbol")), "");
            compare(String(Icons.symbol("")), "");
            compare(String(Icons.symbol("constructor")), "");
            compare(String(Icons.symbol(undefined)), "");
        }

        function test_artwork_for_a_known_id() {
            icon.appId = "org.staros.files.desktop";
            icon.name = "Files";
            const artwork = findChild(icon, "artwork");
            const monogram = findChild(icon, "monogram");
            tryCompare(artwork, "status", Image.Ready, 5000, "the Files artwork loads");
            verify(artwork.visible && !monogram.visible);
            // Rendered at the shown size, so it is crisp.
            compare(artwork.sourceSize.width, 64);
            compare(artwork.sourceSize.height, 64);
            // Rendered: the white folder front at the centre, the blue glass
            // tile left of it (device pixels, see tst_launcher.qml).
            waitForRendering(root);
            const img = grabImage(root);
            const dpr = Screen.devicePixelRatio;
            const c = Math.floor(32 * dpr);
            const x = Math.floor(9 * dpr);
            verify(c < img.width && c < img.height);
            verify(img.red(c, c) > 200 && img.green(c, c) > 200 && img.blue(c, c) > 200,
                   "folder front at the centre: " + img.pixel(c, c));
            verify(img.blue(x, c) - img.red(x, c) > 60, "blue tile at the left: " + img.pixel(x, c));
        }

        function test_monogram_for_an_unknown_id() {
            icon.appId = "org.example.unknown";
            icon.name = "example";
            const monogram = findChild(icon, "monogram");
            verify(monogram.visible);
            verify(!findChild(icon, "artwork").visible);
            verify(Qt.colorEqual(monogram.color, Theme.monogram));
            compare(findChild(icon, "monogramLetter").text, "E");
            icon.name = "";
            compare(findChild(icon, "monogramLetter").text, "");
        }

        function test_switching_ids() {
            const artwork = findChild(icon, "artwork");
            const monogram = findChild(icon, "monogram");
            icon.name = "Konsole";
            icon.appId = "org.kde.konsole";
            tryCompare(artwork, "status", Image.Ready, 5000);
            verify(!monogram.visible);
            icon.appId = "nothing";
            verify(monogram.visible && !artwork.visible);
            icon.appId = "org.kde.konsole.desktop";
            tryCompare(artwork, "status", Image.Ready, 5000);
            verify(artwork.visible && !monogram.visible);
        }

        // An app without Star OS artwork shows the host's fallback with its
        // iconData; without iconData it keeps the monogram.
        function test_fallback_component() {
            icon.appId = "firefox.desktop";
            icon.name = "Firefox";
            icon.fallback = fallbackComponent;
            icon.iconData = "firefox";
            tryVerify(() => icon.usesFallback, 5000, "the fallback is loaded");
            const item = findChild(icon, "fallbackIcon");
            verify(item !== null);
            compare(item.iconData, "firefox");
            verify(!findChild(icon, "monogram").visible);
            icon.iconData = undefined;
            tryVerify(() => !icon.usesFallback, 5000, "no iconData, no fallback");
            verify(findChild(icon, "monogram").visible);
            // Star OS artwork wins over the fallback.
            icon.iconData = "files";
            icon.appId = "org.staros.files";
            tryCompare(findChild(icon, "artwork"), "status", Image.Ready, 5000);
            verify(!icon.usesFallback);
            icon.fallback = null;
            icon.iconData = undefined;
        }

        function test_decorative() {
            compare(icon.Accessible.ignored, true);
        }
    }
}
