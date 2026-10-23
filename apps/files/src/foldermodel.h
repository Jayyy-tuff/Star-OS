// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <KFileItem>

#include <QAbstractListModel>
#include <QList>
#include <QPair>
#include <QString>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class KCoreDirLister;

namespace KIO
{
class Job;
}

// One folder's contents, listed and watched by KCoreDirLister. Rows are sorted
// folders first, then by name ignoring case, by size (largest first) or by the
// time modified (newest first). The lister applies the hidden-file setting;
// the name filter (a case-insensitive substring) is applied here so that it
// also matches folders and partial names.
class FolderModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(QString location READ location NOTIFY urlChanged)
    Q_PROPERTY(QUrl parentUrl READ parentUrl NOTIFY urlChanged)
    Q_PROPERTY(bool isTrash READ isTrash NOTIFY urlChanged)
    Q_PROPERTY(QString nameFilter READ nameFilter WRITE setNameFilter NOTIFY nameFilterChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool loading READ isLoading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    // A SortKey value: 0 name, 1 size, 2 modified.
    Q_PROPERTY(int sortKey READ sortKey WRITE setSortKey NOTIFY sortKeyChanged)
    // "9.8 GiB free" for a local folder, empty elsewhere (Trash).
    Q_PROPERTY(QString freeText READ freeText NOTIFY freeTextChanged)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        UrlRole,
        IsDirRole,
        SizeRole,
        ModifiedRole,
        MimeTypeRole,
        TypeNameRole,
        HiddenRole,
        AccessibleDescriptionRole,
    };
    Q_ENUM(Role)

    enum SortKey {
        SortByName = 0,
        SortBySize,
        SortByModified,
    };
    Q_ENUM(SortKey)

    explicit FolderModel(QObject *parent = nullptr);
    ~FolderModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QUrl url() const;
    void setUrl(const QUrl &url);
    QString location() const;
    QUrl parentUrl() const;
    bool isTrash() const;
    QString nameFilter() const;
    void setNameFilter(const QString &filter);
    bool showHidden() const;
    void setShowHidden(bool show);
    int count() const;
    bool isLoading() const;
    QString errorString() const;
    int sortKey() const;
    void setSortKey(int key);
    QString freeText() const;

    KFileItem itemAt(int row) const;

    // Lists the folder again and applies the differences (KDirWatch and
    // KDirNotify do this too, but neither is guaranteed: no D-Bus in tests,
    // inotify limits on large trees).
    Q_INVOKABLE void refresh();
    Q_INVOKABLE int indexOfUrl(const QUrl &url) const;
    // What the user typed in the location field, as a URL Files can show: a
    // path (absolute, ~/..., or relative to this folder), a file: URL or a
    // trash: URL. Returns an empty URL for anything else.
    Q_INVOKABLE QUrl urlFromLocation(const QString &text) const;

    static QUrl normalized(const QUrl &url);
    static QUrl parentOf(const QUrl &url);

Q_SIGNALS:
    void urlChanged();
    void nameFilterChanged();
    void showHiddenChanged();
    void countChanged();
    void loadingChanged();
    void errorStringChanged();
    void sortKeyChanged();
    void freeTextChanged();
    // The lister finished (completed or canceled) a listing or an update.
    void listingFinished();

private:
    bool accepts(const KFileItem &item) const;
    bool lessThan(const KFileItem &a, const KFileItem &b) const;
    void updateFreeText();
    int rowOfUrl(const QList<KFileItem> &items, const QUrl &url) const;
    int insertionRow(const KFileItem &item) const;
    void insertItem(const KFileItem &item);
    void rebuild();
    void addItems(const KFileItemList &items);
    void removeItems(const KFileItemList &items);
    void replaceItems(const QList<QPair<KFileItem, KFileItem>> &pairs);
    void clearItems();
    void setLoading(bool loading);
    void setErrorString(const QString &error);

    KCoreDirLister *m_lister;
    QUrl m_url;
    QString m_nameFilter;
    QList<KFileItem> m_all; // everything the lister shows (hidden setting applied)
    QList<KFileItem> m_items; // the rows: m_all filtered and sorted
    bool m_loading = false;
    QString m_errorString;
    int m_sortKey = SortByName;
    QString m_freeText;
};
