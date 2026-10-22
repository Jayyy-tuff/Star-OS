// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QList>
#include <QString>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

// The places in the sidebar: Home, the XDG user folders that exist, Trash and
// Computer. Built once; the folders are read from QStandardPaths.
class PlacesModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ count CONSTANT)
    Q_PROPERTY(QUrl homeUrl READ homeUrl CONSTANT)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        UrlRole,
    };
    Q_ENUM(Role)

    explicit PlacesModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;
    QUrl homeUrl() const;

    Q_INVOKABLE int indexOfUrl(const QUrl &url) const;
    // The place name for a place, otherwise the folder's own name.
    Q_INVOKABLE QString nameForUrl(const QUrl &url) const;

private:
    struct Place {
        QString name;
        QUrl url;
    };
    QList<Place> m_places;
};
