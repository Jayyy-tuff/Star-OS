// SPDX-License-Identifier: GPL-3.0-or-later
// Store against a fake flatpak (fakeflatpak.h): the exact command lines, the
// consent flow, offline handling, install / remove / update, permissions, and
// that malformed app ids never reach flatpak.

#include "fakeflatpak.h"
#include "store.h"

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using namespace Qt::StringLiterals;

namespace
{
const QString Editor = u"org.example.Editor"_s;
const QByteArray FlathubRemote = "flathub\thttps://dl.flathub.org/repo/\n";
}

class StoreTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void asksForConsentWithoutFlathub();
    void enablingFlathubAddsTheRemoteAndLoads();
    void failedRemoteAddIsAnError();
    void startsWithFlathubAndJoinsInstalledApps();
    void offlineWithoutCatalogue();
    void offlineWithEarlierCatalogue();
    void installsAndRemoves();
    void reportsFailedInstall();
    void updatesAll();
    void readsPermissions();
    void opensOnlyInstalledApps();
    void refusesInvalidIds();
    void missingFlatpakIsAnError();

private:
    std::unique_ptr<Store> makeStore();
    void startReady(Store &store);
    QStringList log() const;
    void write(const QString &name, const QByteArray &content);

    std::unique_ptr<QTemporaryDir> m_dir;
    QString m_state;
    QString m_data;
    QString m_active;
    QString m_repo;
    QString m_program;
};

void StoreTest::init()
{
    m_dir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_dir->isValid());
    QDir dir(m_dir->path());
    QVERIFY(dir.mkdir(u"state"_s));
    m_state = dir.filePath(u"state"_s);
    m_data = dir.filePath(u"data"_s);
    m_active = m_data + u"/appstream/flathub/"_s + Store::flatpakArch() + u"/active"_s;
    m_repo = dir.filePath(u"flathub.flatpakrepo"_s);
    QVERIFY(FakeFlatpak::write(m_dir->path(), u"flathub.flatpakrepo"_s, "[Flatpak Repo]\nTitle=Flathub\n"));
    m_program = FakeFlatpak::create(m_state, m_active);
    QVERIFY(!m_program.isEmpty());
    QFile fixture(QStringLiteral(SUNSTORE_TEST_DATA "/appstream.xml"));
    QVERIFY(fixture.open(QIODevice::ReadOnly));
    write(u"appstream.xml"_s, fixture.readAll());
}

std::unique_ptr<Store> StoreTest::makeStore()
{
    return std::make_unique<Store>(m_program, m_data, m_repo);
}

void StoreTest::startReady(Store &store)
{
    write(u"remotes"_s, FlathubRemote);
    store.start();
    QTRY_VERIFY(store.state() == u"ready"_s && !store.busy());
}

QStringList StoreTest::log() const
{
    return FakeFlatpak::log(m_state);
}

void StoreTest::write(const QString &name, const QByteArray &content)
{
    QVERIFY(FakeFlatpak::write(m_state, name, content));
}

void StoreTest::asksForConsentWithoutFlathub()
{
    auto store = makeStore();
    QCOMPARE(store->state(), u"starting"_s);
    store->start();
    QTRY_COMPARE(store->state(), u"needsConsent"_s);
    QCOMPARE(log(), QStringList({u"remotes --user --columns=name,url"_s}));
    // Nothing is installed before Flathub is enabled.
    QVERIFY(!store->install(Editor));
    store->refresh();
    QCOMPARE(log().size(), 1);
}

void StoreTest::enablingFlathubAddsTheRemoteAndLoads()
{
    auto store = makeStore();
    store->start();
    QTRY_COMPARE(store->state(), u"needsConsent"_s);
    store->enableFlathub();
    QTRY_VERIFY(store->state() == u"ready"_s && !store->busy());
    const QStringList calls = log();
    QVERIFY2(calls.contains(u"remote-add --user --if-not-exists flathub "_s + m_repo), qPrintable(calls.join(u'\n')));
    QVERIFY(calls.contains(u"update --user --appstream flathub"_s));
    QVERIFY(calls.contains(u"list --user --app --columns=application,name,version,origin"_s));
    QVERIFY(calls.contains(u"remote-ls --user --updates --app --columns=application,version"_s));
    QVERIFY(!store->offline());
    QCOMPARE(store->apps()->catalogueSize(), 2);
    QCOMPARE(store->apps()->rowCount(), 2);
}

void StoreTest::failedRemoteAddIsAnError()
{
    write(u"fail-remote-add"_s, "error: Can't load file flathub.flatpakrepo\n");
    auto store = makeStore();
    store->start();
    QTRY_COMPARE(store->state(), u"needsConsent"_s);
    store->enableFlathub();
    QTRY_COMPARE(store->state(), u"error"_s);
    QCOMPARE(store->errorString(), u"Can't load file flathub.flatpakrepo"_s);
    QVERIFY(!store->busy());
}

