// SPDX-License-Identifier: GPL-3.0-or-later
#include "gamelibrary.h"
#include "steamlibrary.h"

#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>

#include <KConfig>
#include <KConfigGroup>
#include <KIO/ApplicationLauncherJob>
#include <KIO/CommandLauncherJob>
#include <KIO/DesktopExecParser>
#include <KIO/OpenUrlJob>
#include <KService>
#include <KSycoca>

#include <algorithm>

namespace
{
const QString OwnId = QStringLiteral("org.staros.games.desktop");
const QStringList SteamClients{QStringLiteral("steam.desktop"), QStringLiteral("com.valvesoftware.Steam.desktop")};
}

GameLibrary::GameLibrary(QObject *parent)
    : QAbstractListModel(parent)
    , m_steamRoots(SteamLibrary::defaultRoots(QDir::homePath()))
    , m_gameModeAvailable(!QStandardPaths::findExecutable(QStringLiteral("gamemoderun")).isEmpty())
    // A name, not a path: KConfig finds it in ~/.config, and quick settings
    // (StarOS.System's GameModeSetting) is told when it changes.
    , m_configPath(QStringLiteral("staros-gamesrc"))
{
    m_launcher = [this](const QString &kind, const QString &target, bool gameMode) {
        return defaultLaunch(kind, target, gameMode);
    };
    m_processTimer.setInterval(5000);
    connect(&m_processTimer, &QTimer::timeout, this, &GameLibrary::checkProcesses);
    // A game installed or removed while Game Center is open.
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &GameLibrary::reload);
    readConfig();
    reload();
}

int GameLibrary::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant GameLibrary::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    const Entry &entry = m_all.at(m_rows.at(index.row()));
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return entry.name;
    case GameIdRole:
        return entry.gameId;
    case SourceRole:
        return entry.source;
    case EmulatorRole:
        return entry.emulator;
    case Qt::DecorationRole:
    case IconRole:
        return entry.icon;
    case LastPlayedRole:
        return entry.lastPlayed;
    }
    return {};
}

QHash<int, QByteArray> GameLibrary::roleNames() const
{
    return {
        {NameRole, "name"},
        {GameIdRole, "gameId"},
        {SourceRole, "source"},
        {EmulatorRole, "emulator"},
        {IconRole, "icon"},
        {LastPlayedRole, "lastPlayed"},
    };
}

int GameLibrary::totalCount() const
{
    return int(m_all.size());
}

QString GameLibrary::filter() const
{
    return m_filter;
}

void GameLibrary::setFilter(const QString &filter)
{
    static const QStringList known{QStringLiteral("all"), QStringLiteral("steam"), QStringLiteral("apps"), QStringLiteral("emulators")};
    const QString next = known.contains(filter) ? filter : QStringLiteral("all");
    if (next == m_filter) {
        return;
    }
    m_filter = next;
    applyFilter();
    Q_EMIT filterChanged();
}

QString GameLibrary::search() const
{
    return m_search;
}

void GameLibrary::setSearch(const QString &search)
{
    if (search == m_search) {
        return;
    }
    m_search = search;
    applyFilter();
    Q_EMIT searchChanged();
}

QString GameLibrary::steamDesktopId() const
{
    return m_steamDesktopId;
}

bool GameLibrary::gameModeAvailable() const
{
    return m_gameModeAvailable;
}

bool GameLibrary::gameMode() const
{
    return m_gameModeAvailable && m_gameMode;
}

void GameLibrary::setGameMode(bool on)
{
    if (on == m_gameMode) {
        return;
    }
    m_gameMode = on;
    KConfig config(m_configPath, KConfig::SimpleConfig);
    config.group(QStringLiteral("General")).writeEntry("GameMode", on, KConfig::Notify);
    config.sync();
    Q_EMIT gameModeChanged();
}

int GameLibrary::running() const
{
    return int(m_pids.size());
}

void GameLibrary::readConfig()
{
    KConfig config(m_configPath, KConfig::SimpleConfig);
    m_gameMode = config.group(QStringLiteral("General")).readEntry("GameMode", false);
    m_played.clear();
    const KConfigGroup played = config.group(QStringLiteral("Played"));
    const QStringList keys = played.keyList();
    for (const QString &key : keys) {
        const QDateTime time = played.readEntry(key, QDateTime());
        if (time.isValid()) {
            m_played.insert(key, time);
        }
    }
}

bool GameLibrary::matches(const Entry &entry, const QString &filter, const QString &search)
{
    if (filter == QLatin1String("steam") && entry.source != QLatin1String("steam")) {
        return false;
    }
    if (filter == QLatin1String("apps") && (entry.source == QLatin1String("steam") || entry.emulator)) {
        return false;
    }
    if (filter == QLatin1String("emulators") && !entry.emulator) {
        return false;
    }
    return search.trimmed().isEmpty() || entry.name.contains(search.trimmed(), Qt::CaseInsensitive);
}

