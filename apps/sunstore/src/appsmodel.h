// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "appstream.h"
#include "flatpakoutput.h"

#include <QAbstractListModel>
#include <QHash>
#include <QQmlEngine>
#include <QSet>

// The apps Sun Store shows: the Flathub catalogue joined with the installed
// apps and the available updates, filtered by section, category and search
// text, sorted by name. Installed apps missing from the catalogue (another
// remote, or no catalogue yet) are still listed under Installed.
class AppsModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Owned by Store")

    // "discover", "installed" or "updates".
    Q_PROPERTY(QString section READ section WRITE setSection NOTIFY sectionChanged)
    // A main category id ("Office", "Game"…); empty for all.
    Q_PROPERTY(QString category READ category WRITE setCategory NOTIFY categoryChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int catalogueSize READ catalogueSize NOTIFY revisionChanged)
    Q_PROPERTY(int updateCount READ updateCount NOTIFY revisionChanged)
    // Changes whenever any app's data changes, for bindings that call app().
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    enum Role {
        AppIdRole = Qt::UserRole + 1,
        NameRole,
        SummaryRole,
        DescriptionRole,
        IconUrlRole,
        DeveloperRole,
        LicenseRole,
        VerifiedRole,
        CategoriesRole,
        VersionRole,
        InstalledRole,
        InstalledVersionRole,
        UpdateAvailableRole,
        InCatalogueRole,
    };
    Q_ENUM(Role)

    explicit AppsModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString section() const;
    void setSection(const QString &section);
    QString category() const;
    void setCategory(const QString &category);
    QString searchText() const;
    void setSearchText(const QString &text);
    int catalogueSize() const;
    int updateCount() const;
    int revision() const;

    void setCatalogue(const QList<CatalogueApp> &apps);
    void setInstalled(const QList<FlatpakOutput::InstalledApp> &apps);
    void setUpdates(const QHash<QString, QString> &updates);

    // All roles of one app by id (role names as keys); empty if unknown.
    Q_INVOKABLE QVariantMap app(const QString &appId) const;
    Q_INVOKABLE bool isInstalled(const QString &appId) const;
    // The row of an app in the current filter, or -1.
    Q_INVOKABLE int indexOf(const QString &appId) const;
    // The category ids the Discover section offers, in display order: Star
    // picks ("starpicks"), all apps (""), then Flathub's main categories.
    Q_INVOKABLE QStringList categoryIds() const;
    Q_INVOKABLE QString categoryName(const QString &id) const;

Q_SIGNALS:
    void sectionChanged();
    void categoryChanged();
    void searchTextChanged();
    void countChanged();
    void revisionChanged();

private:
    struct Entry {
        CatalogueApp app;
        bool inCatalogue = false;
        QString installedVersion;
        bool installed = false;
        QString updateVersion;
    };

    void rebuild();
    void refilter();
    bool matches(const Entry &entry) const;
    QVariant value(const Entry &entry, int role) const;

    QHash<QString, Entry> m_entries;
    QList<CatalogueApp> m_catalogue;
    QList<FlatpakOutput::InstalledApp> m_installed;
    QHash<QString, QString> m_updates;
    QList<QString> m_rows; // ids in display order
    QString m_section = QStringLiteral("discover");
    QString m_category;
    QString m_searchText;
    int m_revision = 0;
};
