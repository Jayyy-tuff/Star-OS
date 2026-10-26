// SPDX-License-Identifier: GPL-3.0-or-later
#include "widgetstore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

WidgetStore::WidgetStore(QObject *parent)
    : QObject(parent)
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &WidgetStore::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &WidgetStore::reload);
    setFilePath(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation)
                + QStringLiteral("/staros/widgets.json"));
}

QVariantMap WidgetStore::values() const
{
    return m_values;
}

QString WidgetStore::filePath() const
{
    return m_filePath;
}

void WidgetStore::setFilePath(const QString &filePath)
{
    if (filePath == m_filePath) {
        return;
    }
    if (!m_watcher.files().isEmpty()) {
        m_watcher.removePaths(m_watcher.files());
    }
    if (!m_watcher.directories().isEmpty()) {
        m_watcher.removePaths(m_watcher.directories());
    }
    m_filePath = filePath;
    // Saving replaces the file, so the folder is watched as well.
    QDir().mkpath(QFileInfo(m_filePath).absolutePath());
    Q_EMIT filePathChanged();
    reload();
}

QVariant WidgetStore::value(const QString &key, const QVariant &fallback) const
{
    return m_values.value(key, fallback);
}

void WidgetStore::setValue(const QString &key, const QVariant &value)
{
    // JavaScript objects can arrive wrapped; stored as maps and lists.
    const QVariant plain = value.metaType() == QMetaType::fromType<QJSValue>() ? value.value<QJSValue>().toVariant() : value;
    QVariantMap values = m_values;
    if (plain.isValid() && !plain.isNull()) {
        values.insert(key, plain);
    } else {
        values.remove(key);
    }
    // Compared as JSON: QML numbers and lists arrive as other variant types.
    if (QJsonObject::fromVariantMap(values) == QJsonObject::fromVariantMap(m_values)) {
        return;
    }
    m_values = QJsonObject::fromVariantMap(values).toVariantMap();
    save();
    Q_EMIT valuesChanged();
}

bool WidgetStore::save()
{
    QJsonObject root = QJsonObject::fromVariantMap(m_values);
    root.insert(QStringLiteral("version"), 1);
    QDir().mkpath(QFileInfo(m_filePath).absolutePath());
    QSaveFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    const bool ok = file.commit();
    watch();
    return ok;
}

void WidgetStore::reload()
{
    QVariantMap loaded;
    QFile file(m_filePath);
    if (file.open(QIODevice::ReadOnly) && file.size() <= MaxFileSize) {
        loaded = QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
        loaded.remove(QStringLiteral("version"));
    }
    watch();
    if (QJsonObject::fromVariantMap(loaded) == QJsonObject::fromVariantMap(m_values)) {
        return;
    }
    m_values = loaded;
    Q_EMIT valuesChanged();
}

void WidgetStore::watch()
{
    const QString directory = QFileInfo(m_filePath).absolutePath();
    if (QFileInfo::exists(directory) && !m_watcher.directories().contains(directory)) {
        m_watcher.addPath(directory);
    }
    if (QFileInfo::exists(m_filePath) && !m_watcher.files().contains(m_filePath)) {
        m_watcher.addPath(m_filePath);
    }
}
