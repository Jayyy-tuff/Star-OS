// SPDX-License-Identifier: GPL-3.0-or-later
#include "appsmodel.h"

#include "starpicks.h"

#include <QCollator>
#include <QPair>
#include <QUrl>

#include <algorithm>

namespace
{
// Freedesktop main categories as Flathub groups them.
const QList<QPair<QString, const char *>> Categories = {
    {QStringLiteral("AudioVideo"), QT_TRANSLATE_NOOP("AppsModel", "Audio & Video")},
    {QStringLiteral("Development"), QT_TRANSLATE_NOOP("AppsModel", "Development")},
    {QStringLiteral("Education"), QT_TRANSLATE_NOOP("AppsModel", "Education")},
    {QStringLiteral("Game"), QT_TRANSLATE_NOOP("AppsModel", "Games")},
    {QStringLiteral("Graphics"), QT_TRANSLATE_NOOP("AppsModel", "Graphics")},
    {QStringLiteral("Network"), QT_TRANSLATE_NOOP("AppsModel", "Internet")},
    {QStringLiteral("Office"), QT_TRANSLATE_NOOP("AppsModel", "Office")},
    {QStringLiteral("Science"), QT_TRANSLATE_NOOP("AppsModel", "Science")},
    {QStringLiteral("System"), QT_TRANSLATE_NOOP("AppsModel", "System")},
    {QStringLiteral("Utility"), QT_TRANSLATE_NOOP("AppsModel", "Utilities")},
};
}

AppsModel::AppsModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int AppsModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant AppsModel::value(const Entry &entry, int role) const
{
    const CatalogueApp &app = entry.app;
    switch (role) {
    case AppIdRole:
        return app.id;
    case Qt::DisplayRole:
    case NameRole:
        return app.name;
    case SummaryRole:
        return app.summary;
    case DescriptionRole:
        return app.description;
    case IconUrlRole:
        return app.iconPath.isEmpty() ? QUrl() : QUrl::fromLocalFile(app.iconPath);
    case DeveloperRole:
        return app.developer;
    case LicenseRole:
        return app.license;
    case VerifiedRole:
        return app.verified;
    case CategoriesRole:
        return app.categories;
    case VersionRole:
        return entry.updateVersion.isEmpty() ? app.version : entry.updateVersion;
    case InstalledRole:
        return entry.installed;
    case InstalledVersionRole:
        return entry.installedVersion;
    case UpdateAvailableRole:
        return entry.installed && m_updates.contains(app.id);
    case InCatalogueRole:
        return entry.inCatalogue;
    }
    return {};
}

QVariant AppsModel::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    return value(m_entries.value(m_rows.at(index.row())), role);
}

QHash<int, QByteArray> AppsModel::roleNames() const
{
    return {
        {AppIdRole, "appId"},
        {NameRole, "name"},
        {SummaryRole, "summary"},
        {DescriptionRole, "description"},
        {IconUrlRole, "iconUrl"},
        {DeveloperRole, "developer"},
        {LicenseRole, "license"},
        {VerifiedRole, "verified"},
        {CategoriesRole, "categories"},
        {VersionRole, "version"},
        {InstalledRole, "installed"},
        {InstalledVersionRole, "installedVersion"},
        {UpdateAvailableRole, "updateAvailable"},
        {InCatalogueRole, "inCatalogue"},
    };
}

QString AppsModel::section() const
{
    return m_section;
}

void AppsModel::setSection(const QString &section)
{
    if (section == m_section) {
        return;
    }
    m_section = section;
    Q_EMIT sectionChanged();
    refilter();
}

QString AppsModel::category() const
{
    return m_category;
}

void AppsModel::setCategory(const QString &category)
{
    if (category == m_category) {
        return;
    }
    m_category = category;
    Q_EMIT categoryChanged();
    refilter();
}

QString AppsModel::searchText() const
{
    return m_searchText;
}

void AppsModel::setSearchText(const QString &text)
{
    if (text == m_searchText) {
        return;
    }
    m_searchText = text;
    Q_EMIT searchTextChanged();
    refilter();
}

int AppsModel::catalogueSize() const
{
    return int(m_catalogue.size());
}

int AppsModel::updateCount() const
{
    int count = 0;
    for (const auto &entry : m_entries) {
        count += entry.installed && m_updates.contains(entry.app.id) ? 1 : 0;
    }
    return count;
}

