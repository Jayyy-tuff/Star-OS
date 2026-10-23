// SPDX-License-Identifier: GPL-3.0-or-later
// NotesStore: changes are saved, a second store sees them, changes made by
// another process are picked up, and bad files and values are tolerated.

#include "notesstore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <limits>
#include <memory>

using namespace Qt::StringLiterals;

class NotesStoreTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void addUpdateMoveRemove();
    void secondStoreSeesSavedNotes();
    void externalChangeIsReloaded();
    void badFileGivesNoNotes();
    void positionsAndTextAreLimited();
    void roleNames();

private:
    QString text(const NotesStore &store, int row) const;
    std::unique_ptr<QTemporaryDir> m_dir;
    QString m_path;
};

void NotesStoreTest::init()
{
    m_dir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_dir->isValid());
    // The folder does not exist yet; saving creates it.
    m_path = m_dir->filePath(u"staros/notes.json"_s);
}

QString NotesStoreTest::text(const NotesStore &store, int row) const
{
    return store.data(store.index(row), NotesStore::NoteTextRole).toString();
}

void NotesStoreTest::addUpdateMoveRemove()
{
    NotesStore store(m_path);
    QCOMPARE(store.rowCount(), 0);
    QSignalSpy count(&store, &NotesStore::countChanged);
    const QString first = store.add(u"buy milk"_s);
    QVERIFY(!first.isEmpty());
    const QString second = store.add(QString());
    QCOMPARE(store.rowCount(), 2);
    QCOMPARE(count.count(), 2);
    QVERIFY(QFile::exists(m_path));

    store.update(first, u"buy oat milk"_s);
    QCOMPARE(text(store, 0), u"buy oat milk"_s);
    store.move(second, 0.25, 0.75);
    QCOMPARE(store.data(store.index(1), NotesStore::PosXRole).toDouble(), 0.25);
    QCOMPARE(store.data(store.index(1), NotesStore::PosYRole).toDouble(), 0.75);

    store.remove(first);
    QCOMPARE(store.rowCount(), 1);
    QCOMPARE(store.data(store.index(0), NotesStore::NoteIdRole).toString(), second);
    // Unknown ids change nothing.
    store.update(u"nope"_s, u"x"_s);
    store.move(u"nope"_s, 0.5, 0.5);
    store.remove(u"nope"_s);
    QCOMPARE(store.rowCount(), 1);
}

void NotesStoreTest::secondStoreSeesSavedNotes()
{
    {
        NotesStore store(m_path);
        const QString id = store.add(u"hello star"_s);
        store.move(id, 0.1, 0.2);
    }
    NotesStore again(m_path);
    QCOMPARE(again.rowCount(), 1);
    QCOMPARE(text(again, 0), u"hello star"_s);
    QCOMPARE(again.data(again.index(0), NotesStore::PosYRole).toDouble(), 0.2);
}

void NotesStoreTest::externalChangeIsReloaded()
{
    NotesStore one(m_path);
    NotesStore two(m_path);
    one.add(u"from one"_s);
    QTRY_COMPARE(two.rowCount(), 1);
    QCOMPARE(text(two, 0), u"from one"_s);
}

void NotesStoreTest::badFileGivesNoNotes()
{
    QVERIFY(QDir().mkpath(QFileInfo(m_path).absolutePath()));
    QFile file(m_path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write("{not json");
    file.close();
    NotesStore store(m_path);
    QCOMPARE(store.rowCount(), 0);
    // Notes without an id are skipped.
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(R"({"version":1,"notes":[{"text":"no id"},{"id":"a","text":"ok","x":7,"y":-3}]})");
    file.close();
    store.reload();
    QCOMPARE(store.rowCount(), 1);
    QCOMPARE(text(store, 0), u"ok"_s);
    QCOMPARE(store.data(store.index(0), NotesStore::PosXRole).toDouble(), 1.0);
    QCOMPARE(store.data(store.index(0), NotesStore::PosYRole).toDouble(), 0.0);
}

void NotesStoreTest::positionsAndTextAreLimited()
{
    NotesStore store(m_path);
    const QString id = store.add(QString(NotesStore::MaxTextLength + 50, u'a'));
    QCOMPARE(int(text(store, 0).size()), NotesStore::MaxTextLength);
    store.move(id, std::numeric_limits<double>::quiet_NaN(), 2.0);
    QCOMPARE(store.data(store.index(0), NotesStore::PosXRole).toDouble(), 0.0);
    QCOMPARE(store.data(store.index(0), NotesStore::PosYRole).toDouble(), 1.0);
    for (int i = 1; i < NotesStore::MaxNotes; ++i) {
        QVERIFY(!store.add(QString()).isEmpty());
    }
    QVERIFY(store.add(u"one too many"_s).isEmpty());
    QCOMPARE(store.rowCount(), NotesStore::MaxNotes);
}

void NotesStoreTest::roleNames()
{
    NotesStore store(m_path);
    const auto names = store.roleNames();
    QCOMPARE(names.value(NotesStore::NoteIdRole), QByteArray("noteId"));
    QCOMPARE(names.value(NotesStore::NoteTextRole), QByteArray("noteText"));
    QCOMPARE(names.value(NotesStore::PosXRole), QByteArray("posX"));
    QCOMPARE(names.value(NotesStore::PosYRole), QByteArray("posY"));
}

QTEST_GUILESS_MAIN(NotesStoreTest)

#include "tst_notesstore.moc"