void StoreTest::startsWithFlathubAndJoinsInstalledApps()
{
    write(u"installed"_s, "org.example.Editor\tExample Editor\t2.0\tflathub\norg.other.Tool\tTool\t1.0\tother\n");
    write(u"updates"_s, "org.example.Editor\t2.1\n");
    auto store = makeStore();
    startReady(*store);
    if (QTest::currentTestFailed()) {
        return;
    }
    QVERIFY(!log().join(u'\n').contains(u"remote-add"_s));

    AppsModel *apps = store->apps();
    QTRY_COMPARE(apps->updateCount(), 1);
    QVERIFY(apps->isInstalled(Editor));
    const QVariantMap editor = apps->app(Editor);
    QCOMPARE(editor.value(u"installedVersion"_s).toString(), u"2.0"_s);
    QCOMPARE(editor.value(u"version"_s).toString(), u"2.1"_s);
    QCOMPARE(editor.value(u"updateAvailable"_s).toBool(), true);
    QCOMPARE(editor.value(u"inCatalogue"_s).toBool(), true);

    // Discover lists the catalogue; Installed also lists apps from elsewhere.
    QCOMPARE(apps->rowCount(), 2);
    apps->setSection(u"installed"_s);
    QCOMPARE(apps->rowCount(), 2);
    QCOMPARE(apps->data(apps->index(0), AppsModel::NameRole).toString(), u"Example Editor"_s);
    QCOMPARE(apps->data(apps->index(1), AppsModel::NameRole).toString(), u"Tool"_s);
    QCOMPARE(apps->data(apps->index(1), AppsModel::InCatalogueRole).toBool(), false);
    apps->setSection(u"updates"_s);
    QCOMPARE(apps->rowCount(), 1);
    apps->setSection(u"discover"_s);
    apps->setCategory(u"Game"_s);
    QCOMPARE(apps->rowCount(), 1);
    QCOMPARE(apps->data(apps->index(0), AppsModel::AppIdRole).toString(), u"org.example.Game"_s);
    apps->setCategory(QString());
    apps->setSearchText(u"PLAIN TEXT"_s); // summaries match too
    QCOMPARE(apps->rowCount(), 1);
    QCOMPARE(apps->indexOf(Editor), 0);
}

void StoreTest::offlineWithoutCatalogue()
{
    write(u"remotes"_s, FlathubRemote);
    write(u"fail-update"_s, "error: Unable to load summary from remote flathub: Could not resolve hostname\n");
    auto store = makeStore();
    store->start();
    QTRY_VERIFY(store->state() == u"offline"_s && !store->busy());
    QVERIFY(store->offline());
    QCOMPARE(store->errorString(), u"Unable to load summary from remote flathub: Could not resolve hostname"_s);
}

void StoreTest::offlineWithEarlierCatalogue()
{
    QVERIFY(QDir().mkpath(m_active));
    QVERIFY(QFile::copy(QDir(m_state).filePath(u"appstream.xml"_s), QDir(m_active).filePath(u"appstream.xml"_s)));
    write(u"remotes"_s, FlathubRemote);
    write(u"fail-update"_s, "error: Could not resolve hostname\n");
    auto store = makeStore();
    store->start();
    QTRY_VERIFY(store->offline() && !store->busy());
    QCOMPARE(store->state(), u"ready"_s);
    QCOMPARE(store->apps()->catalogueSize(), 2);
}

void StoreTest::installsAndRemoves()
{
    auto store = makeStore();
    startReady(*store);
    if (QTest::currentTestFailed()) {
        return;
    }
    QSignalSpy finished(store.get(), &Store::operationFinished);
    QStringList progress;
    connect(store.get(), &Store::progressTextChanged, this, [&] {
        progress.append(store->progressText());
    });

    QVERIFY(store->install(Editor));
    QVERIFY(store->busy());
    QCOMPARE(store->operation(), u"install"_s);
    QCOMPARE(store->busyAppId(), Editor);
    QVERIFY(!store->install(u"org.example.Game"_s)); // one change at a time
    QTRY_COMPARE(finished.count(), 1);
    QCOMPARE(finished.at(0), QVariantList({u"install"_s, Editor}));
    QVERIFY(store->apps()->isInstalled(Editor));
    QVERIFY(!store->busy());
    QVERIFY(log().contains(u"install --user --noninteractive -y flathub org.example.Editor"_s));
    QVERIFY2(progress.contains(u"Installing app/org.example.Editor/x86_64/stable"_s), qPrintable(progress.join(u'|')));

    QVERIFY(store->remove(Editor));
    QTRY_COMPARE(finished.count(), 2);
    QCOMPARE(finished.at(1), QVariantList({u"remove"_s, Editor}));
    QVERIFY(!store->apps()->isInstalled(Editor));
    QVERIFY(log().contains(u"uninstall --user --noninteractive -y org.example.Editor"_s));
}

