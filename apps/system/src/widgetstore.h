// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QVariantMap>

// The desktop widgets' settings (M0.5): which widgets are shown and the
// weather's place, as a JSON object in $XDG_DATA_HOME/staros/widgets.json
// (on Star Storage when the live medium keeps changes there). The file is
// reloaded when another process changes it.
class WidgetStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)
    Q_PROPERTY(QString filePath READ filePath WRITE setFilePath NOTIFY filePathChanged)

public:
    static constexpr qint64 MaxFileSize = 64 * 1024;

    explicit WidgetStore(QObject *parent = nullptr);

    QVariantMap values() const;
    QString filePath() const;
    void setFilePath(const QString &filePath);

    Q_INVOKABLE QVariant value(const QString &key, const QVariant &fallback = QVariant()) const;
    // Saves at once; an undefined value removes the key.
    Q_INVOKABLE void setValue(const QString &key, const QVariant &value);
    Q_INVOKABLE void reload();

Q_SIGNALS:
    void valuesChanged();
    void filePathChanged();

private:
    bool save();
    void watch();

    QString m_filePath;
    QVariantMap m_values;
    QFileSystemWatcher m_watcher;
};
