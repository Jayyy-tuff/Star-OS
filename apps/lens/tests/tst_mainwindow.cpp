// SPDX-License-Identifier: GPL-3.0-or-later
// Loads the real Star Lens window (StarOS.Lens Main). Without KWin (the tests
// have no session bus) the screenshot fails, and the window must show why
// instead of staying hidden.
#include "captureprovider.h"

#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <QtQml/QQmlExtensionPlugin>

Q_IMPORT_QML_PLUGIN(StarOS_LensPlugin)

class MainWindowTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void showsWhyTheScreenshotFailed()
    {
        QQmlApplicationEngine engine;
        engine.addImportPath(QStringLiteral(STAROS_SHELL_QML_DIR));
        engine.addImageProvider(QStringLiteral("lens"), new CaptureProvider);
        engine.loadFromModule("StarOS.Lens", "Main");
        QCOMPARE(engine.rootObjects().size(), 1);

        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QVERIFY(window);
        QCOMPARE(window->title(), QStringLiteral("Star Lens"));
        QTRY_VERIFY_WITH_TIMEOUT(window->isVisible(), 20000);

        auto *errorView = window->findChild<QQuickItem *>(QStringLiteral("errorView"));
        auto *errorText = window->findChild<QQuickItem *>(QStringLiteral("errorText"));
        auto *capture = window->findChild<QQuickItem *>(QStringLiteral("capture"));
        QVERIFY(errorView && errorText && capture);
        QVERIFY(errorView->isVisible());
        QVERIFY(!capture->isVisible());
        const QString text = errorText->property("text").toString();
        QVERIFY2(text.startsWith(QStringLiteral("Star Lens could not take a screenshot: ")), qPrintable(text));
    }
};

QTEST_MAIN(MainWindowTest)

#include "tst_mainwindow.moc"
