// SPDX-License-Identifier: GPL-3.0-or-later
// NetworkStatus's reading of systemd-networkd's Describe() JSON and iwd's
// signal strength; AudioControl, DisplayControl and NetworkStatus without a
// sound server or the services they talk to (as in the package build).

#include "audiocontrol.h"
#include "displaycontrol.h"
#include "networkstatus.h"

#include <QSignalSpy>
#include <QTest>

namespace
{
QByteArray describe(const QByteArray &interfaces)
{
    return "{\"Interfaces\":[" + interfaces + "],\"OperationalState\":\"routable\"}";
}

const QByteArray Loopback = R"({"Index":1,"Name":"lo","Type":"loopback","OperationalState":"carrier","AdministrativeState":"unmanaged"})";
const QByteArray WiredUp = R"({"Index":2,"Name":"enp1s0","Type":"ether","OperationalState":"routable","AdministrativeState":"configured"})";
const QByteArray WiredDown = R"({"Index":2,"Name":"enp1s0","Type":"ether","OperationalState":"no-carrier","AdministrativeState":"configured"})";
const QByteArray WifiUp = R"({"Index":3,"Name":"wlan0","Type":"wlan","OperationalState":"routable","AdministrativeState":"configured","SSID":"Star Cafe"})";
const QByteArray WifiConfiguring =
    R"({"Index":3,"Name":"wlan0","Type":"wlan","OperationalState":"dormant","AdministrativeState":"configuring","SSID":"Star Cafe"})";
const QByteArray WiredNoRoute = R"({"Index":2,"Name":"enp1s0","Type":"ether","OperationalState":"degraded","AdministrativeState":"configured"})";
}

class ControlsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void parsesLinks()
    {
        const QList<NetworkStatus::Link> links = NetworkStatus::parseLinks(describe(Loopback + "," + WifiUp));
        QCOMPARE(links.size(), 2);
        QCOMPARE(links.at(1).name, QStringLiteral("wlan0"));
        QCOMPARE(links.at(1).type, QStringLiteral("wlan"));
        QCOMPARE(links.at(1).ssid, QStringLiteral("Star Cafe"));
        QVERIFY(NetworkStatus::parseLinks("not json").isEmpty());
    }

    void summarizes_data()
    {
        QTest::addColumn<QByteArray>("interfaces");
        QTest::addColumn<QString>("state");
        QTest::addColumn<QString>("kind");
        QTest::addColumn<QString>("name");
        QTest::newRow("wired") << QByteArray(Loopback + "," + WiredUp) << "connected" << "wired" << "";
        QTest::newRow("wifi") << QByteArray(Loopback + "," + WifiUp) << "connected" << "wifi" << "Star Cafe";
        QTest::newRow("the routable link wins") << QByteArray(WiredDown + "," + WifiUp) << "connected" << "wifi" << "Star Cafe";
        QTest::newRow("connecting") << QByteArray(WiredDown + "," + WifiConfiguring) << "connecting" << "wifi" << "Star Cafe";
        QTest::newRow("no route") << QByteArray(WiredNoRoute) << "limited" << "wired" << "";
        QTest::newRow("cable out") << QByteArray(Loopback + "," + WiredDown) << "offline" << "" << "";
        QTest::newRow("loopback only") << QByteArray(Loopback) << "offline" << "" << "";
        QTest::newRow("nothing") << QByteArray() << "offline" << "" << "";
    }

    void summarizes()
    {
        QFETCH(QByteArray, interfaces);
        QFETCH(QString, state);
        QFETCH(QString, kind);
        QFETCH(QString, name);
        const NetworkStatus::Summary summary = NetworkStatus::summarize(NetworkStatus::parseLinks(describe(interfaces)));
        QCOMPARE(summary.state, state);
        QCOMPARE(summary.kind, kind);
        QCOMPARE(summary.networkName, name);
    }

    void strengthBars()
    {
        QCOMPARE(NetworkStatus::strengthBars(-3000), 4);
        QCOMPARE(NetworkStatus::strengthBars(-5000), 4);
        QCOMPARE(NetworkStatus::strengthBars(-6500), 2);
        QCOMPARE(NetworkStatus::strengthBars(-7000), 2);
        QCOMPARE(NetworkStatus::strengthBars(-9500), 1);
    }

    // Nothing to talk to: everything reads as absent and calls do nothing.
    void withoutServices()
    {
        NetworkStatus network;
        network.setInterval(0);
        QCOMPARE(network.interval(), 0);
        QVERIFY(!network.wifiAvailable());
        network.scan();
        network.connectTo(QStringLiteral("/net/connman/iwd/0/3/no_such_network"));
        network.submitPassphrase(QStringLiteral("secret"));
        QSignalSpy done(&network, &NetworkStatus::passphraseDone);
        network.cancelPassphrase();
        QCOMPARE(done.count(), 1);

        DisplayControl display;
        QVERIFY(!display.brightnessAvailable());
        display.setBrightness(50);
        QCOMPARE(display.brightness(), 0);

        AudioControl audio;
        QVERIFY(!audio.available());
        QCOMPARE(audio.volume(), 0);
        audio.setVolume(40);
        audio.raise();
        QCOMPARE(audio.volume(), 0);
        QVERIFY(!audio.muted());
    }
};

QTEST_MAIN(ControlsTest)

#include "tst_controls.moc"
