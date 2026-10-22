// SPDX-License-Identifier: GPL-3.0-or-later
// FolderModel over a real KCoreDirLister on temporary folders: order, roles,
// hidden files, the name filter, updates, errors and URL helpers.

#include "foldermodel.h"

#include <KIO/Global>

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

namespace
{
bool writeFile(const QString &path, const QByteArray &content = QByteArray())
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(content) == content.size();
}

QStringList names(const FolderModel &model)
{
    QStringList result;
    for (int row = 0; row < model.rowCount(); ++row) {
        result.append(model.data(model.index(row), FolderModel::NameRole).toString());
    }
    return result;
}

// Opens `url` and waits for the lister to finish (completed or canceled).
bool openAndWait(FolderModel &model, const QUrl &url)
{
    QSignalSpy finished(&model, &FolderModel::listingFinished);
    model.setUrl(url);
    return finished.count() > 0 || finished.wait(20000);
}
}

class FolderModelTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void listsFoldersFirstThenNamesIgnoringCase();
    void rolesDescribeItems();
    void hiddenFilesFollowTheSetting();
    void nameFilterMatchesPartsOfNames();
    void refreshAppliesChanges();
    void missingFolderReportsAnError();
    void urlHelpers();

private:
    QUrl urlOf(const QString &name) const;

    // A new folder per test: KCoreDirLister caches listings per process.
    std::unique_ptr<QTemporaryDir> m_dir;
};

void FolderModelTest::init()
{
    m_dir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_dir->isValid());
    QDir dir(m_dir->path());
    for (const QString &folder : {QStringLiteral("zeta"), QStringLiteral("Alpha"), QStringLiteral(".hidden-dir")}) {
        QVERIFY(dir.mkdir(folder));
    }
    QVERIFY(writeFile(dir.filePath(QStringLiteral("b.txt")), "hello\n"));
    QVERIFY(writeFile(dir.filePath(QStringLiteral("A.txt"))));
    QVERIFY(writeFile(dir.filePath(QStringLiteral("c"))));
    QVERIFY(writeFile(dir.filePath(QStringLiteral(".secret"))));
}

QUrl FolderModelTest::urlOf(const QString &name) const
{
    return QUrl::fromLocalFile(QDir(m_dir->path()).filePath(name));
}

void FolderModelTest::listsFoldersFirstThenNamesIgnoringCase()
{
    FolderModel model;
    QVERIFY(openAndWait(model, QUrl::fromLocalFile(m_dir->path())));
    QVERIFY2(model.errorString().isEmpty(), qPrintable(model.errorString()));
    QVERIFY(!model.isLoading());
    QCOMPARE(names(model), QStringList({"Alpha", "zeta", "A.txt", "b.txt", "c"}));
    QCOMPARE(model.count(), 5);
}

void FolderModelTest::rolesDescribeItems()
{
    FolderModel model;
    QVERIFY(openAndWait(model, QUrl::fromLocalFile(m_dir->path())));

    const QHash<int, QByteArray> roles = model.roleNames();
    for (const QByteArray &role : {"name", "url", "isDir", "size", "modified", "mimeType", "typeName", "hidden", "accessibleDescription"}) {
        QVERIFY2(roles.values().contains(role), role.constData());
    }

    const int fileRow = model.indexOfUrl(urlOf(QStringLiteral("b.txt")));
    QCOMPARE(fileRow, 3);
    const QModelIndex file = model.index(fileRow);
    QCOMPARE(model.data(file, Qt::DisplayRole).toString(), QStringLiteral("b.txt"));
    QCOMPARE(model.data(file, FolderModel::UrlRole).toUrl(), urlOf(QStringLiteral("b.txt")));
    QCOMPARE(model.data(file, FolderModel::IsDirRole).toBool(), false);
    QCOMPARE(model.data(file, FolderModel::SizeRole).toLongLong(), 6);
    QCOMPARE(model.data(file, FolderModel::HiddenRole).toBool(), false);
    QVERIFY(model.data(file, FolderModel::ModifiedRole).toDateTime().isValid());
    const QString fileType = model.data(file, FolderModel::TypeNameRole).toString();
    QVERIFY(!fileType.isEmpty());
    QCOMPARE(model.data(file, FolderModel::AccessibleDescriptionRole).toString(),
             QStringLiteral("%1, %2").arg(fileType, KIO::convertSize(6)));

    const QModelIndex folder = model.index(model.indexOfUrl(urlOf(QStringLiteral("Alpha"))));
    QCOMPARE(folder.row(), 0);
    QCOMPARE(model.data(folder, FolderModel::IsDirRole).toBool(), true);
    QVERIFY(!model.data(folder, FolderModel::SizeRole).isValid());
    QCOMPARE(model.data(folder, FolderModel::AccessibleDescriptionRole).toString(),
             model.data(folder, FolderModel::TypeNameRole).toString());
}

void FolderModelTest::hiddenFilesFollowTheSetting()
{
    FolderModel model;
    QVERIFY(openAndWait(model, QUrl::fromLocalFile(m_dir->path())));
    QSignalSpy hiddenChanged(&model, &FolderModel::showHiddenChanged);

    model.setShowHidden(true);
    QCOMPARE(hiddenChanged.count(), 1);
    QVERIFY(model.showHidden());
    QTRY_COMPARE(names(model), QStringList({".hidden-dir", "Alpha", "zeta", ".secret", "A.txt", "b.txt", "c"}));
    QCOMPARE(model.data(model.index(0), FolderModel::HiddenRole).toBool(), true);

    model.setShowHidden(false);
    QTRY_COMPARE(names(model), QStringList({"Alpha", "zeta", "A.txt", "b.txt", "c"}));

    // The setting also applies to the next folder.
    model.setShowHidden(true);
    QVERIFY(openAndWait(model, urlOf(QStringLiteral("Alpha"))));
    QVERIFY(writeFile(QDir(m_dir->path()).filePath(QStringLiteral("Alpha/.dot"))));
    model.refresh();
    QTRY_COMPARE(names(model), QStringList({".dot"}));
}

