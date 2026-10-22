// SPDX-License-Identifier: GPL-3.0-or-later
#include "foldermodel.h"

#include <KCoreDirLister>
#include <KIO/Global>
#include <KIO/Job>

#include <QDir>

#include <algorithm>
#include <iterator>

namespace
{
// Larger batches (a first listing arrives in big chunks) are merged with one
// model reset instead of a row insertion each.
constexpr qsizetype BatchResetThreshold = 16;

bool lessThan(const KFileItem &a, const KFileItem &b)
{
    if (a.isDir() != b.isDir()) {
        return a.isDir();
    }
    const QString textA = a.text();
    const QString textB = b.text();
    const int order = QString::compare(textA, textB, Qt::CaseInsensitive);
    if (order != 0) {
        return order < 0;
    }
    if (textA != textB) {
        return textA < textB;
    }
    // The Trash can hold several items with the same name.
    return a.url().toString() < b.url().toString();
}

QString typeName(const KFileItem &item)
{
    const QString comment = item.mimeComment();
    if (!comment.isEmpty()) {
        return comment;
    }
    return item.isDir() ? FolderModel::tr("Folder") : FolderModel::tr("File");
}
}

FolderModel::FolderModel(QObject *parent)
    : QAbstractListModel(parent)
    , m_lister(new KCoreDirLister(this))
{
    // Errors are shown inline through errorString; there is no dialog to show.
    m_lister->setAutoErrorHandlingEnabled(false);

    connect(m_lister, &KCoreDirLister::started, this, [this] {
        setLoading(true);
    });
    connect(m_lister, &KCoreDirLister::completed, this, [this] {
        setLoading(false);
        Q_EMIT listingFinished();
    });
    connect(m_lister, &KCoreDirLister::canceled, this, [this] {
        setLoading(false);
        Q_EMIT listingFinished();
    });
    connect(m_lister, &KCoreDirLister::clear, this, &FolderModel::clearItems);
    connect(m_lister, &KCoreDirLister::itemsAdded, this, [this](const QUrl &, const KFileItemList &items) {
        addItems(items);
    });
    connect(m_lister, &KCoreDirLister::itemsDeleted, this, &FolderModel::removeItems);
    connect(m_lister, &KCoreDirLister::refreshItems, this, &FolderModel::replaceItems);
    connect(m_lister, &KCoreDirLister::redirection, this, [this](const QUrl &, const QUrl &newUrl) {
        m_url = normalized(newUrl);
        Q_EMIT urlChanged();
    });
    connect(m_lister, &KCoreDirLister::jobError, this, [this](KIO::Job *job) {
        setErrorString(job->errorString());
    });

    connect(this, &QAbstractItemModel::rowsInserted, this, &FolderModel::countChanged);
    connect(this, &QAbstractItemModel::rowsRemoved, this, &FolderModel::countChanged);
    connect(this, &QAbstractItemModel::modelReset, this, &FolderModel::countChanged);
}

FolderModel::~FolderModel() = default;

int FolderModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant FolderModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.parent().isValid() || index.row() >= m_items.size()) {
        return {};
    }
    const KFileItem &item = m_items.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return item.text();
    case UrlRole:
        return item.url();
    case IsDirRole:
        return item.isDir();
    case SizeRole:
        return item.isDir() ? QVariant() : QVariant(qint64(item.size()));
    case ModifiedRole:
        return item.time(KFileItem::ModificationTime);
    case MimeTypeRole:
        return item.mimetype();
    case TypeNameRole:
        return typeName(item);
    case HiddenRole:
        return item.isHidden();
    case AccessibleDescriptionRole:
        if (item.isDir()) {
            return typeName(item);
        }
        return tr("%1, %2").arg(typeName(item), KIO::convertSize(item.size()));
    }
    return {};
}

