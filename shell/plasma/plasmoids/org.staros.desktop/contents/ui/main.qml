// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import org.kde.plasma.plasmoid

// Star OS desktop containment (M0.2): shows only the wallpaper, which libplasma
// draws behind the containment (org.kde.color in Theme.desktop, set by the
// shell package's layout.js). No icons, no context menu, no toolbox.
ContainmentItem {
}
