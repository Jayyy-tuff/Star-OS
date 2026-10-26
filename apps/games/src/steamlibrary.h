// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QList>
#include <QString>
#include <QStringList>
#include <QVariantMap>

#include <optional>

// Steam's installed games, read from its library files (ADR-0017): the
// libraries in steamapps/libraryfolders.vdf and one appmanifest_<id>.acf per
// app. Both use Valve's KeyValues text format. Nothing here starts Steam.
namespace SteamLibrary
{
struct Game {
    QString appId;
    QString name;
    QDateTime lastPlayed;
};

// KeyValues text as nested maps; keys are lower-cased (Steam mixes cases).
QVariantMap parseKeyValues(const QByteArray &text);
// The library folders a libraryfolders.vdf lists (old and new layout).
QStringList libraryFolders(const QByteArray &libraryFoldersVdf);
// A fully installed game, or nothing for tools, runtimes and partial installs.
std::optional<Game> parseManifest(const QByteArray &acf);
// Proton, the Steam Linux Runtime and the Steamworks redistributables.
bool isTool(const QString &appId, const QString &name);
// The Steam folders of the native and the Flatpak Steam under HOME.
QStringList defaultRoots(const QString &home);
// Every installed game under the roots and their libraries, once each.
QList<Game> scan(const QStringList &roots);
}