void FolderModelTest::nameFilterMatchesPartsOfNames()
{
    FolderModel model;
    QVERIFY(openAndWait(model, QUrl::fromLocalFile(m_dir->path())));

    model.setNameFilter(QStringLiteral("TXT"));
    QCOMPARE(names(model), QStringList({"A.txt", "b.txt"}));
    model.setNameFilter(QStringLiteral("  ph "));
    QCOMPARE(model.nameFilter(), QStringLiteral("ph"));
    QCOMPARE(names(model), QStringList({"Alpha"}));
    model.setNameFilter(QStringLiteral("nothing"));
    QCOMPARE(model.count(), 0);
    model.setNameFilter(QString());
    QCOMPARE(model.count(), 5);
}

void FolderModelTest::refreshAppliesChanges()
{
    FolderModel model;
    QVERIFY(openAndWait(model, QUrl::fromLocalFile(m_dir->path())));
    QDir dir(m_dir->path());

    QVERIFY(writeFile(dir.filePath(QStringLiteral("d.txt"))));
    QVERIFY(dir.mkdir(QStringLiteral("Beta")));
    model.refresh();
    QTRY_COMPARE_WITH_TIMEOUT(names(model), QStringList({"Alpha", "Beta", "zeta", "A.txt", "b.txt", "c", "d.txt"}), 20000);

    QVERIFY(dir.remove(QStringLiteral("c")));
    QVERIFY(dir.rename(QStringLiteral("A.txt"), QStringLiteral("e.txt")));
    model.refresh();
    QTRY_COMPARE_WITH_TIMEOUT(names(model), QStringList({"Alpha", "Beta", "zeta", "b.txt", "d.txt", "e.txt"}), 20000);
    QCOMPARE(model.indexOfUrl(urlOf(QStringLiteral("e.txt"))), 5);
    QCOMPARE(model.indexOfUrl(urlOf(QStringLiteral("c"))), -1);
}

void FolderModelTest::missingFolderReportsAnError()
{
    FolderModel model;
    QSignalSpy errorChanged(&model, &FolderModel::errorStringChanged);
    QVERIFY(openAndWait(model, urlOf(QStringLiteral("missing"))));
    QVERIFY(!model.errorString().isEmpty());
    QVERIFY(errorChanged.count() >= 1);
    QCOMPARE(model.count(), 0);
    QVERIFY(!model.isLoading());

    // Once the folder exists, refresh lists it and clears the error.
    QDir dir(m_dir->path());
    QVERIFY(dir.mkdir(QStringLiteral("missing")));
    QVERIFY(writeFile(dir.filePath(QStringLiteral("missing/found.txt"))));
    model.refresh();
    QTRY_COMPARE_WITH_TIMEOUT(names(model), QStringList({"found.txt"}), 20000);
    QVERIFY(model.errorString().isEmpty());
}

void FolderModelTest::urlHelpers()
{
    QCOMPARE(FolderModel::parentOf(QUrl(QStringLiteral("file:///a/b"))), QUrl(QStringLiteral("file:///a")));
    QCOMPARE(FolderModel::parentOf(QUrl(QStringLiteral("file:///a/b/"))), QUrl(QStringLiteral("file:///a")));
    QCOMPARE(FolderModel::parentOf(QUrl(QStringLiteral("file:///a"))), QUrl(QStringLiteral("file:///")));
    QCOMPARE(FolderModel::parentOf(QUrl(QStringLiteral("file:///"))), QUrl());
    QCOMPARE(FolderModel::parentOf(QUrl(QStringLiteral("trash:/0-old"))), QUrl(QStringLiteral("trash:/")));
    QCOMPARE(FolderModel::parentOf(QUrl(QStringLiteral("trash:/"))), QUrl());
    QCOMPARE(FolderModel::normalized(QUrl(QStringLiteral("trash:"))), QUrl(QStringLiteral("trash:/")));
    QCOMPARE(FolderModel::normalized(QUrl(QStringLiteral("file:///a/./b/../c/"))), QUrl(QStringLiteral("file:///a/c")));

    FolderModel model;
    QVERIFY(openAndWait(model, QUrl::fromLocalFile(m_dir->path())));
    QCOMPARE(model.location(), QDir::cleanPath(m_dir->path()));
    QVERIFY(!model.isTrash());
    QCOMPARE(model.parentUrl(), FolderModel::parentOf(QUrl::fromLocalFile(m_dir->path())));

    QCOMPARE(model.urlFromLocation(QStringLiteral("Alpha")), urlOf(QStringLiteral("Alpha")));
    QCOMPARE(model.urlFromLocation(QStringLiteral(" /usr/../etc/ ")), QUrl::fromLocalFile(QStringLiteral("/etc")));
    QCOMPARE(model.urlFromLocation(QStringLiteral("~/Music")), QUrl::fromLocalFile(QDir::homePath() + QStringLiteral("/Music")));
    QCOMPARE(model.urlFromLocation(QStringLiteral("trash:/")), QUrl(QStringLiteral("trash:/")));
    QCOMPARE(model.urlFromLocation(QStringLiteral("file:///tmp")), QUrl::fromLocalFile(QStringLiteral("/tmp")));
    QCOMPARE(model.urlFromLocation(QStringLiteral("https://example.org/")), QUrl());
    QCOMPARE(model.urlFromLocation(QString()), QUrl());
}

QTEST_MAIN(FolderModelTest)

#include "tst_foldermodel.moc"
