// SPDX-License-Identifier: GPL-3.0-or-later
// Steam's KeyValues files and GameLibrary against its own desktop files (a
// "system" and a Flatpak export directory on XDG_DATA_DIRS, see
// tests/CMakeLists.txt) and a fixture Steam folder with two libraries.
// Launches go to a recorder; nothing is started.

#include "gamelibrary.h"
#include "steamlibrary.h"

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include <KConfig>
#include <KConfigGroup>
#include <KSycoca>
#include <kservice_export.h>

#include <memory>

extern KSERVICE_EXPORT int ksycoca_ms_between_checks;

using namespace Qt::StringLiterals;

namespace
{
QString dataRoot()
{
    return QString::fromLocal8Bit(qgetenv("STAROS_TEST_DATA"));
}

void writeFile(const QString &path, const QByteArray &content)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(content);
}

void writeDesktop(const QString &directory, const QString &id, const QString &name, const QString &extra)
{
    writeFile(directory + u'/' + id + u".desktop"_s,
              u"[Desktop Entry]\nType=Application\nName=%1\nExec=true\nIcon=applications-games\n%2"_s.arg(name, extra).toUtf8());
}

QByteArray manifest(const QByteArray &appId, const QByteArray &name, const QByteArray &flags, const QByteArray &extra = {})
{
    return "\"AppState\"\n{\n\t\"appid\"\t\t\"" + appId + "\"\n\t\"Universe\"\t\t\"1\"\n\t\"name\"\t\t\"" + name
        + "\"\n\t\"StateFlags\"\t\t\"" + flags + "\"\n" + extra + "\t\"UserConfig\"\n\t{\n\t\t\"language\"\t\t\"english\"\n\t}\n}\n";
}

QStringList names(const GameLibrary &library)
{
    QStringList list;
    for (int row = 0; row < library.rowCount(); ++row) {
        list.append(library.data(library.index(row), GameLibrary::NameRole).toString());
    }
    return list;
}
}

class GameLibraryTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    QStringList m_launches;

    QString steamRoot() const
    {
        return m_dir.filePath(u"home/.local/share/Steam"_s);
    }

    std::unique_ptr<GameLibrary> makeLibrary()
    {
        auto library = std::make_unique<GameLibrary>();
        library->setLauncher([this](const QString &kind, const QString &target, bool gameMode) {
            m_launches.append(kind + u' ' + target + (gameMode ? u" gamemode"_s : QString()));
            return !target.contains(u"broken"_s, Qt::CaseInsensitive);
        });
        library->setGameModeAvailable(true);
        library->setConfigPath(m_dir.filePath(u"staros-gamesrc"_s));
        library->setSteamRoots({steamRoot(), m_dir.filePath(u"home/.steam/steam"_s)});
        return library;
    }

