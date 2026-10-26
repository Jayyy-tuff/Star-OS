// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>

#include <KConfigWatcher>
#include <KSharedConfig>

// Game Center's game mode (ADR-0017) for quick settings: whether GameMode is
// installed and whether games started from Game Center use it. Kept in
// ~/.config/staros-gamesrc [General] GameMode, which Game Center reads too.
class GameModeSetting : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit GameModeSetting(QObject *parent = nullptr);

    bool available() const;
    bool enabled() const;
    void setEnabled(bool enabled);

Q_SIGNALS:
    void enabledChanged();

private:
    void read();

    KSharedConfig::Ptr m_config;
    KConfigWatcher::Ptr m_watcher;
    bool m_available = false;
    bool m_enabled = false;
};
