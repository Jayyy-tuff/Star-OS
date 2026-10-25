// SPDX-License-Identifier: GPL-3.0-or-later
#include "applicationsmodel.h"

#include <QCollator>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>

#include <KIO/ApplicationLauncherJob>
#include <KSycoca>

#include <sys/stat.h>

#include <algorithm>

Q_LOGGING_CATEGORY(STAROS_APPS, "staros.apps")

namespace
{
constexpr qint64 RecentDays = 30;
constexpr qint64 NewDays = 3;
constexpr int RecentLimit = 6;

QString folded(const QString &text)
{
    return text.toCaseFolded();
}

QStringList nameWords(const QString &name)
{
    static const QRegularExpression separators(QStringLiteral("[\\s\\-_.:/]+"));
    return folded(name).split(separators, Qt::SkipEmptyParts);
}

QString sectionOf(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (trimmed.isEmpty() || !trimmed.at(0).isLetter()) {
        return QStringLiteral("#");
    }
    return trimmed.left(1).toUpper();
}

// The time of the file itself: Flatpak's exports are links into the
// deployment, whose files carry the time 0.
QDateTime linkTime(const QString &path)
{
    struct stat st;
    if (::lstat(QFile::encodeName(path).constData(), &st) != 0) {
        return {};
    }
    return QDateTime::fromSecsSinceEpoch(st.st_mtime);
}
}

ApplicationsModel::ApplicationsModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_statePath(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/staros/apps.json"))
    , m_now([] {
        return QDateTime::currentDateTime();
    })
{
    const QString kbuildsycoca = QStandardPaths::findExecutable(QStringLiteral("kbuildsycoca6"));
    if (!kbuildsycoca.isEmpty()) {
        m_rebuildCommand = {kbuildsycoca};
    }
    m_launcher = [this](const KService::Ptr &service) {
        auto *job = new KIO::ApplicationLauncherJob(service);
        connect(job, &KJob::result, this, [this, name = service->name()](KJob *job) {
            if (job->error() != 0) {
                qCWarning(STAROS_APPS) << "could not start" << name << job->errorString();
                Q_EMIT launchFailed(name, job->errorString());
            }
        });
        job->start();
        return true;
    };

    m_rebuildTimer.setSingleShot(true);
    m_rebuildTimer.setInterval(1000);
    connect(&m_rebuildTimer, &QTimer::timeout, this, &ApplicationsModel::rebuild);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &ApplicationsModel::scheduleRebuild);
    // Another process (kded, Sun Store's flatpak) rebuilt the database.
    connect(KSycoca::self(), &KSycoca::databaseChanged, this, &ApplicationsModel::reload);

    loadState();
    reload();
}

int ApplicationsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant ApplicationsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    const Entry &entry = m_entries.at(m_rows.at(index.row()));
    switch (role) {
    case Qt::DisplayRole:
    case AppNameRole:
        return entry.name;
    case GenericNameRole:
        return entry.genericName;
    case CommentRole:
        return entry.comment;
    case AppIdRole:
        return entry.id;
    case Qt::DecorationRole:
        return entry.icon;
    case KeywordsRole:
        return entry.keywords;
    case CategoriesRole:
        return entry.categories;
    case SourceRole:
        return entry.source;
    case InstalledAtRole:
        return entry.installedAt;
    case IsNewRole:
        return isNew(entry);
    case SectionRole:
        return sectionOf(entry.name);
    default:
        return {};
    }
}

QHash<int, QByteArray> ApplicationsModel::roleNames() const
{
    return {
        {Qt::DisplayRole, "display"},
        {Qt::DecorationRole, "decoration"},
        {AppNameRole, "AppName"},
        {GenericNameRole, "GenericName"},
        {CommentRole, "Comment"},
        {AppIdRole, "AppId"},
        {KeywordsRole, "Keywords"},
        {CategoriesRole, "Categories"},
        {SourceRole, "Source"},
        {InstalledAtRole, "InstalledAt"},
        {IsNewRole, "IsNew"},
        {SectionRole, "Section"},
    };
}

