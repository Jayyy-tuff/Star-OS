// SPDX-License-Identifier: GPL-3.0-or-later
// The flatpak output parsers: tables as flatpak prints them without a
// terminal (tab-separated, no title row), permissions from app metadata, and
// the app id check that guards every command line.

#include "flatpakoutput.h"

#include <QTest>

class ParsersTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void remoteNames();
    void installedApps();
    void updates();
    void permissions();
    void permissionsOfEmptyMetadata();
    void appIds_data();
    void appIds();
};

void ParsersTest::remoteNames()
{
    const QString output = QStringLiteral("flathub\thttps://dl.flathub.org/repo/\nexample\thttps://example.org/repo/\n\n");
    QCOMPARE(FlatpakOutput::remoteNames(output), QStringList({"flathub", "example"}));
    QCOMPARE(FlatpakOutput::remoteNames(QString()), QStringList());
}

void ParsersTest::installedApps()
{
    const QString output = QStringLiteral(
        "org.example.Editor\tExample Editor\t2.1\tflathub\n"
        "not an id\tBroken\t1.0\tflathub\n"
        "org.example.NoName\t\t\texample\n");
    const auto apps = FlatpakOutput::installedApps(output);
    QCOMPARE(apps.size(), 2);
    QCOMPARE(apps.at(0).id, QStringLiteral("org.example.Editor"));
    QCOMPARE(apps.at(0).name, QStringLiteral("Example Editor"));
    QCOMPARE(apps.at(0).version, QStringLiteral("2.1"));
    QCOMPARE(apps.at(0).origin, QStringLiteral("flathub"));
    // Without a name the id is shown.
    QCOMPARE(apps.at(1).name, QStringLiteral("org.example.NoName"));
    QCOMPARE(apps.at(1).version, QString());
    QCOMPARE(apps.at(1).origin, QStringLiteral("example"));
}

void ParsersTest::updates()
{
    const auto result = FlatpakOutput::updates(QStringLiteral("org.example.Editor\t2.2\n--bad\t1\norg.example.Game\t\n"));
    QCOMPARE(result.size(), 2);
    QCOMPARE(result.value(QStringLiteral("org.example.Editor")), QStringLiteral("2.2"));
    QVERIFY(result.contains(QStringLiteral("org.example.Game")));
}

void ParsersTest::permissions()
{
    const QString metadata = QStringLiteral(
        "[Application]\n"
        "name=org.example.Editor\n"
        "runtime=org.freedesktop.Platform/x86_64/24.08\n"
        "command=editor\n"
        "\n"
        "[Context]\n"
        "shared=network;ipc;\n"
        "sockets=x11;wayland;pulseaudio;!session-bus;\n"
        "devices=dri;\n"
        "filesystems=xdg-documents;home:ro;/opt/data:create;!host;\n"
        "\n"
        "[Session Bus Policy]\n"
        "org.freedesktop.Notifications=talk\n"
        "org.example.Editor.*=own\n"
        "org.example.Ignored=none\n"
        "\n"
        "[System Bus Policy]\n"
        "org.freedesktop.UPower=talk\n");
    QCOMPARE(FlatpakOutput::permissions(metadata),
             QStringList({
                 "Network access",
                 "X11 display: can see other X11 windows and their input",
                 "Sound playback and recording",
                 "Graphics acceleration",
                 "Your documents folder",
                 "Your home folder (read only)",
                 "The folder /opt/data",
                 "Owns org.example.Editor.* on the session bus",
                 "Talks to org.freedesktop.Notifications on the session bus",
                 "Talks to org.freedesktop.UPower on the system bus",
             }));
}

void ParsersTest::permissionsOfEmptyMetadata()
{
    QCOMPARE(FlatpakOutput::permissions(QStringLiteral("[Application]\nname=org.example.Tiny\n")), QStringList());
    QCOMPARE(FlatpakOutput::permissions(QString()), QStringList());
}

void ParsersTest::appIds_data()
{
    QTest::addColumn<QString>("id");
    QTest::addColumn<bool>("valid");
    QTest::newRow("three parts") << QStringLiteral("org.example.Editor") << true;
    QTest::newRow("dash in last part") << QStringLiteral("io.github.someone.App-Name") << true;
    QTest::newRow("underscores") << QStringLiteral("com.example_corp.my_app") << true;
    QTest::newRow("empty") << QString() << false;
    QTest::newRow("option") << QStringLiteral("--help") << false;
    QTest::newRow("two parts") << QStringLiteral("org.example") << false;
    QTest::newRow("empty part") << QStringLiteral("org..example.App") << false;
    QTest::newRow("leading digit") << QStringLiteral("org.1example.App") << false;
    QTest::newRow("dash in middle part") << QStringLiteral("org.ex-ample.App") << false;
    QTest::newRow("shell text") << QStringLiteral("org.example.App;rm") << false;
    QTest::newRow("ref") << QStringLiteral("app/org.example.App/x86_64/stable") << false;
    QTest::newRow("space") << QStringLiteral("org.example.App ") << false;
    QTest::newRow("too long") << QStringLiteral("org.example.") + QString(250, QLatin1Char('a')) << false;
}

void ParsersTest::appIds()
{
    QFETCH(QString, id);
    QFETCH(bool, valid);
    QCOMPARE(FlatpakOutput::isValidAppId(id), valid);
}

QTEST_GUILESS_MAIN(ParsersTest)

#include "tst_parsers.moc"
