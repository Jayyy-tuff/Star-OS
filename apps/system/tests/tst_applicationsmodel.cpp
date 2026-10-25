// SPDX-License-Identifier: GPL-3.0-or-later
// ApplicationsModel against its own desktop files: a "system" directory and a
// Flatpak export directory on XDG_DATA_DIRS (tests/CMakeLists.txt), and the
// test-mode user data directory. Launches go to a recorder.

#include "applicationsmodel.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include <KSycoca>
#include <kservice_export.h>

extern KSERVICE_EXPORT int ksycoca_ms_between_checks;

namespace
{
QString dataRoot()
{
    return QString::fromLocal8Bit(qgetenv("STAROS_TEST_DATA"));
}

QString systemApps()
{
    return dataRoot() + QStringLiteral("/system/applications");
}

QString flatpakApps()
{
    return dataRoot() + QStringLiteral("/flatpak/exports/share/applications");
}

QString flatpakDeploy()
{
    return dataRoot() + QStringLiteral("/flatpak/app");
}

void writeDesktop(const QString &path, const QString &name, const QString &extra = QString())
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(QStringLiteral("[Desktop Entry]\nType=Application\nName=%1\nExec=true\nIcon=applications-other\n%2")
                   .arg(name, extra)
                   .toUtf8());
}

// Like Flatpak: the export is a link to a file whose time is 0.
void writeFlatpak(const QString &id, const QString &name, const QString &extra = QString())
{
    const QString target = flatpakDeploy() + QLatin1Char('/') + id + QStringLiteral(".desktop");
    writeDesktop(target, name, extra);
    QFile file(target);
    QVERIFY(file.open(QIODevice::ReadWrite));
    QVERIFY(file.setFileTime(QDateTime::fromSecsSinceEpoch(0), QFileDevice::FileModificationTime));
    file.close();
    const QString link = flatpakApps() + QLatin1Char('/') + id + QStringLiteral(".desktop");
    QFile::remove(link);
    QDir().mkpath(flatpakApps());
    QVERIFY(QFile::link(target, link));
}

QStringList names(const ApplicationsModel &model)
{
    QStringList list;
    for (int row = 0; row < model.rowCount(); ++row) {
        list.append(model.data(model.index(row), ApplicationsModel::AppNameRole).toString());
    }
    return list;
}
}

class ApplicationsModelTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_state;
    QStringList m_launched;

    std::unique_ptr<ApplicationsModel> makeModel()
    {
        auto model = std::make_unique<ApplicationsModel>();
        model->setRebuildCommand({});
        model->setStatePath(m_state.filePath(QStringLiteral("apps.json")));
        model->setLauncher([this](const KService::Ptr &service) {
            m_launched.append(service->storageId());
            return true;
        });
        return model;
    }