void GameLibrary::applyFilter()
{
    QList<int> rows;
    for (qsizetype i = 0; i < m_all.size(); ++i) {
        if (matches(m_all.at(i), m_filter, m_search)) {
            rows.append(int(i));
        }
    }
    if (rows == m_rows) {
        return;
    }
    beginResetModel();
    m_rows = rows;
    endResetModel();
    Q_EMIT countChanged();
}

void GameLibrary::reload()
{
    KSycoca::self()->ensureCacheValid();
    QList<Entry> entries;
    QSet<QString> steamApps;
    QString steamClient;
    static const QRegularExpression steamRun(QStringLiteral("steam://rungameid/(\\d+)"));
    const KService::List services = KService::allServices();
    for (const KService::Ptr &service : services) {
        if (!service || !service->isApplication() || service->noDisplay() || !service->showInCurrentDesktop()
            || !service->showOnCurrentPlatform()) {
            continue;
        }
        const QString id = service->storageId();
        if (SteamClients.contains(id)) {
            if (steamClient.isEmpty()) {
                steamClient = id;
            }
            continue;
        }
        const QStringList categories = service->categories();
        if (id == OwnId || !categories.contains(QLatin1String("Game"))) {
            continue;
        }
        Entry entry;
        entry.name = service->name();
        entry.gameId = id;
        entry.emulator = categories.contains(QLatin1String("Emulator"));
        entry.icon = service->icon();
        QString path = service->entryPath();
        if (QDir::isRelativePath(path)) {
            path = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, path);
        }
        const QRegularExpressionMatch match = steamRun.match(service->exec());
        if (match.hasMatch()) {
            entry.source = QStringLiteral("steam");
            steamApps.insert(match.captured(1));
        } else if (path.contains(QLatin1String("/flatpak/exports/"))) {
            entry.source = QStringLiteral("flatpak");
        } else {
            entry.source = QStringLiteral("app");
        }
        entry.lastPlayed = m_played.value(id);
        entries.append(entry);
    }
    const QList<SteamLibrary::Game> steamGames = SteamLibrary::scan(m_steamRoots);
    for (const SteamLibrary::Game &game : steamGames) {
        if (steamApps.contains(game.appId)) {
            continue; // Steam made a desktop entry for it
        }
        Entry entry;
        entry.name = game.name;
        entry.gameId = QStringLiteral("steam:") + game.appId;
        entry.source = QStringLiteral("steam");
        entry.icon = QStringLiteral("steam_icon_") + game.appId;
        entry.lastPlayed = std::max(game.lastPlayed, m_played.value(entry.gameId));
        entries.append(entry);
    }
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::sort(entries.begin(), entries.end(), [&collator](const Entry &a, const Entry &b) {
        return collator.compare(a.name, b.name) < 0;
    });

    beginResetModel();
    m_all = entries;
    m_steamDesktopId = steamClient;
    m_rows.clear();
    for (qsizetype i = 0; i < m_all.size(); ++i) {
        if (matches(m_all.at(i), m_filter, m_search)) {
            m_rows.append(int(i));
        }
    }
    endResetModel();
    Q_EMIT countChanged();
}

QVariantMap GameLibrary::get(int row) const
{
    if (row < 0 || row >= int(m_rows.size())) {
        return {};
    }
    const Entry &entry = m_all.at(m_rows.at(row));
    return {
        {QStringLiteral("name"), entry.name},
        {QStringLiteral("gameId"), entry.gameId},
        {QStringLiteral("source"), entry.source},
        {QStringLiteral("emulator"), entry.emulator},
        {QStringLiteral("icon"), entry.icon},
        {QStringLiteral("lastPlayed"), entry.lastPlayed},
    };
}

bool GameLibrary::launch(int row)
{
    if (row < 0 || row >= int(m_rows.size())) {
        return false;
    }
    return launchGame(m_all.at(m_rows.at(row)).gameId);
}

bool GameLibrary::launchGame(const QString &gameId)
{
    const auto it = std::find_if(m_all.begin(), m_all.end(), [&gameId](const Entry &entry) {
        return entry.gameId == gameId;
    });
    if (it == m_all.end()) {
        return false;
    }
    // Quick settings may have changed game mode since Game Center opened.
    const bool gameModeBefore = m_gameMode;
    KConfig settings(m_configPath, KConfig::SimpleConfig);
    m_gameMode = settings.group(QStringLiteral("General")).readEntry("GameMode", m_gameMode);
    if (m_gameMode != gameModeBefore) {
        Q_EMIT gameModeChanged();
    }
    const bool steam = gameId.startsWith(QLatin1String("steam:"));
    const bool started = steam ? m_launcher(QStringLiteral("url"), QStringLiteral("steam://rungameid/") + gameId.mid(6), false)
                               : m_launcher(QStringLiteral("desktop"), gameId, gameMode() && it->source == QLatin1String("app"));
    if (!started) {
        Q_EMIT launchFailed(it->name);
        return false;
    }
    const QDateTime now = QDateTime::currentDateTime();
    it->lastPlayed = now;
    m_played.insert(gameId, now);
    KConfig config(m_configPath, KConfig::SimpleConfig);
    config.group(QStringLiteral("Played")).writeEntry(gameId, now);
    config.sync();
    const qsizetype index = std::distance(m_all.begin(), it);
    const int row = int(m_rows.indexOf(int(index)));
    if (row >= 0) {
        Q_EMIT dataChanged(this->index(row), this->index(row), {LastPlayedRole});
    }
    Q_EMIT launched(gameId);
    return true;
}

