// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QStringList>

// "Star picks" (M0.4): free and open-source Flathub apps that Star OS
// suggests first, beyond the apps preinstalled on the ISO. Ids that Flathub
// does not list are simply not shown. Changed in reviewed changes only.
namespace StarPicks
{
inline const QString CategoryId = QStringLiteral("starpicks");

inline const QStringList AppIds = {
    QStringLiteral("org.libreoffice.LibreOffice"),
    QStringLiteral("org.gimp.GIMP"),
    QStringLiteral("org.inkscape.Inkscape"),
    QStringLiteral("org.kde.krita"),
    QStringLiteral("org.blender.Blender"),
    QStringLiteral("org.audacityteam.Audacity"),
    QStringLiteral("org.kde.kdenlive"),
    QStringLiteral("com.obsproject.Studio"),
    QStringLiteral("org.mozilla.Thunderbird"),
    QStringLiteral("org.keepassxc.KeePassXC"),
    QStringLiteral("com.github.johnfactotum.Foliate"),
    QStringLiteral("org.qbittorrent.qBittorrent"),
    QStringLiteral("com.github.tchx84.Flatseal"),
    QStringLiteral("net.supertuxkart.SuperTuxKart"),
};
}
