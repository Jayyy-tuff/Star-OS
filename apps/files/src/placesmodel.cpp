// SPDX-License-Identifier: GPL-3.0-or-later
#include "placesmodel.h"

#include "foldermodel.h"

#include <QDir>
#include <QFileInfo>
#include <QPair>
#include <QStandardPaths>

PlacesModel::PlacesModel(QObject *parent)
    : QAbstractListModel(parent)
{
    const QString home = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
    m_places.append({tr("Home"), QUrl::fromLocalFile(home)});

    const QList<QPair<QStandardPaths::StandardLocation, QString>> folders = {
        {QStandardPaths::DesktopLocation, tr("Desktop")},
        {QStandardPaths::DocumentsLocation, tr("Documents")},
        {QStandardPaths::DownloadLocation, tr("Downloads")},
        {QStandardPaths::MusicLocation, tr("Music")},
        {QStandardPaths::PicturesLocation, tr("Pictures")},
        {QStandardPaths::MoviesLocation, tr("Videos")},
    };
    for (const auto &folder : folders) {
        const QString path = QDir::cleanPath(QStandardPaths::writableLocation(folder.first));
        // xdg-user-dirs points disabled folders at home itself.
        if (!path.isEmpty() && path != home && QFileInfo(path).isDir()) {
            m_places.append({folder.second, QUrl::fromLocalFile(path)});
        }
    }

    m_places.append({tr("Trash"), QUrl(QStringLiteral("trash:/"))});
    m_places.append({tr("Computer"), QUrl::fromLocalFile(QStringLiteral("/"))});
}

int PlacesModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_places.size());
}

QVariant PlacesModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.parent().isValid() || index.row() >= m_places.size()) {
        return {};
    }
    const Place &place = m_places.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole:
        return place.name;
    case UrlRole:
        return place.url;
    }
    return {};
}

QHash<int, QByteArray> PlacesModel::roleNames() const
{
    return {
        {NameRole, "name"},
        {UrlRole, "url"},
    };
}

int PlacesModel::count() const
{
    return int(m_places.size());
}

QUrl PlacesModel::homeUrl() const
{
    return m_places.constFirst().url;
}

int PlacesModel::indexOfUrl(const QUrl &url) const
{
    const QUrl target = FolderModel::normalized(url);
    for (int row = 0; row < m_places.size(); ++row) {
        if (FolderModel::normalized(m_places.at(row).url) == target) {
            return row;
        }
    }
    return -1;
}

QString PlacesModel::nameForUrl(const QUrl &url) const
{
    const int row = indexOfUrl(url);
    if (row >= 0) {
        return m_places.at(row).name;
    }
    const QString name = FolderModel::normalized(url).fileName();
    return name.isEmpty() ? url.toDisplayString(QUrl::PreferLocalFile) : name;
}
