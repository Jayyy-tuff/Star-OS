// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QHash>
#include <QList>
#include <QString>
#include <QStringList>

// Parsers for the flatpak command line. Without a terminal, flatpak 1.18
// prints tables as tab-separated rows with no title row
// (app/flatpak-table-printer.c), in the order of the --columns option.
namespace FlatpakOutput
{
struct InstalledApp {
    QString id;
    QString name;
    QString version;
    QString origin;
};

// `flatpak remotes --columns=name,url`: the remote names.
QStringList remoteNames(const QString &output);

// `flatpak list --app --columns=application,name,version,origin`.
QList<InstalledApp> installedApps(const QString &output);

// `flatpak remote-ls --updates --app --columns=application,version`:
// app id -> available version.
QHash<QString, QString> updates(const QString &output);

// `flatpak remote-info --show-metadata`: the app's sandbox permissions as
// short sentences for people, from [Context] and the bus policies.
QStringList permissions(const QString &metadata);

// A Flatpak application id (reverse DNS, at least three parts). Anything else
// is never passed to flatpak, so it cannot be read as an option or a path.
bool isValidAppId(const QString &id);
}
