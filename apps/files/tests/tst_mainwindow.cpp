// SPDX-License-Identifier: GPL-3.0-or-later
// Loads the real Files window (StarOS.Files Main) with the real models on a
// temporary home folder and checks what the session test and screen readers
// rely on: the title, the "Places" list and the "Folder contents" list.
#include <QDir>
#include <QQmlApplicationEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>
#include <QtQml/QQmlExtensionPlugin>

Q_IMPORT_QML_PLUGIN(StarOS_FilesPlugin)

class MainWindowTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    void showsFolderWithAccessibleViews()
    {
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QVERIFY(QDir(dir.path()).mkdir(QStringLiteral("Projects")));

        QQmlApplicationEngine engine;
        engine.addImportPath(QStringLiteral(STAROS_SHELL_QML_DIR));
        engine.setInitialProperties({{QStringLiteral("initialUrl"), QUrl::fromLocalFile(dir.path())}});
        engine.loadFromModule("StarOS.Files", "Main");
        QCOMPARE(engine.rootObjects().size(), 1);

        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().constFirst());
        QVERIFY(window);
        const QString folderName = QDir(dir.path()).dirName();
        QTRY_COMPARE(window->title(), QStringLiteral("Files — %1").arg(folderName));

        auto *places = window->findChild<QQuickItem *>(QStringLiteral("places"));
        auto *contents = window->findChild<QQuickItem *>(QStringLiteral("folderContents"));
        auto *toolbar = window->findChild<QQuickItem *>(QStringLiteral("toolbar"));
        QVERIFY(places && contents && toolbar);
        QTRY_COMPARE(contents->property("count").toInt(), 1);
        QVERIFY(places->property("count").toInt() >= 3); // Home, Trash, Computer
    }
};

QTEST_MAIN(MainWindowTest)

#include "tst_mainwindow.moc"
