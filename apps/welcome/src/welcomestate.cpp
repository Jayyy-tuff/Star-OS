// SPDX-License-Identifier: GPL-3.0-or-later
#include "welcomestate.h"

#include <QStandardPaths>

#include <KConfig>
#include <KConfigGroup>
#include <KIO/ApplicationLauncherJob>
#include <KService>

WelcomeState::WelcomeState(QObject *parent)
    : QObject(parent)
    , m_configPath(defaultConfigPath())
{
    m_launcher = [](const QString &desktopId) {
        const KService::Ptr service = KService::serviceByStorageId(desktopId);
        if (!service) {
            return false;
        }
        auto *job = new KIO::ApplicationLauncherJob(service);
        job->start();
        return true;
    };
}

QString WelcomeState::defaultConfigPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/staros-welcomerc");
}

bool WelcomeState::shownBefore(const QString &configPath)
{
    KConfig config(configPath, KConfig::SimpleConfig);
    return config.group(QStringLiteral("General")).readEntry("Shown", false);
}

bool WelcomeState::shownBefore() const
{
    return shownBefore(m_configPath);
}

void WelcomeState::finish()
{
    if (shownBefore()) {
        return;
    }
    KConfig config(m_configPath, KConfig::SimpleConfig);
    config.group(QStringLiteral("General")).writeEntry("Shown", true);
    config.sync();
    Q_EMIT shownBeforeChanged();
}

bool WelcomeState::open(const QString &desktopId)
{
    if (!m_launcher(desktopId)) {
        return false;
    }
    Q_EMIT opened(desktopId);
    return true;
}

void WelcomeState::setConfigPath(const QString &path)
{
    m_configPath = path;
    Q_EMIT shownBeforeChanged();
}

void WelcomeState::setLauncher(Launcher launcher)
{
    m_launcher = std::move(launcher);
}