int ApplicationsModel::count() const
{
    return int(m_rows.size());
}

int ApplicationsModel::totalCount() const
{
    return int(m_entries.size());
}

QString ApplicationsModel::filter() const
{
    return m_filter;
}

void ApplicationsModel::setFilter(const QString &filter)
{
    if (filter == m_filter) {
        return;
    }
    m_filter = filter;
    const int before = count();
    beginResetModel();
    applyFilter();
    endResetModel();
    Q_EMIT filterChanged();
    if (count() != before) {
        Q_EMIT countChanged();
    }
}

int ApplicationsModel::revision() const
{
    return m_revision;
}

QVariantList ApplicationsModel::recentlyInstalled() const
{
    const QDateTime now = m_now();
    QList<const Entry *> recent;
    for (const Entry &entry : m_entries) {
        if (entry.source != QLatin1String("system") && entry.installedAt.isValid()
            && entry.installedAt.secsTo(now) < RecentDays * 86400) {
            recent.append(&entry);
        }
    }
    std::stable_sort(recent.begin(), recent.end(), [](const Entry *a, const Entry *b) {
        return a->installedAt > b->installedAt;
    });
    QVariantList list;
    for (const Entry *entry : std::as_const(recent)) {
        if (list.size() == RecentLimit) {
            break;
        }
        list.append(toMap(*entry));
    }
    return list;
}

void ApplicationsModel::reload()
{
    KSycoca::self()->ensureCacheValid();

    const QString userData = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    QList<Entry> entries;
    QSet<QString> seen;
    const KService::List services = KService::allServices();
    for (const KService::Ptr &service : services) {
        if (!service || !service->isApplication() || service->noDisplay() || !service->showInCurrentDesktop()
            || !service->showOnCurrentPlatform() || seen.contains(service->storageId())) {
            continue;
        }
        seen.insert(service->storageId());
        Entry entry;
        entry.id = service->storageId();
        entry.name = service->name();
        entry.genericName = service->genericName();
        entry.comment = service->comment();
        entry.icon = service->icon();
        entry.keywords = service->keywords();
        entry.categories = service->categories();
        entry.service = service;
        entry.path = service->entryPath();
        if (QDir::isRelativePath(entry.path)) {
            entry.path = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, entry.path);
        }
        if (entry.path.contains(QLatin1String("/flatpak/exports/"))) {
            entry.source = QStringLiteral("flatpak");
        } else if (!userData.isEmpty() && entry.path.startsWith(userData + QLatin1Char('/'))) {
            entry.source = QStringLiteral("user");
        } else {
            entry.source = QStringLiteral("system");
        }
        if (entry.source != QLatin1String("system")) {
            entry.installedAt = linkTime(entry.path);
        }
        entries.append(entry);
    }

    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::stable_sort(entries.begin(), entries.end(), [&collator](const Entry &a, const Entry &b) {
        const int order = collator.compare(a.name, b.name);
        return order != 0 ? order < 0 : a.id < b.id;
    });

    const int before = count();
    beginResetModel();
    m_entries = entries;
    applyFilter();
    endResetModel();
    ++m_revision;
    qCInfo(STAROS_APPS) << "applications:" << m_entries.size();
    Q_EMIT revisionChanged();
    if (count() != before) {
        Q_EMIT countChanged();
    }
    watchDirectories();
}

bool ApplicationsModel::launch(int row)
{
    if (row < 0 || row >= count()) {
        return false;
    }
    return start(m_entries.at(m_rows.at(row)));
}

bool ApplicationsModel::launchDesktopId(const QString &desktopId)
{
    const QString wanted = normalizedId(desktopId);
    for (const Entry &entry : std::as_const(m_entries)) {
        if (normalizedId(entry.id) == wanted) {
            return start(entry);
        }
    }
    qCWarning(STAROS_APPS) << "not installed:" << desktopId;
    return false;
}

QVariantMap ApplicationsModel::get(int row) const
{
    if (row < 0 || row >= count()) {
        return {};
    }
    return toMap(m_entries.at(m_rows.at(row)));
}

