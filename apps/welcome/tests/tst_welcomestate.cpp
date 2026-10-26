// SPDX-License-Identifier: GPL-3.0-or-later
// WelcomeState: the tour is shown until finished, finishing is kept in the
// configuration file, and apps open through the launcher (a recorder here).

#include "welcomestate.h"

#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

using namespace Qt::StringLiterals;

class WelcomeStateTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    void finishIsKept()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath(u"staros-welcomerc"_s);
        WelcomeState state;
        state.setConfigPath(path);
        QVERIFY(!state.shownBefore());
        QVERIFY(!WelcomeState::shownBefore(path));
        QSignalSpy changed(&state, &WelcomeState::shownBeforeChanged);
        state.finish();
        QVERIFY(state.shownBefore());
        QCOMPARE(changed.count(), 1);
        state.finish();
        QCOMPARE(changed.count(), 1);
        QVERIFY(WelcomeState::shownBefore(path));
        WelcomeState other;
        other.setConfigPath(path);
        QVERIFY(other.shownBefore());
    }

    void defaultPathIsTheUsersConfig()
    {
        QVERIFY(WelcomeState::defaultConfigPath().endsWith(u"/staros-welcomerc"_s));
        QVERIFY(WelcomeState::defaultConfigPath().startsWith(
            QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)));
    }

    void opensApps()
    {
        WelcomeState state;
        QStringList opened;
        state.setLauncher([&opened](const QString &id) {
            opened.append(id);
            return id != u"missing.desktop"_s;
        });
        QSignalSpy spy(&state, &WelcomeState::opened);
        QVERIFY(state.open(u"org.staros.lens.desktop"_s));
        QVERIFY(!state.open(u"missing.desktop"_s));
        QCOMPARE(opened, QStringList({u"org.staros.lens.desktop"_s, u"missing.desktop"_s}));
        QCOMPARE(spy.count(), 1);
    }
};

QTEST_GUILESS_MAIN(WelcomeStateTest)

#include "tst_welcomestate.moc"