QHash<int, QByteArray> FolderModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {UrlRole, "url"},
        {IsDirRole, "isDir"},
        {SizeRole, "size"},
        {ModifiedRole, "modified"},
        {MimeTypeRole, "mimeType"},
        {TypeNameRole, "typeName"},
        {HiddenRole, "hidden"},
        {AccessibleDescriptionRole, "accessibleDescription"},
    };
}

QUrl FolderModel::url() const
{
    return m_url;
}

void FolderModel::setUrl(const QUrl &url)
{
    const QUrl target = normalized(url);
    if (!target.isValid() || target.scheme().isEmpty()) {
        setErrorString(tr("This location is not valid."));
        return;
    }
    if (target == m_url) {
        return;
    }
    m_url = target;
    setErrorString(QString());
    Q_EMIT urlChanged();
    // Emits clear() first, which empties the rows.
    m_lister->openUrl(m_url);
}

QString FolderModel::location() const
{
    return m_url.isLocalFile() ? m_url.toLocalFile() : m_url.toDisplayString();
}

QUrl FolderModel::parentUrl() const
{
    return parentOf(m_url);
}

bool FolderModel::isTrash() const
{
    return m_url.scheme() == QLatin1String("trash");
}

QString FolderModel::nameFilter() const
{
    return m_nameFilter;
}

void FolderModel::setNameFilter(const QString &filter)
{
    const QString trimmed = filter.trimmed();
    if (trimmed == m_nameFilter) {
        return;
    }
    m_nameFilter = trimmed;
    rebuild();
    Q_EMIT nameFilterChanged();
}

bool FolderModel::showHidden() const
{
    return m_lister->showHiddenFiles();
}

void FolderModel::setShowHidden(bool show)
{
    if (show == m_lister->showHiddenFiles()) {
        return;
    }
    m_lister->setShowHiddenFiles(show);
    // Emits itemsDeleted / itemsAdded for the items that change visibility.
    m_lister->emitChanges();
    Q_EMIT showHiddenChanged();
}

int FolderModel::count() const
{
    return int(m_items.size());
}

bool FolderModel::isLoading() const
{
    return m_loading;
}

QString FolderModel::errorString() const
{
    return m_errorString;
}

KFileItem FolderModel::itemAt(int row) const
{
    return row >= 0 && row < m_items.size() ? m_items.at(row) : KFileItem();
}

void FolderModel::refresh()
{
    if (m_url.isEmpty()) {
        return;
    }
    if (m_errorString.isEmpty()) {
        m_lister->updateDirectory(m_url);
    } else {
        // A failed listing is not held by the lister, so list it afresh.
        setErrorString(QString());
        m_lister->openUrl(m_url, KCoreDirLister::Reload);
    }
}

int FolderModel::indexOfUrl(const QUrl &url) const
{
    return rowOfUrl(m_items, normalized(url));
}

QUrl FolderModel::urlFromLocation(const QString &text) const
{
    QString input = text.trimmed();
    if (input.isEmpty()) {
        return {};
    }
    if (input == QLatin1String("~") || input.startsWith(QLatin1String("~/"))) {
        input = QDir::homePath() + input.mid(1);
    }
    if (input.startsWith(QLatin1Char('/'))) {
        return normalized(QUrl::fromLocalFile(input));
    }
    const QUrl url(input);
    if (url.isLocalFile() || url.scheme() == QLatin1String("trash")) {
        return normalized(url);
    }
    if (url.scheme().isEmpty() && m_url.isLocalFile()) {
        return normalized(QUrl::fromLocalFile(QDir(m_url.toLocalFile()).absoluteFilePath(input)));
    }
    return {};
}

QUrl FolderModel::normalized(const QUrl &url)
{
    QUrl clean = url.adjusted(QUrl::NormalizePathSegments | QUrl::StripTrailingSlash);
    if (clean.path().isEmpty() && !clean.scheme().isEmpty()) {
        clean.setPath(QStringLiteral("/"));
    }
    return clean;
}