void StoreTest::reportsFailedInstall()
{
    auto store = makeStore();
    startReady(*store);
    if (QTest::currentTestFailed()) {
        return;
    }
    write(u"fail-install"_s, "Looking for matches\nerror: No remote refs found for org.example.Editor\n");
    QSignalSpy failed(store.get(), &Store::operationFailed);
    QVERIFY(store->install(Editor));
    QTRY_COMPARE(failed.count(), 1);
    QCOMPARE(failed.at(0), QVariantList({u"install"_s, Editor, u"No remote refs found for org.example.Editor"_s}));
    QVERIFY(!store->apps()->isInstalled(Editor));
    QVERIFY(!store->busy());
}

void StoreTest::updatesAll()
{
    write(u"installed"_s, "org.example.Editor\tExample Editor\t2.0\tflathub\n");
    write(u"updates"_s, "org.example.Editor\t2.1\n");
    auto store = makeStore();
    startReady(*store);
    if (QTest::currentTestFailed()) {
        return;
    }
    QTRY_COMPARE(store->apps()->updateCount(), 1);
    QSignalSpy finished(store.get(), &Store::operationFinished);
    QVERIFY(store->updateAll());
    QTRY_COMPARE(finished.count(), 1);
    QCOMPARE(finished.at(0), QVariantList({u"update"_s, QString()}));
    QVERIFY(log().contains(u"update --user --noninteractive -y"_s));
    QCOMPARE(store->apps()->updateCount(), 0);
}

void StoreTest::readsPermissions()
{
    auto store = makeStore();
    startReady(*store);
    if (QTest::currentTestFailed()) {
        return;
    }
    write(u"metadata"_s, "[Application]\nname=org.example.Editor\n\n[Context]\nshared=network;\n");
    QSignalSpy ready(store.get(), &Store::permissionsReady);
    store->requestPermissions(Editor);
    QTRY_COMPARE(ready.count(), 1);
    QCOMPARE(ready.at(0).at(0).toString(), Editor);
    QCOMPARE(ready.at(0).at(1).toStringList(), QStringList({u"Network access"_s}));
    QVERIFY(log().contains(u"remote-info --user --show-metadata flathub org.example.Editor"_s));

    QSignalSpy failed(store.get(), &Store::permissionsFailed);
    write(u"fail-remote-info"_s, "error: Could not resolve hostname\n");
    store->requestPermissions(Editor);
    QTRY_COMPARE(failed.count(), 1);
    QCOMPARE(failed.at(0), QVariantList({Editor, u"Could not resolve hostname"_s}));
}

void StoreTest::opensOnlyInstalledApps()
{
    write(u"installed"_s, "org.example.Editor\tExample Editor\t2.0\tflathub\n");
    auto store = makeStore();
    startReady(*store);
    if (QTest::currentTestFailed()) {
        return;
    }
    QTRY_VERIFY(store->apps()->isInstalled(Editor));
    QVERIFY(!store->open(u"org.example.Game"_s));
    QVERIFY(store->open(Editor));
    QTRY_VERIFY(QFile::exists(QDir(m_state).filePath(u"ran-org.example.Editor"_s)));
    QVERIFY(log().contains(u"run org.example.Editor"_s));
    QVERIFY(!log().join(u'\n').contains(u"run org.example.Game"_s));
}

void StoreTest::refusesInvalidIds()
{
    auto store = makeStore();
    startReady(*store);
    if (QTest::currentTestFailed()) {
        return;
    }
    const QStringList before = log();
    QSignalSpy failed(store.get(), &Store::permissionsFailed);
    const QStringList ids = {u"--help"_s, u"org.example"_s, u"org.example.App;rm -rf ~"_s, u"../../etc/passwd"_s, QString()};
    for (const QString &id : ids) {
        QVERIFY2(!store->install(id), qPrintable(id));
        QVERIFY2(!store->remove(id), qPrintable(id));
        QVERIFY2(!store->open(id), qPrintable(id));
        store->requestPermissions(id);
    }
    QCOMPARE(failed.count(), ids.size());
    QVERIFY(!store->busy());
    QTest::qWait(200);
    QCOMPARE(log(), before);
}

void StoreTest::missingFlatpakIsAnError()
{
    Store store(QDir(m_dir->path()).filePath(u"no-such-flatpak"_s), m_data, m_repo);
    store.start();
    QTRY_COMPARE(store.state(), u"error"_s);
    QVERIFY(!store.errorString().isEmpty());
}

QTEST_GUILESS_MAIN(StoreTest)

#include "tst_store.moc"
