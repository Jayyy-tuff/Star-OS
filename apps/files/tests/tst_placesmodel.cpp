// SPDX-License-Identifier: GPL-3.0-or-later
// PlacesModel with a temporary home: only the user folders that exist are
// listed, in the fixed order, followed by Trash and Computer.

#include "placesmodel.h"

#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

class PlacesModelTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void listsExistingPlacesInOrder();
    void namesAndFindsUrls();

private:
    QUrl homeUrl(const QString &relative = QString()) const;

    QTemporaryDir m_home;
};

void PlacesModelTest::initTestCase()
{
    QVERIFY(m_home.isValid());
    // QStandardPaths reads $HOME and $XDG_CONFIG_HOME/user-dirs.dirs on each
    // call; with no user-dirs.dirs the folders are $HOME/Desktop and so on.
    qputenv("HOME", QFile::encodeName(m_home.path()));
    qputenv("XDG_CONFIG_HOME", QFile::encodeName(m_home.path() + QStringLiteral("/config")));
    QDir home(m_home.path());
    QVERIFY(home.mkdir(QStringLiteral("Desktop")));
    QVERIFY(home.mkdir(QStringLiteral("Music")));
    // A file where a folder is expected is not a place.
    QFile pictures(home.filePath(QStringLiteral("Pictures")));
    QVERIFY(pictures.open(QIODevice::WriteOnly));
}

QUrl PlacesModelTest::homeUrl(const QString &relative) const
{
    const QString home = QDir::cleanPath(m_home.path());
    return QUrl::fromLocalFile(relative.isEmpty() ? home : home + QLatin1Char('/') + relative);
}

void PlacesModelTest::listsExistingPlacesInOrder()
{
    PlacesModel places;
    QStringList names;
    QList<QUrl> urls;
    for (int row = 0; row < places.rowCount(); ++row) {
        names.append(places.data(places.index(row), PlacesModel::NameRole).toString());
        urls.append(places.data(places.index(row), PlacesModel::UrlRole).toUrl());
    }
    QCOMPARE(names, QStringList({"Home", "Desktop", "Music", "Trash", "Computer"}));
    QCOMPARE(urls,
             QList<QUrl>({homeUrl(), homeUrl(QStringLiteral("Desktop")), homeUrl(QStringLiteral("Music")),
                          QUrl(QStringLiteral("trash:/")), QUrl::fromLocalFile(QStringLiteral("/"))}));
    QCOMPARE(places.count(), 5);
    QCOMPARE(places.homeUrl(), homeUrl());
    QCOMPARE(places.data(places.index(0), Qt::DisplayRole).toString(), QStringLiteral("Home"));
    QVERIFY(places.roleNames().values().contains("name"));
    QVERIFY(places.roleNames().values().contains("url"));
}

void PlacesModelTest::namesAndFindsUrls()
{
    PlacesModel places;
    QCOMPARE(places.indexOfUrl(homeUrl(QStringLiteral("Music"))), 2);
    QCOMPARE(places.indexOfUrl(QUrl(homeUrl(QStringLiteral("Desktop")).toString() + QLatin1Char('/'))), 1);
    QCOMPARE(places.indexOfUrl(QUrl(QStringLiteral("trash:/"))), 3);
    QCOMPARE(places.indexOfUrl(homeUrl(QStringLiteral("Music/Album"))), -1);

    QCOMPARE(places.nameForUrl(homeUrl()), QStringLiteral("Home"));
    QCOMPARE(places.nameForUrl(QUrl(QStringLiteral("trash:/"))), QStringLiteral("Trash"));
    QCOMPARE(places.nameForUrl(QUrl::fromLocalFile(QStringLiteral("/"))), QStringLiteral("Computer"));
    QCOMPARE(places.nameForUrl(homeUrl(QStringLiteral("Music/Album"))), QStringLiteral("Album"));
}

QTEST_MAIN(PlacesModelTest)

#include "tst_placesmodel.moc"