QVariantMap ApplicationsModel::find(const QString &desktopId) const
{
    const QString wanted = normalizedId(desktopId);
    for (const Entry &entry : m_entries) {
        if (normalizedId(entry.id) == wanted) {
            return toMap(entry);
        }
    }
    return {};
}

QVariantList ApplicationsModel::apps(const QStringList &desktopIds) const
{
    QVariantList list;
    for (const QString &id : desktopIds) {
        const QVariantMap app = find(id);
        if (!app.isEmpty()) {
            list.append(app);
        }
    }
    return list;
}

void ApplicationsModel::setLauncher(Launcher launcher)
{
    m_launcher = std::move(launcher);
}

void ApplicationsModel::setStatePath(const QString &path)
{
    m_statePath = path;
    loadState();
    ++m_revision;
    Q_EMIT revisionChanged();
}

void ApplicationsModel::setRebuildCommand(const QStringList &command)
{
    m_rebuildCommand = command;
}

void ApplicationsModel::setNow(std::function<QDateTime()> now)
{
    m_now = std::move(now);
}

QString ApplicationsModel::normalizedId(const QString &desktopId)
{
    QString id = desktopId.section(QLatin1Char('/'), -1);
    if (id.endsWith(QLatin1String(".desktop"))) {
        id.chop(8);
    }
    return id;
}

int ApplicationsModel::rank(const Entry &entry, const QString &filter)
{
    const QString query = folded(filter.simplified());
    if (query.isEmpty()) {
        return 0;
    }
    const QString name = folded(entry.name);
    if (name.startsWith(query)) {
        return 0;
    }
    const QStringList terms = query.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    const QStringList words = nameWords(entry.name);
    const bool everyTermStartsAWord = std::all_of(terms.cbegin(), terms.cend(), [&words](const QString &term) {
        return std::any_of(words.cbegin(), words.cend(), [&term](const QString &word) {
            return word.startsWith(term);
        });
    });
    if (everyTermStartsAWord) {
        return 1;
    }
    if (name.contains(query)) {
        return 2;
    }
    const QString haystack =
        folded(QStringList{entry.name, entry.genericName, entry.keywords.join(QLatin1Char(' ')), entry.comment, normalizedId(entry.id)}.join(QLatin1Char(' ')));
    const bool everyTermFound = std::all_of(terms.cbegin(), terms.cend(), [&haystack](const QString &term) {
        return haystack.contains(term);
    });
    return everyTermFound ? 3 : -1;
}

void ApplicationsModel::scheduleRebuild()
{
    m_rebuildTimer.start();
}

void ApplicationsModel::rebuild()
{
    if (m_rebuildCommand.isEmpty()) {
        reload();
        return;
    }
    if (m_rebuilding) {
        m_rebuildTimer.start();
        return;
    }
    m_rebuilding = true;
    auto *process = new QProcess(this);
    process->setProgram(m_rebuildCommand.constFirst());
    process->setArguments(m_rebuildCommand.mid(1));
    process->setStandardInputFile(QProcess::nullDevice());
    process->setStandardOutputFile(QProcess::nullDevice());
    process->setStandardErrorFile(QProcess::nullDevice());
    auto done = [this, process] {
        process->deleteLater();
        m_rebuilding = false;
        reload();
    };
    connect(process, &QProcess::finished, this, done);
    connect(process, &QProcess::errorOccurred, this, [done](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            done();
        }
    });
    process->start(QIODevice::ReadOnly);
}