bool GameLibrary::getGames()
{
    return m_launcher(QStringLiteral("command"), QStringLiteral("staros-sunstore --category Game"), false);
}

bool GameLibrary::openSteam()
{
    return !m_steamDesktopId.isEmpty() && m_launcher(QStringLiteral("desktop"), m_steamDesktopId, false);
}

bool GameLibrary::defaultLaunch(const QString &kind, const QString &target, bool gameMode)
{
    if (kind == QLatin1String("command")) {
        QStringList args = target.split(QLatin1Char(' '), Qt::SkipEmptyParts);
        if (args.isEmpty()) {
            return false;
        }
        const QString program = args.takeFirst();
        auto *job = new KIO::CommandLauncherJob(program, args);
        if (program == QLatin1String("staros-sunstore")) {
            job->setDesktopName(QStringLiteral("org.staros.sunstore"));
        }
        job->start();
        return true;
    }
    if (kind == QLatin1String("url")) {
        auto *job = new KIO::OpenUrlJob(QUrl(target));
        job->start();
        return true;
    }
    const KService::Ptr service = KService::serviceByStorageId(target);
    if (!service) {
        return false;
    }
    if (gameMode) {
        // gamemoderun asks GameMode for the game's lifetime; notifications
        // are held back until it ends.
        const QStringList args = KIO::DesktopExecParser(*service, {}).resultingArguments();
        if (args.isEmpty()) {
            return false;
        }
        auto *job = new KIO::CommandLauncherJob(QStringLiteral("gamemoderun"), args);
        job->setDesktopName(service->desktopEntryName());
        connect(job, &KJob::result, this, [this, job, name = service->name()] {
            if (job->error() != 0) {
                Q_EMIT launchFailed(name);
            } else {
                watchProcess(job->pid());
            }
        });
        job->start();
        return true;
    }
    auto *job = new KIO::ApplicationLauncherJob(service);
    connect(job, &KJob::result, this, [this, job, name = service->name()] {
        if (job->error() != 0) {
            Q_EMIT launchFailed(name);
        }
    });
    job->start();
    return true;
}

void GameLibrary::watchProcess(qint64 pid)
{
    if (pid <= 0) {
        return;
    }
    m_pids.append(pid);
    holdNotifications(true);
    m_processTimer.start();
    Q_EMIT runningChanged();
}

void GameLibrary::checkProcesses()
{
    const qsizetype before = m_pids.size();
    m_pids.removeIf([](qint64 pid) {
        return !QFileInfo::exists(QStringLiteral("/proc/%1").arg(pid));
    });
    if (m_pids.isEmpty()) {
        m_processTimer.stop();
        holdNotifications(false);
    }
    if (m_pids.size() != before) {
        Q_EMIT runningChanged();
    }
}

// Plasma's notification server holds notifications back while an
// inhibition is open; it ends when Game Center quits as well.
void GameLibrary::holdNotifications(bool hold)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected() || hold == m_inhibiting) {
        return;
    }
    m_inhibiting = hold;
    const QString service = QStringLiteral("org.freedesktop.Notifications");
    const QString path = QStringLiteral("/org/freedesktop/Notifications");
    if (!hold) {
        if (m_inhibitCookie != 0) {
            QDBusMessage message = QDBusMessage::createMethodCall(service, path, service, QStringLiteral("UnInhibit"));
            message << m_inhibitCookie;
            bus.asyncCall(message);
            m_inhibitCookie = 0;
        }
        return;
    }
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, service, QStringLiteral("Inhibit"));
    message << QStringLiteral("org.staros.games") << tr("Playing a game") << QVariantMap();
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<uint> reply = *call;
        if (!reply.isError()) {
            m_inhibitCookie = reply.value();
            if (!m_inhibiting) {
                // The game ended before the answer came.
                m_inhibiting = true;
                holdNotifications(false);
            }
        }
    });
}

void GameLibrary::setSteamRoots(const QStringList &roots)
{
    m_steamRoots = roots;
    reload();
}

void GameLibrary::setLauncher(Launcher launcher)
{
    m_launcher = std::move(launcher);
}

void GameLibrary::setGameModeAvailable(bool available)
{
    m_gameModeAvailable = available;
}

void GameLibrary::setConfigPath(const QString &path)
{
    m_configPath = path;
    readConfig();
    reload();
    Q_EMIT gameModeChanged();
}
