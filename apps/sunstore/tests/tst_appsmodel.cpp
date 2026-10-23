// SPDX-License-Identifier: GPL-3.0-or-later
// AppsModel's categories: Star picks first, then all apps, then Flathub's main
// categories; Star picks shows only the curated ids that are in the catalogue.
#include "appsmodel.h"
#include "starpicks.h"

#include <QRegularExpression>
#include <QTest>

using namespace Qt::StringLiterals;

namespace
{
CatalogueApp app(const QString &id, const QString &name, const QStringList &categories)
{
    CatalogueApp result;
    result.id = id;
    result.name = name;
    result.categories = categories;
    return result;
}
}

class AppsModelTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void categoriesStartWithStarPicks()
    {
        AppsModel model;
        const QStringList ids = model.categoryIds();
        QVERIFY(ids.size() > 2);
        QCOMPARE(ids.at(0), u"starpicks"_s);
        QCOMPARE(ids.at(1), QString());
        QCOMPARE(model.categoryName(u"starpicks"_s), u"Star picks"_s);
        QCOMPARE(model.categoryName(QString()), u"All apps"_s);
        QCOMPARE(model.categoryName(u"Game"_s), u"Games"_s);
    }

    void starPicksShowsCuratedAppsOnly()
    {
        AppsModel model;
        model.setCatalogue({
            app(u"org.gimp.GIMP"_s, u"GNU Image Manipulation Program"_s, {u"Graphics"_s}),
            app(u"org.example.Other"_s, u"Other"_s, {u"Graphics"_s}),
            app(u"org.keepassxc.KeePassXC"_s, u"KeePassXC"_s, {u"Utility"_s}),
        });
        QCOMPARE(model.rowCount(), 3);
        model.setCategory(u"starpicks"_s);
        QCOMPARE(model.rowCount(), 2);
        QCOMPARE(model.indexOf(u"org.example.Other"_s), -1);
        QVERIFY(model.indexOf(u"org.gimp.GIMP"_s) >= 0);
        model.setCategory(u"Graphics"_s);
        QCOMPARE(model.rowCount(), 2);
        model.setCategory(QString());
        QCOMPARE(model.rowCount(), 3);
    }

    void picksAreFlatpakIds()
    {
        static const QRegularExpression id(u"^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_-]+){2,}$"_s);
        QVERIFY(StarPicks::AppIds.size() >= 10);
        for (const QString &appId : StarPicks::AppIds) {
            QVERIFY2(id.match(appId).hasMatch(), qPrintable(appId));
            QCOMPARE(StarPicks::AppIds.count(appId), 1);
        }
    }
};

QTEST_GUILESS_MAIN(AppsModelTest)

#include "tst_appsmodel.moc"
