// SPDX-License-Identifier: GPL-3.0-or-later
// Loads the real Star Storage window (StarOS.Storage Main) with StarOS.System
// from Qt's QML directory. Whether the installed helper is there or not, the
// window must leave "loading" and show the disk list or why it has none.
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>
#include <QtQml/QQmlExtensionPlugin>

Q_IMPORT_QML_PLUGIN(StarOS_StoragePlugin)

class MainWindowTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void showsDisksOrWhyNot()
    {
        QQmlApplicationEngine engine;
        engine.addImportPath(QStringLiteral(STAROS_SHELL_QML_DIR));
        engine.loadFromModule("StarOS.Storage", "Main");
        QCOMPARE(engine.rootObjects().size(), 1);

        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QVERIFY(window);
        QCOMPARE(window->title(), QStringLiteral("Star Storage"));
        QVERIFY(window->isVisible());

        auto *disks = window->findChild<QQuickItem *>(QStringLiteral("disks"));
        auto *statusText = window->findChild<QQuickItem *>(QStringLiteral("statusText"));
        auto *listState = window->findChild<QQuickItem *>(QStringLiteral("listState"));
        QVERIFY(disks && statusText && listState);
        // SystemStatus answered: the status line says where changes go.
        QTRY_VERIFY(!statusText->property("text").toString().isEmpty());
        // The helper answered, or its absence is reported: no longer looking.
        QTRY_VERIFY_WITH_TIMEOUT(listState->property("text").toString() != QStringLiteral("Looking for disks…"), 20000);
    }
};

QTEST_MAIN(MainWindowTest)

#include "tst_mainwindow.moc"
