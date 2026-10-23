// SPDX-License-Identifier: GPL-3.0-or-later
#include "store.h"

#include "appstream.h"
#include "flatpakoutput.h"

#include <QDir>
#include <QProcess>
#include <QStandardPaths>
#include <QSysInfo>

namespace
{
const QString Flathub = QStringLiteral("flathub");
const QString User = QStringLiteral("--user");
}

Store::Store(QObject *parent)
    : Store(QStringLiteral("flatpak"),
            QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/flatpak"),
            QStringLiteral(STAROS_SUNSTORE_FLATHUB_REPO),
            parent)
{
}

Store::Store(const QString &program, const QString &dataDir, const QString &flathubRepoFile, QObject *parent)
    : QObject(parent)
    , m_cli(new FlatpakCli(program, this))
    , m_apps(new AppsModel(this))
    , m_dataDir(dataDir)
    , m_flathubRepoFile(flathubRepoFile)
{
}

QString Store::state() const
{
    return m_state;
}

bool Store::offline() const
{
    return m_offline;
}

QString Store::errorString() const
{
    return m_errorString;
}

bool Store::busy() const
{
    return !m_operation.isEmpty();
}

QString Store::operation() const
{
    return m_operation;
}

QString Store::busyAppId() const
{
    return m_busyAppId;
}

QString Store::progressText() const
{
    return m_progressText;
}

AppsModel *Store::apps() const
{
    return m_apps;
}

QString Store::flatpakArch()
{
    const QString arch = QSysInfo::currentCpuArchitecture();
    if (arch == QLatin1String("arm64")) {
        return QStringLiteral("aarch64");
    }
    if (arch == QLatin1String("arm")) {
        return QStringLiteral("arm");
    }
    return arch;
}

void Store::setState(const QString &state)
{
    if (state != m_state) {
        m_state = state;
        Q_EMIT stateChanged();
    }
}

void Store::setOffline(bool offline)
{
    if (offline != m_offline) {
        m_offline = offline;
        Q_EMIT offlineChanged();
    }
}

void Store::setErrorString(const QString &text)
{
    if (text != m_errorString) {
        m_errorString = text;
        Q_EMIT errorStringChanged();
    }
}

void Store::setBusy(const QString &operation, const QString &appId)
{
    if (operation != m_operation || appId != m_busyAppId) {
        m_operation = operation;
        m_busyAppId = appId;
        Q_EMIT busyChanged();
    }
    setProgressText(QString());
}

void Store::setProgressText(const QString &text)
{
    if (text != m_progressText) {
        m_progressText = text;
        Q_EMIT progressTextChanged();
    }
}

void Store::start()
{
    if (m_state != QLatin1String("starting") && m_state != QLatin1String("error")) {
        return;
    }
    setState(QStringLiteral("starting"));
    m_cli->run({QStringLiteral("remotes"), User, QStringLiteral("--columns=name,url")}, [this](const FlatpakCli::Result &result) {
        if (!result.ok()) {
            setErrorString(result.message());
            setState(QStringLiteral("error"));
            return;
        }
        if (!FlatpakOutput::remoteNames(result.output).contains(Flathub)) {
            setState(QStringLiteral("needsConsent"));
            return;
        }
        // Show what an earlier download left while the new one runs.
        loadCatalogue();
        setState(m_apps->catalogueSize() > 0 ? QStringLiteral("ready") : QStringLiteral("loading"));
        loadInstalled();
        refresh();
    });
}

void Store::enableFlathub()
{
    if (m_state != QLatin1String("needsConsent") || busy()) {
        return;
    }
    setState(QStringLiteral("loading"));
    setBusy(QStringLiteral("enable"), QString());
    m_cli->run({QStringLiteral("remote-add"), User, QStringLiteral("--if-not-exists"), Flathub, m_flathubRepoFile},
               [this](const FlatpakCli::Result &result) {
                   setBusy(QString(), QString());
                   if (!result.ok()) {
                       setErrorString(result.message());
                       setState(QStringLiteral("error"));
                       return;
                   }
                   loadInstalled();
                   refresh();
               });
}