private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        ksycoca_ms_between_checks = 0;
        QVERIFY(!dataRoot().isEmpty());
        QDir(dataRoot()).removeRecursively();
        QDir(QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation)).removeRecursively();
        QDir(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)).removeRecursively();

        writeDesktop(systemApps() + QStringLiteral("/org.example.Terminal.desktop"), QStringLiteral("Terminal Star"),
                     QStringLiteral("GenericName=Terminal\nKeywords=shell;console;\n"));
        writeDesktop(systemApps() + QStringLiteral("/org.example.Settings.desktop"), QStringLiteral("System Settings"),
                     QStringLiteral("GenericName=Settings\n"));
        writeDesktop(systemApps() + QStringLiteral("/org.example.Monitor.desktop"), QStringLiteral("System Monitor"),
                     QStringLiteral("Keywords=cpu;processes;\n"));
        writeDesktop(systemApps() + QStringLiteral("/org.example.Hidden.desktop"), QStringLiteral("Hidden Helper"),
                     QStringLiteral("NoDisplay=true\n"));
        writeDesktop(systemApps() + QStringLiteral("/org.example.Gnome.desktop"), QStringLiteral("Gnome Only"),
                     QStringLiteral("OnlyShowIn=GNOME;\n"));
        writeDesktop(systemApps() + QStringLiteral("/org.example.Files.desktop"), QStringLiteral("files"));
        writeFlatpak(QStringLiteral("org.gimp.GIMP"), QStringLiteral("GIMP"), QStringLiteral("GenericName=Image Editor\n"));
        writeDesktop(QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation) + QStringLiteral("/org.example.Mine.desktop"),
                     QStringLiteral("My Script"));
    }

    void init()
    {
        m_launched.clear();
        QFile::remove(m_state.filePath(QStringLiteral("apps.json")));
    }

    void listsVisibleAppsByName()
    {
        auto model = makeModel();
        QCOMPARE(names(*model),
                 (QStringList{QStringLiteral("files"), QStringLiteral("GIMP"), QStringLiteral("My Script"), QStringLiteral("System Monitor"),
                              QStringLiteral("System Settings"), QStringLiteral("Terminal Star")}));
        QCOMPARE(model->count(), 6);
        QCOMPARE(model->totalCount(), 6);
        QVERIFY(model->find(QStringLiteral("org.example.Hidden")).isEmpty());
        QVERIFY(model->find(QStringLiteral("org.example.Gnome.desktop")).isEmpty());
    }

    void rolesAndSources()
    {
        auto model = makeModel();
        const QHash<int, QByteArray> roles = model->roleNames();
        QCOMPARE(roles.value(ApplicationsModel::AppNameRole), QByteArray("AppName"));
        QCOMPARE(roles.value(Qt::DecorationRole), QByteArray("decoration"));
        QCOMPARE(roles.value(ApplicationsModel::AppIdRole), QByteArray("AppId"));

        const QVariantMap gimp = model->find(QStringLiteral("org.gimp.GIMP.desktop"));
        QCOMPARE(gimp.value(QStringLiteral("AppId")).toString(), QStringLiteral("org.gimp.GIMP.desktop"));
        QCOMPARE(gimp.value(QStringLiteral("Source")).toString(), QStringLiteral("flatpak"));
        QCOMPARE(gimp.value(QStringLiteral("GenericName")).toString(), QStringLiteral("Image Editor"));
        QCOMPARE(gimp.value(QStringLiteral("decoration")).toString(), QStringLiteral("applications-other"));
        // The link's own time, not the deployment's 1970.
        QVERIFY(gimp.value(QStringLiteral("InstalledAt")).toDateTime().secsTo(QDateTime::currentDateTime()) < 3600);
        QCOMPARE(model->find(QStringLiteral("org.example.Mine")).value(QStringLiteral("Source")).toString(), QStringLiteral("user"));
        const QVariantMap terminal = model->find(QStringLiteral("org.example.Terminal"));
        QCOMPARE(terminal.value(QStringLiteral("Source")).toString(), QStringLiteral("system"));
        QVERIFY(!terminal.value(QStringLiteral("InstalledAt")).toDateTime().isValid());
        QCOMPARE(terminal.value(QStringLiteral("Section")).toString(), QStringLiteral("T"));
        QCOMPARE(model->find(QStringLiteral("org.example.Files")).value(QStringLiteral("Section")).toString(), QStringLiteral("F"));
    }

    void filterRanksMatches_data()
    {
        QTest::addColumn<QString>("filter");
        QTest::addColumn<QStringList>("expected");
        QTest::newRow("name prefix, then by name") << QStringLiteral("sys")
                                                   << QStringList{QStringLiteral("System Monitor"), QStringLiteral("System Settings")};
        QTest::newRow("case") << QStringLiteral("GIM") << QStringList{QStringLiteral("GIMP")};
        QTest::newRow("word prefix") << QStringLiteral("set") << QStringList{QStringLiteral("System Settings")};
        QTest::newRow("words in any order") << QStringLiteral("star term") << QStringList{QStringLiteral("Terminal Star")};
        // Name prefix, word prefix, then the name contains it; ids are
        // searched without ".desktop".
        QTest::newRow("ranks") << QStringLiteral("s")
                               << QStringList{QStringLiteral("System Monitor"), QStringLiteral("System Settings"), QStringLiteral("My Script"),
                                              QStringLiteral("Terminal Star"), QStringLiteral("files")};
        QTest::newRow("keyword") << QStringLiteral("cpu") << QStringList{QStringLiteral("System Monitor")};
        QTest::newRow("generic name") << QStringLiteral("image") << QStringList{QStringLiteral("GIMP")};
        QTest::newRow("spaces") << QStringLiteral("  system   set ") << QStringList{QStringLiteral("System Settings")};
        QTest::newRow("nothing") << QStringLiteral("zzz") << QStringList{};
    }

    void filterRanksMatches()
    {
        QFETCH(QString, filter);
        QFETCH(QStringList, expected);
        auto model = makeModel();
        QSignalSpy counts(model.get(), &ApplicationsModel::countChanged);
        model->setFilter(filter);
        QCOMPARE(names(*model), expected);
        QCOMPARE(model->count(), expected.size());
        QCOMPARE(counts.count(), expected.size() == 6 ? 0 : 1);
        model->setFilter(QString());
        QCOMPARE(model->count(), 6);
    }

    void launchesTheFilteredRow()
    {
        auto model = makeModel();
        model->setFilter(QStringLiteral("set"));
        QSignalSpy launched(model.get(), &ApplicationsModel::launched);
        QVERIFY(model->launch(0));
        QCOMPARE(m_launched, QStringList{QStringLiteral("org.example.Settings.desktop")});
        QCOMPARE(launched.count(), 1);
        QVERIFY(!model->launch(1));
        QVERIFY(!model->launch(-1));
        QVERIFY(model->launchDesktopId(QStringLiteral("org.example.Terminal")));
        QVERIFY(!model->launchDesktopId(QStringLiteral("org.example.Missing.desktop")));
        QCOMPARE(m_launched.size(), 2);
    }

    void recentlyInstalledAndNew()
    {
        auto model = makeModel();
        QVariantList recent = model->recentlyInstalled();
        QStringList ids;
        for (const QVariant &app : recent) {
            ids.append(app.toMap().value(QStringLiteral("AppId")).toString());
        }
        ids.sort();
        QCOMPARE(ids, (QStringList{QStringLiteral("org.example.Mine.desktop"), QStringLiteral("org.gimp.GIMP.desktop")}));
        QVERIFY(model->find(QStringLiteral("org.gimp.GIMP")).value(QStringLiteral("IsNew")).toBool());
        QVERIFY(!model->find(QStringLiteral("org.example.Terminal")).value(QStringLiteral("IsNew")).toBool());

        // Launching ends "new", and it is remembered.
        const int revision = model->revision();
        QVERIFY(model->launchDesktopId(QStringLiteral("org.gimp.GIMP.desktop")));
        QVERIFY(model->revision() > revision);
        QVERIFY(!model->find(QStringLiteral("org.gimp.GIMP")).value(QStringLiteral("IsNew")).toBool());
        QFile state(m_state.filePath(QStringLiteral("apps.json")));
        QVERIFY(state.open(QIODevice::ReadOnly));
        QVERIFY(QJsonDocument::fromJson(state.readAll()).object().value(QLatin1String("launched")).toArray().contains(
            QStringLiteral("org.gimp.GIMP.desktop")));
        auto again = makeModel();
        QVERIFY(!again->find(QStringLiteral("org.gimp.GIMP")).value(QStringLiteral("IsNew")).toBool());
        QVERIFY(again->find(QStringLiteral("org.example.Mine")).value(QStringLiteral("IsNew")).toBool());

        // New for three days, recent for thirty.
        again->setNow([] {
            return QDateTime::currentDateTime().addDays(4);
        });
        QVERIFY(!again->find(QStringLiteral("org.example.Mine")).value(QStringLiteral("IsNew")).toBool());
        QCOMPARE(again->recentlyInstalled().size(), 2);
        again->setNow([] {
            return QDateTime::currentDateTime().addDays(31);
        });
        QCOMPARE(again->recentlyInstalled().size(), 0);
    }

    void appsKeepsTheGivenOrder()
    {
        auto model = makeModel();
        const QVariantList pinned = model->apps({QStringLiteral("org.example.Terminal.desktop"), QStringLiteral("org.example.Missing.desktop"),
                                                 QStringLiteral("org.gimp.GIMP")});
        QCOMPARE(pinned.size(), 2);
        QCOMPARE(pinned.at(0).toMap().value(QStringLiteral("AppName")).toString(), QStringLiteral("Terminal Star"));
        QCOMPARE(pinned.at(1).toMap().value(QStringLiteral("AppName")).toString(), QStringLiteral("GIMP"));
        QCOMPARE(model->get(0).value(QStringLiteral("AppName")).toString(), QStringLiteral("files"));
        QVERIFY(model->get(99).isEmpty());
    }

    // An app exported while the model runs appears without a reload call.
    void followsInstallsAndRemovals()
    {
        auto model = makeModel();
        QSignalSpy revisions(model.get(), &ApplicationsModel::revisionChanged);
        QVERIFY(model->find(QStringLiteral("org.example.Game")).isEmpty());
        writeFlatpak(QStringLiteral("org.example.Game"), QStringLiteral("Space Game"), QStringLiteral("Categories=Game;\n"));
        QTRY_VERIFY_WITH_TIMEOUT(!model->find(QStringLiteral("org.example.Game")).isEmpty(), 15000);
        QVERIFY(revisions.count() > 0);
        QCOMPARE(model->totalCount(), 7);
        QCOMPARE(model->recentlyInstalled().constFirst().toMap().value(QStringLiteral("AppName")).toString(), QStringLiteral("Space Game"));
        QCOMPARE(model->find(QStringLiteral("org.example.Game")).value(QStringLiteral("Categories")).toStringList(),
                 QStringList{QStringLiteral("Game")});

        QVERIFY(QFile::remove(flatpakApps() + QStringLiteral("/org.example.Game.desktop")));
        QTRY_VERIFY_WITH_TIMEOUT(model->find(QStringLiteral("org.example.Game")).isEmpty(), 15000);
        QCOMPARE(model->totalCount(), 6);
    }
};

QTEST_GUILESS_MAIN(ApplicationsModelTest)

#include "tst_applicationsmodel.moc"
