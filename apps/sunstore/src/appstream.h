// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QList>
#include <QString>
#include <QStringList>

class QIODevice;

// One desktop application from a Flathub AppStream catalogue.
struct CatalogueApp {
    QString id;
    QString name;
    QString summary;
    QString description; // paragraphs separated by blank lines, list items as "• "
    QString iconPath; // a cached icon file, or empty
    QString developer;
    QString license;
    QString version; // the newest release listed
    QStringList categories;
    bool verified = false; // Flathub's developer verification
};

namespace AppStream
{
// Parses a catalogue (the <components> document flatpak checks out). Only
// desktop applications are returned, with their untranslated texts. Cached
// icon names are resolved in iconDir/128x128 and then iconDir/64x64.
QList<CatalogueApp> parse(QIODevice *device, const QString &iconDir);

// Reads the catalogue of one remote from flatpak's "active" checkout:
// appstream.xml, or appstream.xml.gz from older flatpak releases.
QList<CatalogueApp> loadActive(const QString &activeDir);
}
