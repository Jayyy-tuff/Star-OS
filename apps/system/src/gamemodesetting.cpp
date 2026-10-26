// SPDX-License-Identifier: GPL-3.0-or-later
#include "gamemodesetting.h"

#include <QStandardPaths>

#include <KConfigGroup>

GameModeSetting::GameModeSetting(QObject *parent)
    : QObject(parent)
    , m_config(KSharedConfig::openConfig(QStringLiteral("staros-gamesrc"), KConfig::SimpleConfig))
    , m_watcher(KConfigWatcher::create(m_config))
    , m_available(!QStandardPaths::findExecutable(QStringLiteral("gamemoderun")).isEmpty())
{
    // Game Center changed it.
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, &GameModeSetting::read);
    read();
}

bool GameModeSetting::available() const
{
    return m_available;
}

bool GameModeSetting::enabled() const
{
    return m_enabled;
}

void GameModeSetting::setEnabled(bool enabled)
{
    if (enabled == m_enabled) {
        return;
    }
    m_enabled = enabled;
    m_config->group(QStringLiteral("General")).writeEntry("GameMode", enabled, KConfig::Notify);
    m_config->sync();
    Q_EMIT enabledChanged();
}

void GameModeSetting::read()
{
    m_config->reparseConfiguration();
    const bool enabled = m_config->group(QStringLiteral("General")).readEntry("GameMode", false);
    if (enabled != m_enabled) {
        m_enabled = enabled;
        Q_EMIT enabledChanged();
    }
}
