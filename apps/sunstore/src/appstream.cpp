// SPDX-License-Identifier: GPL-3.0-or-later
#include "appstream.h"

#include <KCompressionDevice>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QXmlStreamReader>

namespace
{
const QString VerifiedKey = QStringLiteral("flathub::verification::verified");

bool isTranslation(const QXmlStreamReader &reader)
{
    return reader.attributes().hasAttribute(QStringLiteral("xml:lang"));
}

QString text(QXmlStreamReader &reader)
{
    return reader.readElementText(QXmlStreamReader::IncludeChildElements).simplified();
}

QString iconFile(const QString &iconDir, const QString &name)
{
    if (name.isEmpty() || name.contains(QLatin1Char('/'))) {
        return {};
    }
    for (const char *size : {"128x128", "64x64"}) {
        const QString path = QDir(iconDir).filePath(QLatin1String(size) + QLatin1Char('/') + name);
        if (QFileInfo::exists(path)) {
            return path;
        }
    }
    return {};
}

// <description>: untranslated <p> and <li> texts.
QString description(QXmlStreamReader &reader)
{
    QStringList blocks;
    while (reader.readNextStartElement()) {
        const auto name = reader.name();
        if (isTranslation(reader)) {
            reader.skipCurrentElement();
        } else if (name == QLatin1String("p")) {
            const QString paragraph = text(reader);
            if (!paragraph.isEmpty()) {
                blocks.append(paragraph);
            }
        } else if (name == QLatin1String("ul") || name == QLatin1String("ol")) {
            QStringList items;
            while (reader.readNextStartElement()) {
                if (reader.name() == QLatin1String("li") && !isTranslation(reader)) {
                    items.append(QStringLiteral("• ") + text(reader));
                } else {
                    reader.skipCurrentElement();
                }
            }
            if (!items.isEmpty()) {
                blocks.append(items.join(QLatin1Char('\n')));
            }
        } else {
            reader.skipCurrentElement();
        }
    }
    return blocks.join(QStringLiteral("\n\n"));
}

CatalogueApp component(QXmlStreamReader &reader, const QString &iconDir)
{
    CatalogueApp app;
    QString icon64;
    while (reader.readNextStartElement()) {
        const auto name = reader.name();
        if (name == QLatin1String("id")) {
            app.id = text(reader);
            if (app.id.endsWith(QLatin1String(".desktop"))) {
                app.id.chop(8);
            }
        } else if (name == QLatin1String("name") && !isTranslation(reader)) {
            app.name = text(reader);
        } else if (name == QLatin1String("summary") && !isTranslation(reader)) {
            app.summary = text(reader);
        } else if (name == QLatin1String("description") && !isTranslation(reader)) {
            app.description = description(reader);
        } else if (name == QLatin1String("icon")) {
            const auto attributes = reader.attributes();
            const bool cached = attributes.value(QStringLiteral("type")) == QLatin1String("cached");
            const QString width = attributes.value(QStringLiteral("width")).toString();
            const QString file = text(reader);
            if (cached && (app.iconPath.isEmpty() || width == QLatin1String("128"))) {
                const QString path = iconFile(iconDir, file);
                if (!path.isEmpty()) {
                    app.iconPath = path;
                }
            }
        } else if (name == QLatin1String("categories")) {
            while (reader.readNextStartElement()) {
                if (reader.name() == QLatin1String("category")) {
                    app.categories.append(text(reader));
                } else {
                    reader.skipCurrentElement();
                }
            }
        } else if (name == QLatin1String("developer_name") && !isTranslation(reader)) {
            if (app.developer.isEmpty()) {
                app.developer = text(reader);
            } else {
                reader.skipCurrentElement();
            }
        } else if (name == QLatin1String("developer")) {
            // AppStream 1.0: <developer id="..."><name>...</name></developer>
            while (reader.readNextStartElement()) {
                if (reader.name() == QLatin1String("name") && !isTranslation(reader)) {
                    app.developer = text(reader);
                } else {
                    reader.skipCurrentElement();
                }
            }
        } else if (name == QLatin1String("project_license")) {
            app.license = text(reader);
        } else if (name == QLatin1String("releases")) {
            while (reader.readNextStartElement()) {
                if (reader.name() == QLatin1String("release") && app.version.isEmpty()) {
                    app.version = reader.attributes().value(QStringLiteral("version")).toString();
                }
                reader.skipCurrentElement();
            }
        } else if (name == QLatin1String("custom")) {
            while (reader.readNextStartElement()) {
                if (reader.name() == QLatin1String("value")
                    && reader.attributes().value(QStringLiteral("key")) == VerifiedKey) {
                    app.verified = text(reader) == QLatin1String("true");
                } else {
                    reader.skipCurrentElement();
                }
            }
        } else {
            reader.skipCurrentElement();
        }
    }
    if (app.name.isEmpty()) {
        app.name = app.id;
    }
    return app;
}
}

namespace AppStream
{
QList<CatalogueApp> parse(QIODevice *device, const QString &iconDir)
{
    QList<CatalogueApp> apps;
    QXmlStreamReader reader(device);
    if (!reader.readNextStartElement() || reader.name() != QLatin1String("components")) {
        return apps;
    }
    while (reader.readNextStartElement()) {
        const QString type = reader.attributes().value(QStringLiteral("type")).toString();
        if (reader.name() == QLatin1String("component")
            && (type == QLatin1String("desktop-application") || type == QLatin1String("desktop"))) {
            CatalogueApp app = component(reader, iconDir);
            if (!app.id.isEmpty()) {
                apps.append(app);
            }
        } else {
            reader.skipCurrentElement();
        }
    }
    return apps;
}

QList<CatalogueApp> loadActive(const QString &activeDir)
{
    const QDir dir(activeDir);
    const QString iconDir = dir.filePath(QStringLiteral("icons"));
    QFile plain(dir.filePath(QStringLiteral("appstream.xml")));
    if (plain.open(QIODevice::ReadOnly)) {
        return parse(&plain, iconDir);
    }
    KCompressionDevice compressed(dir.filePath(QStringLiteral("appstream.xml.gz")), KCompressionDevice::GZip);
    if (compressed.open(QIODevice::ReadOnly)) {
        return parse(&compressed, iconDir);
    }
    return {};
}
}
