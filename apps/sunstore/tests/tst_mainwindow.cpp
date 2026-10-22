// SPDX-License-Identifier: GPL-3.0-or-later
// Loads the real Sun Store window (StarOS.SunStore Main) with the real Store.
// A fake flatpak without remotes comes first in PATH, so the first-run
// consent page shows; checks what the session test and screen readers rely
// on: the title, the consent text and the "Enable Flathub" button.
#include "fakeflatpak.h"

#include <QDir>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QtQml/QQmlExtensionPlugin>

Q_IMPORT_QML_PLUGIN(StarOS_SunStorePlugin)

class MainWindowTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        QStandardPaths::setTestModeEnabled(true);
        const QString program = FakeFlatpak::create(m_dir.path(), m_dir.filePath(QStringLiteral("active")));
        QVERIFY(!program.isEmpty());
        qputenv("PATH", QFile::encodeName(m_dir.path()) + ':' + qgetenv("PATH"));
    }

    void showsConsentOnFirstRun()
    {
        QQmlApplicationEngine engine;
        engine.addImportPath(QStringLiteral(STAROS_SHELL_QML_DIR));
        engine.loadFromModule("StarOS.SunStore", "Main");
        QCOMPARE(engine.rootObjects().size(), 1);

        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QVERIFY(window);
        QCOMPARE(window->title(), QStringLiteral("Sun Store"));

        auto *consent = window->findChild<QQuickItem *>(QStringLiteral("consentPage"));
        auto *enable = window->findChild<QQuickItem *>(QStringLiteral("enableFlathubButton"));
        auto *message = window->findChild<QQuickItem *>(QStringLiteral("consentMessage"));
        QVERIFY(consent && enable && message);
        QTRY_VERIFY(consent->isVisible());
        QCOMPARE(enable->property("text").toString(), QStringLiteral("Enable Flathub"));
        QCOMPARE(message->property("text").toString(),
                 QStringLiteral("Sun Store installs apps from Flathub, a community app store. Star OS does not review these apps."));
        QCOMPARE(FakeFlatpak::log(m_dir.path()), QStringList({QStringLiteral("remotes --user --columns=name,url")}));
    }

private:
    QTemporaryDir m_dir;
};

QTEST_MAIN(MainWindowTest)

#include "tst_mainwindow.moc"