QUrl FolderModel::parentOf(const QUrl &url)
{
    const QUrl clean = normalized(url);
    if (clean.isEmpty() || clean.path() == QLatin1String("/")) {
        return {};
    }
    return normalized(clean.adjusted(QUrl::RemoveFilename));
}

bool FolderModel::accepts(const KFileItem &item) const
{
    return m_nameFilter.isEmpty() || item.text().contains(m_nameFilter, Qt::CaseInsensitive);
}

int FolderModel::rowOfUrl(const QList<KFileItem> &items, const QUrl &url) const
{
    const auto it = std::find_if(items.cbegin(), items.cend(), [&url](const KFileItem &item) {
        return item.url() == url;
    });
    return it == items.cend() ? -1 : int(it - items.cbegin());
}

int FolderModel::insertionRow(const KFileItem &item) const
{
    return int(std::upper_bound(m_items.cbegin(), m_items.cend(), item, lessThan) - m_items.cbegin());
}

void FolderModel::insertItem(const KFileItem &item)
{
    const int row = insertionRow(item);
    beginInsertRows(QModelIndex(), row, row);
    m_items.insert(row, item);
    endInsertRows();
}

void FolderModel::rebuild()
{
    beginResetModel();
    m_items.clear();
    std::copy_if(m_all.cbegin(), m_all.cend(), std::back_inserter(m_items), [this](const KFileItem &item) {
        return accepts(item);
    });
    std::sort(m_items.begin(), m_items.end(), lessThan);
    endResetModel();
}

void FolderModel::addItems(const KFileItemList &items)
{
    m_all.append(items);
    const auto accepted = std::count_if(items.cbegin(), items.cend(), [this](const KFileItem &item) {
        return accepts(item);
    });
    if (accepted > BatchResetThreshold) {
        rebuild();
        return;
    }
    for (const KFileItem &item : items) {
        if (accepts(item)) {
            insertItem(item);
        }
    }
}

void FolderModel::removeItems(const KFileItemList &items)
{
    for (const KFileItem &item : items) {
        const int all = rowOfUrl(m_all, item.url());
        if (all >= 0) {
            m_all.removeAt(all);
        }
        const int row = rowOfUrl(m_items, item.url());
        if (row >= 0) {
            beginRemoveRows(QModelIndex(), row, row);
            m_items.removeAt(row);
            endRemoveRows();
        }
    }
}

void FolderModel::replaceItems(const QList<QPair<KFileItem, KFileItem>> &pairs)
{
    for (const auto &pair : pairs) {
        const KFileItem &oldItem = pair.first;
        const KFileItem &newItem = pair.second;
        const int all = rowOfUrl(m_all, oldItem.url());
        if (all >= 0) {
            m_all[all] = newItem;
        } else {
            m_all.append(newItem);
        }

        const int row = rowOfUrl(m_items, oldItem.url());
        const bool keep = accepts(newItem);
        // Most refreshes (size, time) keep the position: update the row in
        // place so that the view keeps its current item.
        if (row >= 0 && keep && (row == 0 || !lessThan(newItem, m_items.at(row - 1)))
            && (row + 1 >= m_items.size() || !lessThan(m_items.at(row + 1), newItem))) {
            m_items[row] = newItem;
            const QModelIndex changed = index(row);
            Q_EMIT dataChanged(changed, changed);
            continue;
        }
        if (row >= 0) {
            beginRemoveRows(QModelIndex(), row, row);
            m_items.removeAt(row);
            endRemoveRows();
        }
        if (keep) {
            insertItem(newItem);
        }
    }
}

void FolderModel::clearItems()
{
    beginResetModel();
    m_all.clear();
    m_items.clear();
    endResetModel();
}

void FolderModel::setLoading(bool loading)
{
    if (loading != m_loading) {
        m_loading = loading;
        Q_EMIT loadingChanged();
    }
}

void FolderModel::setErrorString(const QString &error)
{
    if (error != m_errorString) {
        m_errorString = error;
        Q_EMIT errorStringChanged();
    }
}