private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
        ksycoca_ms_between_checks = 0;
        QVERIFY(m_dir.isValid());
        QVERIFY(!dataRoot().isEmpty());
        QDir(dataRoot()).removeRecursively();
        QDir(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)).removeRecursively();

        const QString system = dataRoot() + u"/system/applications"_s;
        const QString flatpak = dataRoot() + u"/flatpak/exports/share/applications"_s;
        writeDesktop(system, u"org.example.Asteroids"_s, u"Asteroid Run"_s, u"Categories=Game;ArcadeGame;\n"_s);
        writeDesktop(system, u"org.example.Chess"_s, u"chess"_s, u"Categories=Game;BoardGame;\n"_s);
        writeDesktop(system, u"org.example.Emu"_s, u"Retro Emulator"_s, u"Categories=Game;Emulator;\n"_s);
        writeDesktop(system, u"org.example.Editor"_s, u"Text Editor"_s, u"Categories=Utility;\n"_s);
        writeDesktop(system, u"org.example.HiddenGame"_s, u"Hidden Game"_s, u"Categories=Game;\nNoDisplay=true\n"_s);
        writeDesktop(system, u"org.example.Broken"_s, u"Broken Game"_s, u"Categories=Game;\n"_s);
        writeDesktop(system, u"steam"_s, u"Steam"_s, u"Categories=Network;FileTransfer;Game;\n"_s);
        writeDesktop(system, u"org.staros.games"_s, u"Game Center"_s, u"Categories=Qt;Game;\n"_s);
        writeFile(system + u"/Portal 2.desktop"_s,
                  "[Desktop Entry]\nType=Application\nName=Portal 2\nExec=steam steam://rungameid/620\nIcon=steam_icon_620\n"
                  "Categories=Game;\n");
        writeDesktop(flatpak, u"org.example.Kart"_s, u"Super Kart"_s, u"Categories=Game;\nX-Flatpak=org.example.Kart\n"_s);

        // Steam: the main library and a second one on another disk.
        const QString second = m_dir.filePath(u"games-disk/SteamLibrary"_s);
        writeFile(steamRoot() + u"/steamapps/libraryfolders.vdf"_s,
                  "\"libraryfolders\"\n{\n\t\"0\"\n\t{\n\t\t\"path\"\t\t\"" + steamRoot().toUtf8()
                      + "\"\n\t\t\"apps\"\n\t\t{\n\t\t\t\"620\"\t\t\"1\"\n\t\t}\n\t}\n\t\"1\"\n\t{\n\t\t\"path\"\t\t\""
                      + second.toUtf8() + "\"\n\t}\n}\n");
        writeFile(steamRoot() + u"/steamapps/appmanifest_620.acf"_s, manifest("620", "Portal 2", "4"));
        writeFile(steamRoot() + u"/steamapps/appmanifest_400.acf"_s,
                  manifest("400", "Portal", "4", "\t\"LastPlayed\"\t\t\"1700000000\"\n"));
        writeFile(steamRoot() + u"/steamapps/appmanifest_1070560.acf"_s, manifest("1070560", "Steam Linux Runtime 1.0 (scout)", "4"));
        writeFile(steamRoot() + u"/steamapps/appmanifest_1493710.acf"_s, manifest("1493710", "Proton Experimental", "4"));
        writeFile(steamRoot() + u"/steamapps/appmanifest_70.acf"_s, manifest("70", "Half-Life", "1026"));
        writeFile(second + u"/steamapps/appmanifest_220.acf"_s, manifest("220", "Half-Life 2", "4"));
        // ~/.steam/steam is a link to the same folder: read once.
        QDir().mkpath(m_dir.filePath(u"home/.steam"_s));
        QVERIFY(QFile::link(steamRoot(), m_dir.filePath(u"home/.steam/steam"_s)));
    }

    void init()
    {
        m_launches.clear();
        QFile::remove(m_dir.filePath(u"staros-gamesrc"_s));
    }

    void parsesKeyValues()
    {
        const QVariantMap map = SteamLibrary::parseKeyValues(
            "// a comment\n\"Root\"\n{\n\t\"Key\"\t\"va\\\"lue\" // trailing\n\t\"Child\" { \"A\" \"1\" }\n\tbare token\n}\n");
        const QVariantMap root = map.value(u"root"_s).toMap();
        QCOMPARE(root.value(u"key"_s).toString(), u"va\"lue"_s);
        QCOMPARE(root.value(u"child"_s).toMap().value(u"a"_s).toString(), u"1"_s);
        QCOMPARE(root.value(u"bare"_s).toString(), u"token"_s);
        QVERIFY(SteamLibrary::parseKeyValues("\"unterminated\" {").value(u"unterminated"_s).toMap().isEmpty());
        QVERIFY(SteamLibrary::parseKeyValues("").isEmpty());
    }

    void readsLibraryFolders()
    {
        QCOMPARE(SteamLibrary::libraryFolders("\"libraryfolders\" { \"0\" { \"path\" \"/a\" } \"1\" { \"path\" \"/b\" } "
                                              "\"contentstatsid\" \"123\" }"),
                 QStringList({u"/a"_s, u"/b"_s}));
        // The layout before 2021.
        QCOMPARE(SteamLibrary::libraryFolders("\"LibraryFolders\" { \"TimeNextStatsReport\" \"1\" \"1\" \"/old\" }"),
                 QStringList({u"/old"_s}));
    }

    void readsManifests()
    {
        const std::optional<SteamLibrary::Game> portal = SteamLibrary::parseManifest(manifest("400", "Portal", "4", "\t\"LastPlayed\"\t\t\"1700000000\"\n"));
        QVERIFY(portal);
        QCOMPARE(portal->appId, u"400"_s);
        QCOMPARE(portal->name, u"Portal"_s);
        QCOMPARE(portal->lastPlayed, QDateTime::fromSecsSinceEpoch(1700000000));
        QVERIFY(!SteamLibrary::parseManifest(manifest("70", "Half-Life", "1026")));
        QVERIFY(!SteamLibrary::parseManifest(manifest("228980", "Steamworks Common Redistributables", "4")));
        QVERIFY(!SteamLibrary::parseManifest("garbage"));
        QVERIFY(SteamLibrary::isTool(u"1493710"_s, u"Proton Experimental"_s));
        QVERIFY(!SteamLibrary::isTool(u"220"_s, u"Half-Life 2"_s));
    }

    void scansEachLibraryOnce()
    {
        const QList<SteamLibrary::Game> games = SteamLibrary::scan({steamRoot(), m_dir.filePath(u"home/.steam/steam"_s)});
        QStringList found;
        for (const SteamLibrary::Game &game : games) {
            found.append(game.name);
        }
        found.sort();
        QCOMPARE(found, QStringList({u"Half-Life 2"_s, u"Portal"_s, u"Portal 2"_s}));
    }

    void listsGames()
    {
        auto library = makeLibrary();
        // Sorted by name; the Steam client, Game Center itself, other apps and
        // hidden entries are left out; Portal 2 comes from its desktop entry.
        QCOMPARE(names(*library), QStringList({u"Asteroid Run"_s, u"Broken Game"_s, u"chess"_s, u"Half-Life 2"_s, u"Portal"_s,
                                               u"Portal 2"_s, u"Retro Emulator"_s, u"Super Kart"_s}));
        QCOMPARE(library->totalCount(), 8);
        QCOMPARE(library->property("count").toInt(), 8);
        QCOMPARE(library->steamDesktopId(), u"steam.desktop"_s);
        const QVariantMap portal = library->get(4);
        QCOMPARE(portal.value(u"gameId"_s).toString(), u"steam:400"_s);
        QCOMPARE(portal.value(u"source"_s).toString(), u"steam"_s);
        QCOMPARE(portal.value(u"icon"_s).toString(), u"steam_icon_400"_s);
        QCOMPARE(portal.value(u"lastPlayed"_s).toDateTime(), QDateTime::fromSecsSinceEpoch(1700000000));
        QCOMPARE(library->get(5).value(u"source"_s).toString(), u"steam"_s);
        QCOMPARE(library->get(5).value(u"gameId"_s).toString(), u"Portal 2.desktop"_s);
        QCOMPARE(library->get(7).value(u"source"_s).toString(), u"flatpak"_s);
        QCOMPARE(library->get(0).value(u"source"_s).toString(), u"app"_s);
        QVERIFY(library->get(6).value(u"emulator"_s).toBool());
        QVERIFY(library->get(99).isEmpty());
        const QHash<int, QByteArray> roles = library->roleNames();
        QCOMPARE(roles.value(GameLibrary::NameRole), "name");
        QCOMPARE(roles.value(GameLibrary::LastPlayedRole), "lastPlayed");
    }

    void filtersAndSearch()
    {
        auto library = makeLibrary();
        QSignalSpy filterChanged(library.get(), &GameLibrary::filterChanged);
        library->setFilter(u"steam"_s);
        QCOMPARE(names(*library), QStringList({u"Half-Life 2"_s, u"Portal"_s, u"Portal 2"_s}));
        library->setFilter(u"emulators"_s);
        QCOMPARE(names(*library), QStringList({u"Retro Emulator"_s}));
        library->setFilter(u"apps"_s);
        QCOMPARE(names(*library), QStringList({u"Asteroid Run"_s, u"Broken Game"_s, u"chess"_s, u"Super Kart"_s}));
        library->setFilter(u"nonsense"_s);
        QCOMPARE(library->filter(), u"all"_s);
        QCOMPARE(filterChanged.count(), 4);
        library->setSearch(u"  PORTAL "_s);
        QCOMPARE(names(*library), QStringList({u"Portal"_s, u"Portal 2"_s}));
        library->setSearch(u"zzz"_s);
        QCOMPARE(library->rowCount(), 0);
        QCOMPARE(library->totalCount(), 8);
    }

    void launches()
    {
        auto library = makeLibrary();
        QSignalSpy launched(library.get(), &GameLibrary::launched);
        QSignalSpy failed(library.get(), &GameLibrary::launchFailed);
        QVERIFY(library->launch(0));
        QVERIFY(library->launchGame(u"steam:220"_s));
        QVERIFY(library->launchGame(u"Portal 2.desktop"_s));
        QVERIFY(!library->launchGame(u"org.example.Editor.desktop"_s));
        QVERIFY(!library->launchGame(u"org.example.Broken.desktop"_s));
        QVERIFY(!library->launch(42));
        QCOMPARE(m_launches, QStringList({u"desktop org.example.Asteroids.desktop"_s, u"url steam://rungameid/220"_s,
                                          u"desktop Portal 2.desktop"_s, u"desktop org.example.Broken.desktop"_s}));
        QCOMPARE(launched.count(), 3);
        QCOMPARE(failed.count(), 1);
        QCOMPARE(failed.at(0).at(0).toString(), u"Broken Game"_s);
        // Played now: kept in the configuration and shown after a reload.
        QVERIFY(library->get(0).value(u"lastPlayed"_s).toDateTime().secsTo(QDateTime::currentDateTime()) < 60);
        auto again = makeLibrary();
        QVERIFY(again->get(0).value(u"lastPlayed"_s).toDateTime().isValid());
        QVERIFY(again->get(3).value(u"lastPlayed"_s).toDateTime().isValid());
    }

    void gameModeAppliesToApps()
    {
        auto library = makeLibrary();
        QVERIFY(!library->gameMode());
        QSignalSpy changed(library.get(), &GameLibrary::gameModeChanged);
        library->setGameMode(true);
        QCOMPARE(changed.count(), 1);
        QVERIFY(library->launchGame(u"org.example.Asteroids.desktop"_s));
        QVERIFY(library->launchGame(u"org.example.Kart.desktop"_s));
        QVERIFY(library->launchGame(u"steam:400"_s));
        QCOMPARE(m_launches, QStringList({u"desktop org.example.Asteroids.desktop gamemode"_s, u"desktop org.example.Kart.desktop"_s,
                                          u"url steam://rungameid/400"_s}));
        // Saved, and read back by another library.
        KConfig config(m_dir.filePath(u"staros-gamesrc"_s), KConfig::SimpleConfig);
        QVERIFY(config.group(u"General"_s).readEntry("GameMode", false));
        QVERIFY(makeLibrary()->gameMode());
        // Without gamemoderun there is no game mode.
        library->setGameModeAvailable(false);
        QVERIFY(!library->gameMode());
    }

    void opensSunStoreAndSteam()
    {
        auto library = makeLibrary();
        QVERIFY(library->getGames());
        QVERIFY(library->openSteam());
        QCOMPARE(m_launches, QStringList({u"command staros-sunstore --category Game"_s, u"desktop steam.desktop"_s}));
    }
};

QTEST_GUILESS_MAIN(GameLibraryTest)

#include "tst_gamelibrary.moc"