void Store::refresh()
{
    if (busy() || m_state == QLatin1String("needsConsent") || m_state == QLatin1String("starting")) {
        return;
    }
    if (m_apps->catalogueSize() == 0) {
        setState(QStringLiteral("loading"));
    }
    setBusy(QStringLiteral("refresh"), QString());
    setProgressText(tr("Updating the app list…"));
    m_cli->run({QStringLiteral("update"), User, QStringLiteral("--appstream"), Flathub}, [this](const FlatpakCli::Result &result) {
        loadCatalogue();
        if (result.ok()) {
            setOffline(false);
            setErrorString(QString());
            setState(QStringLiteral("ready"));
        } else {
            setOffline(true);
            setErrorString(result.message());
            setState(m_apps->catalogueSize() > 0 ? QStringLiteral("ready") : QStringLiteral("offline"));
        }
        loadInstalled([this] {
            setBusy(QString(), QString());
        });
    });
}

void Store::loadCatalogue()
{
    const QString active = QDir(m_dataDir).filePath(QStringLiteral("appstream/%1/%2/active").arg(Flathub, flatpakArch()));
    m_apps->setCatalogue(AppStream::loadActive(active));
}

void Store::loadInstalled(std::function<void()> done)
{
    // Only the newest load's answers are used, so an older, slower one cannot
    // overwrite them.
    const int generation = ++m_loadGeneration;
    m_cli->run({QStringLiteral("list"), User, QStringLiteral("--app"), QStringLiteral("--columns=application,name,version,origin")},
               [this, done, generation](const FlatpakCli::Result &installed) {
                   if (installed.ok() && generation == m_loadGeneration) {
                       m_apps->setInstalled(FlatpakOutput::installedApps(installed.output));
                   }
                   m_cli->run({QStringLiteral("remote-ls"), User, QStringLiteral("--updates"), QStringLiteral("--app"),
                               QStringLiteral("--columns=application,version")},
                              [this, done, generation](const FlatpakCli::Result &updates) {
                                  // Without network there is no update list; keep the last one.
                                  if (updates.ok() && generation == m_loadGeneration) {
                                      m_apps->setUpdates(FlatpakOutput::updates(updates.output));
                                  }
                                  if (done) {
                                      done();
                                  }
                              });
               });
}

bool Store::change(const QString &operation, const QString &appId, const QStringList &arguments)
{
    if (busy() || (!appId.isEmpty() && !FlatpakOutput::isValidAppId(appId))) {
        return false;
    }
    setBusy(operation, appId);
    m_cli->run(
        arguments,
        [this, operation, appId](const FlatpakCli::Result &result) {
            const QString message = result.ok() ? QString() : result.message();
            loadInstalled([this, operation, appId, message] {
                setBusy(QString(), QString());
                if (message.isEmpty()) {
                    Q_EMIT operationFinished(operation, appId);
                } else {
                    Q_EMIT operationFailed(operation, appId, message);
                }
            });
        },
        [this](const QString &line) {
            setProgressText(line.simplified());
        });
    return true;
}

bool Store::install(const QString &appId)
{
    if (appId.isEmpty() || m_state != QLatin1String("ready")) {
        return false;
    }
    return change(QStringLiteral("install"),
                  appId,
                  {QStringLiteral("install"), User, QStringLiteral("--noninteractive"), QStringLiteral("-y"), Flathub, appId});
}

bool Store::remove(const QString &appId)
{
    if (appId.isEmpty()) {
        return false;
    }
    return change(QStringLiteral("remove"), appId, {QStringLiteral("uninstall"), User, QStringLiteral("--noninteractive"), QStringLiteral("-y"), appId});
}

bool Store::updateAll()
{
    return change(QStringLiteral("update"), QString(), {QStringLiteral("update"), User, QStringLiteral("--noninteractive"), QStringLiteral("-y")});
}

bool Store::open(const QString &appId)
{
    if (!FlatpakOutput::isValidAppId(appId) || !m_apps->isInstalled(appId)) {
        return false;
    }
    return m_cli->startDetached({QStringLiteral("run"), appId});
}

bool Store::openStarStorage()
{
    return QProcess::startDetached(QStringLiteral("/usr/bin/staros-storage"), {});
}

void Store::requestPermissions(const QString &appId)
{
    if (!FlatpakOutput::isValidAppId(appId)) {
        Q_EMIT permissionsFailed(appId, tr("“%1” is not a Flatpak app id.").arg(appId));
        return;
    }
    m_cli->run({QStringLiteral("remote-info"), User, QStringLiteral("--show-metadata"), Flathub, appId}, [this, appId](const FlatpakCli::Result &result) {
        if (result.ok()) {
            Q_EMIT permissionsReady(appId, FlatpakOutput::permissions(result.output));
        } else {
            Q_EMIT permissionsFailed(appId, result.message());
        }
    });
}