void ApplicationsModel::watchDirectories()
{
    const QStringList locations = QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation);
    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation));
    // The per-user Flatpak export directory exists only after the first
    // install; made now, it is watched and KService includes it.
    const QString home = QDir::homePath() + QLatin1Char('/');
    for (const QString &location : locations) {
        if (location.startsWith(home) && location.contains(QLatin1String("/flatpak/exports/share/applications"))) {
            QDir().mkpath(location);
        }
    }

    QStringList wanted;
    for (const QString &location : locations) {
        const QFileInfo info(location);
        if (!info.isDir()) {
            continue;
        }
        wanted.append(info.absoluteFilePath());
        const QDir dir(location);
        const QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QString &subdir : subdirs) {
            wanted.append(dir.absoluteFilePath(subdir));
        }
    }
    const QStringList watched = m_watcher.directories();
    for (const QString &path : watched) {
        if (!wanted.contains(path)) {
            m_watcher.removePath(path);
        }
    }
    for (const QString &path : std::as_const(wanted)) {
        if (!watched.contains(path)) {
            m_watcher.addPath(path);
        }
    }
}

void ApplicationsModel::applyFilter()
{
    m_rows.clear();
    if (m_filter.trimmed().isEmpty()) {
        m_rows.reserve(m_entries.size());
        for (int i = 0; i < m_entries.size(); ++i) {
            m_rows.append(i);
        }
        return;
    }
    QList<std::pair<int, int>> ranked; // rank, index
    for (int i = 0; i < m_entries.size(); ++i) {
        const int r = rank(m_entries.at(i), m_filter);
        if (r >= 0) {
            ranked.append({r, i});
        }
    }
    std::stable_sort(ranked.begin(), ranked.end(), [](const auto &a, const auto &b) {
        return a.first < b.first;
    });
    for (const auto &item : std::as_const(ranked)) {
        m_rows.append(item.second);
    }
}

void ApplicationsModel::loadState()
{
    m_launchedIds.clear();
    QFile file(m_statePath);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }
    const QJsonArray launched = QJsonDocument::fromJson(file.read(1024 * 1024)).object().value(QLatin1String("launched")).toArray();
    for (const QJsonValue &value : launched) {
        m_launchedIds.insert(value.toString());
    }
}

void ApplicationsModel::saveState()
{
    if (m_statePath.isEmpty()) {
        return;
    }
    QDir().mkpath(QFileInfo(m_statePath).absolutePath());
    QStringList ids(m_launchedIds.cbegin(), m_launchedIds.cend());
    ids.sort();
    QSaveFile file(m_statePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return;
    }
    QJsonObject object;
    object.insert(QStringLiteral("launched"), QJsonArray::fromStringList(ids));
    object.insert(QStringLiteral("version"), 1);
    file.write(QJsonDocument(object).toJson());
    file.commit();
}

bool ApplicationsModel::isNew(const Entry &entry) const
{
    return entry.source != QLatin1String("system") && entry.installedAt.isValid() && entry.installedAt.secsTo(m_now()) < NewDays * 86400
        && !m_launchedIds.contains(entry.id);
}

QVariantMap ApplicationsModel::toMap(const Entry &entry) const
{
    return {
        {QStringLiteral("AppName"), entry.name},
        {QStringLiteral("display"), entry.name},
        {QStringLiteral("GenericName"), entry.genericName},
        {QStringLiteral("Comment"), entry.comment},
        {QStringLiteral("AppId"), entry.id},
        {QStringLiteral("decoration"), entry.icon},
        {QStringLiteral("Keywords"), entry.keywords},
        {QStringLiteral("Categories"), entry.categories},
        {QStringLiteral("Source"), entry.source},
        {QStringLiteral("InstalledAt"), entry.installedAt},
        {QStringLiteral("IsNew"), isNew(entry)},
        {QStringLiteral("Section"), sectionOf(entry.name)},
    };
}

bool ApplicationsModel::start(const Entry &entry)
{
    if (!m_launcher || !entry.service || !m_launcher(entry.service)) {
        return false;
    }
    qCInfo(STAROS_APPS) << "launch" << entry.id;
    const bool wasNew = isNew(entry);
    m_launchedIds.insert(entry.id);
    saveState();
    Q_EMIT launched(entry.id);
    if (wasNew) {
        if (count() > 0) {
            Q_EMIT dataChanged(index(0), index(count() - 1), {IsNewRole});
        }
        ++m_revision;
        Q_EMIT revisionChanged();
    }
    return true;
}