int AppsModel::revision() const
{
    return m_revision;
}

void AppsModel::setCatalogue(const QList<CatalogueApp> &apps)
{
    m_catalogue = apps;
    rebuild();
}

void AppsModel::setInstalled(const QList<FlatpakOutput::InstalledApp> &apps)
{
    m_installed = apps;
    rebuild();
}

void AppsModel::setUpdates(const QHash<QString, QString> &updates)
{
    m_updates = updates;
    rebuild();
}

void AppsModel::rebuild()
{
    m_entries.clear();
    for (const CatalogueApp &app : std::as_const(m_catalogue)) {
        Entry entry;
        entry.app = app;
        entry.inCatalogue = true;
        m_entries.insert(app.id, entry);
    }
    for (const auto &installed : std::as_const(m_installed)) {
        Entry &entry = m_entries[installed.id];
        if (!entry.inCatalogue) {
            entry.app.id = installed.id;
            entry.app.name = installed.name;
            entry.app.version = installed.version;
        }
        entry.installed = true;
        entry.installedVersion = installed.version;
    }
    for (auto it = m_updates.cbegin(); it != m_updates.cend(); ++it) {
        auto entry = m_entries.find(it.key());
        if (entry != m_entries.end()) {
            entry->updateVersion = it.value();
        }
    }
    ++m_revision;
    Q_EMIT revisionChanged();
    refilter();
}

bool AppsModel::matches(const Entry &entry) const
{
    if (m_section == QLatin1String("installed")) {
        if (!entry.installed) {
            return false;
        }
    } else if (m_section == QLatin1String("updates")) {
        if (!entry.installed || !m_updates.contains(entry.app.id)) {
            return false;
        }
    } else {
        if (!entry.inCatalogue) {
            return false;
        }
        if (m_category == StarPicks::CategoryId) {
            if (!StarPicks::AppIds.contains(entry.app.id)) {
                return false;
            }
        } else if (!m_category.isEmpty() && !entry.app.categories.contains(m_category)) {
            return false;
        }
    }
    const QString needle = m_searchText.trimmed();
    if (needle.isEmpty()) {
        return true;
    }
    return entry.app.name.contains(needle, Qt::CaseInsensitive) || entry.app.id.contains(needle, Qt::CaseInsensitive)
        || entry.app.summary.contains(needle, Qt::CaseInsensitive);
}

void AppsModel::refilter()
{
    QList<QString> rows;
    for (auto it = m_entries.cbegin(); it != m_entries.cend(); ++it) {
        if (matches(it.value())) {
            rows.append(it.key());
        }
    }
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    collator.setNumericMode(true);
    std::sort(rows.begin(), rows.end(), [this, &collator](const QString &a, const QString &b) {
        const int order = collator.compare(m_entries.constFind(a)->app.name, m_entries.constFind(b)->app.name);
        return order != 0 ? order < 0 : a < b;
    });
    const bool countChanges = rows.size() != m_rows.size();
    beginResetModel();
    m_rows = rows;
    endResetModel();
    if (countChanges) {
        Q_EMIT countChanged();
    }
}

QVariantMap AppsModel::app(const QString &appId) const
{
    const auto it = m_entries.constFind(appId);
    if (it == m_entries.cend()) {
        return {};
    }
    QVariantMap result;
    const auto names = roleNames();
    for (auto role = names.cbegin(); role != names.cend(); ++role) {
        result.insert(QString::fromLatin1(role.value()), value(it.value(), role.key()));
    }
    return result;
}

bool AppsModel::isInstalled(const QString &appId) const
{
    return m_entries.value(appId).installed;
}

int AppsModel::indexOf(const QString &appId) const
{
    return int(m_rows.indexOf(appId));
}

QStringList AppsModel::categoryIds() const
{
    QStringList ids{StarPicks::CategoryId, QString()};
    for (const auto &category : Categories) {
        ids.append(category.first);
    }
    return ids;
}

QString AppsModel::categoryName(const QString &id) const
{
    if (id == StarPicks::CategoryId) {
        return tr("Star picks");
    }
    if (id.isEmpty()) {
        return tr("All apps");
    }
    for (const auto &category : Categories) {
        if (category.first == id) {
            return tr(category.second);
        }
    }
    return id;
}
