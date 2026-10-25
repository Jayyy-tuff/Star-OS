// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QQmlEngine>
#include <QSet>
#include <QStringList>
#include <QTimer>

#include <KService>

#include <functional>

// Every application KService lists for this desktop, for the start menu and
// the taskbar (M0.5, ADR-0013). It follows installs live: it watches the
// applications directories on the data paths, rebuilds KService's database
// after a change and reloads.
//
// filter ranks matches: the name starts with the text, every word of the text
// starts a word of the name, the name contains it, then the generic name,
// keywords, comment and id contain every word.
//
// "Recently installed" are apps whose desktop file lies under the user's data
// directory or a Flatpak export directory and changed in the last 30 days;
// such an app is new for three days or until it is launched.
class ApplicationsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY revisionChanged)
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    // Increases on every reload, for bindings on get(), apps() and the like.
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)
    Q_PROPERTY(QVariantList recentlyInstalled READ recentlyInstalled NOTIFY revisionChanged)

public:
    enum Role {
        AppNameRole = Qt::UserRole + 1,
        GenericNameRole,
        CommentRole,
        AppIdRole,
        KeywordsRole,
        CategoriesRole,
        SourceRole,
        InstalledAtRole,
        IsNewRole,
        SectionRole,
    };
    Q_ENUM(Role)

    struct Entry {
        QString id; // storage id, "org.kde.konsole.desktop"
        QString name;
        QString genericName;
        QString comment;
        QString icon;
        QString source; // "system", "flatpak" or "user"
        QString path;
        QStringList keywords;
        QStringList categories;
        QDateTime installedAt; // only for "flatpak" and "user"
        KService::Ptr service;
    };

    using Launcher = std::function<bool(const KService::Ptr &service)>;

    explicit ApplicationsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const;
    int totalCount() const;
    QString filter() const;
    void setFilter(const QString &filter);
    int revision() const;
    QVariantList recentlyInstalled() const;

    // Rereads KService (rebuilding its database if a directory changed).
    Q_INVOKABLE void reload();
    Q_INVOKABLE bool launch(int row);
    Q_INVOKABLE bool launchDesktopId(const QString &desktopId);
    // An app as a map with the role names as keys; empty when unknown.
    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE QVariantMap find(const QString &desktopId) const;
    // The apps among desktopIds that are installed, in that order (for pins).
    Q_INVOKABLE QVariantList apps(const QStringList &desktopIds) const;

    // For tests: what starts an app, where launches are remembered, the
    // command that rebuilds KService's database (empty: in process), the clock.
    void setLauncher(Launcher launcher);
    void setStatePath(const QString &path);
    void setRebuildCommand(const QStringList &command);
    void setNow(std::function<QDateTime()> now);

    static QString normalizedId(const QString &desktopId);
    // 0 is the best rank; -1 means no match.
    static int rank(const Entry &entry, const QString &filter);

Q_SIGNALS:
    void countChanged();
    void filterChanged();
    void revisionChanged();
    void launched(const QString &desktopId);
    void launchFailed(const QString &name, const QString &error);

private:
    void scheduleRebuild();
    void rebuild();
    void watchDirectories();
    void applyFilter();
    void loadState();
    void saveState();
    bool isNew(const Entry &entry) const;
    QVariantMap toMap(const Entry &entry) const;
    bool start(const Entry &entry);

    QList<Entry> m_entries; // all apps, by name
    QList<int> m_rows; // indexes into m_entries, in filter order
    QString m_filter;
    int m_revision = 0;
    QSet<QString> m_launchedIds;
    QString m_statePath;
    QStringList m_rebuildCommand;
    Launcher m_launcher;
    std::function<QDateTime()> m_now;
    QFileSystemWatcher m_watcher;
    QTimer m_rebuildTimer;
    bool m_rebuilding = false;
};
