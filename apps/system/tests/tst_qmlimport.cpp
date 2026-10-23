// SPDX-License-Identifier: GPL-3.0-or-later
// The built module loads from its qmldir (QML_IMPORT_PATH points at the build
// tree's qml folder, laid out as installed) and creates its types.

#include <QQmlComponent>
#include <QQmlEngine>
#include <QStandardPaths>
#include <QTest>

#include <memory>

class QmlImportTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase()
    {
        QStandardPaths::setTestModeEnabled(true);
    }

    void typesLoad()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData(R"(
import QtQml
import StarOS.System
QtObject {
    property SystemStatus status: SystemStatus { interval: 0 }
    property int notes: NotesStore.count
    property string mode: status.storageMode
}
)",
                          QUrl());
        std::unique_ptr<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
        QVERIFY(!object->property("mode").toString().isEmpty());
        QVERIFY(object->property("notes").toInt() >= 0);
    }
};

QTEST_GUILESS_MAIN(QmlImportTest)

#include "tst_qmlimport.moc"
