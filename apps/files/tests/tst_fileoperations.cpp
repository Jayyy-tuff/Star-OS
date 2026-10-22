// SPDX-License-Identifier: GPL-3.0-or-later
// FileOperations against the real KIO on temporary folders. $HOME and the XDG
// directories point into a temporary folder on the same filesystem as the
// test files, so the trash test uses a private "home trash" and nothing
// touches the user's files. KIO's out-of-process workers (kio_trash) inherit
// this environment.

#include "fileoperations.h"

#include <KApplicationTrader>
#include <KProtocolInfo>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <functional>
#include <memory>

namespace
{
bool writeFile(const QString &path, const QByteArray &content = QByteArray())
{
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(content) == content.size();
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

QStringList entries(const QString &path)
{
    return QDir(path).entryList(QDir::AllEntries | QDir::Hidden | QDir::NoDotAndDotDot, QDir::Name);
}
}

class FileOperationsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void init();
    void cleanup();
    void nameErrors();
    void createsFolders();
    void refusesBadNames();
    void renames();
    void refusesRenameOntoAnExistingName();
    void copiesFilesAndFolders();
    void movesFiles();
    void copyIntoTheSameFolderPicksAFreeName();
    void clipboardCopyAndPaste();
    void clipboardCutAndPaste();
    void deletesPermanently();
    void trashRestoreAndEmpty();
    void refusesToStartPrograms();
    void neverRunsDesktopEntries();
    void refusesToOpenItemsInTheTrash();

private:
    struct Outcome {
        bool finished = false;
        bool failed = false;
        QString message;
        QList<QUrl> urls;
    };

    // Runs `action` and waits until the operation reports back.
    Outcome run(const std::function<void()> &action);
    QString pathOf(const QString &name) const;
    QUrl urlOf(const QString &name) const;

    QTemporaryDir m_home;
    std::unique_ptr<QTemporaryDir> m_work;
    std::unique_ptr<FileOperations> m_operations;
};

void FileOperationsTest::initTestCase()
{
    QVERIFY(m_home.isValid());
    const QString home = m_home.path();
    qputenv("HOME", QFile::encodeName(home));
    qputenv("XDG_DATA_HOME", QFile::encodeName(home + QStringLiteral("/.local/share")));
    qputenv("XDG_CONFIG_HOME", QFile::encodeName(home + QStringLiteral("/.config")));
    qputenv("XDG_CACHE_HOME", QFile::encodeName(home + QStringLiteral("/.cache")));
}

void FileOperationsTest::init()
{
    m_work = std::make_unique<QTemporaryDir>(m_home.filePath(QStringLiteral("work-XXXXXX")));
    QVERIFY(m_work->isValid());
    m_operations = std::make_unique<FileOperations>();
}

void FileOperationsTest::cleanup()
{
    m_operations.reset();
    m_work.reset();
}

FileOperationsTest::Outcome FileOperationsTest::run(const std::function<void()> &action)
{
    QSignalSpy finished(m_operations.get(), &FileOperations::finished);
    QSignalSpy failed(m_operations.get(), &FileOperations::failed);
    action();
    QTest::qWaitFor(
        [&] {
            return finished.count() + failed.count() > 0;
        },
        30000);

    Outcome outcome;
    if (!finished.isEmpty()) {
        outcome.finished = true;
        outcome.urls = finished.first().at(1).value<QList<QUrl>>();
    }
    if (!failed.isEmpty()) {
        outcome.failed = true;
        outcome.message = failed.first().at(1).toString();
    }
    return outcome;
}

QString FileOperationsTest::pathOf(const QString &name) const
{
    return name.isEmpty() ? m_work->path() : m_work->filePath(name);
}

QUrl FileOperationsTest::urlOf(const QString &name) const
{
    return QUrl::fromLocalFile(pathOf(name));
}

void FileOperationsTest::nameErrors()
{
    QVERIFY(m_operations->nameError(QStringLiteral("Report 2026.odt")).isEmpty());
    QVERIFY(m_operations->nameError(QStringLiteral(".config")).isEmpty());
    for (const QString &bad : {QString(), QStringLiteral("   "), QStringLiteral("a/b"), QStringLiteral("."), QStringLiteral("..")}) {
        QVERIFY2(!m_operations->nameError(bad).isEmpty(), qPrintable(bad));
    }
}

void FileOperationsTest::createsFolders()
{
    QSignalSpy busyChanged(m_operations.get(), &FileOperations::busyChanged);
    QSignalSpy finished(m_operations.get(), &FileOperations::finished);
    m_operations->createFolder(urlOf(QString()), QStringLiteral(" Projects "));
    QVERIFY(m_operations->isBusy());
    QVERIFY(!m_operations->statusText().isEmpty());
    QVERIFY(finished.wait(30000));
    QVERIFY(!m_operations->isBusy());
    QCOMPARE(busyChanged.count(), 2);
    QCOMPARE(finished.first().at(0).toString(), QStringLiteral("newFolder"));
    QCOMPARE(finished.first().at(1).value<QList<QUrl>>(), QList<QUrl>({urlOf(QStringLiteral("Projects"))}));
    QVERIFY(QFileInfo(pathOf(QStringLiteral("Projects"))).isDir());

    const Outcome again = run([this] {
        m_operations->createFolder(urlOf(QString()), QStringLiteral("Projects"));
    });
    QVERIFY(again.failed);
    QVERIFY(!again.message.isEmpty());
}

void FileOperationsTest::refusesBadNames()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("file.txt"))));
    for (const QString &bad : {QString(), QStringLiteral("a/b"), QStringLiteral(".."), QStringLiteral(".")}) {
        QSignalSpy failed(m_operations.get(), &FileOperations::failed);
        m_operations->createFolder(urlOf(QString()), bad);
        m_operations->rename(urlOf(QStringLiteral("file.txt")), bad);
        // Refused at once, before any job starts.
        QCOMPARE(failed.count(), 2);
        QVERIFY(!m_operations->isBusy());
    }
    QCOMPARE(entries(pathOf(QString())), QStringList({"file.txt"}));
}

void FileOperationsTest::renames()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("old.txt")), "content"));
    QVERIFY(QDir(pathOf(QString())).mkdir(QStringLiteral("folder")));

    Outcome outcome = run([this] {
        m_operations->rename(urlOf(QStringLiteral("old.txt")), QStringLiteral("new.txt"));
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(outcome.urls, QList<QUrl>({urlOf(QStringLiteral("new.txt"))}));
    QCOMPARE(readFile(pathOf(QStringLiteral("new.txt"))), QByteArray("content"));

    outcome = run([this] {
        m_operations->rename(urlOf(QStringLiteral("folder")), QStringLiteral("Folder 2"));
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(entries(pathOf(QString())), QStringList({"Folder 2", "new.txt"}));
}

void FileOperationsTest::refusesRenameOntoAnExistingName()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("a.txt")), "a"));
    QVERIFY(writeFile(pathOf(QStringLiteral("b.txt")), "b"));
    const Outcome outcome = run([this] {
        m_operations->rename(urlOf(QStringLiteral("a.txt")), QStringLiteral("b.txt"));
    });
    QVERIFY(outcome.failed);
    QVERIFY(!outcome.message.isEmpty());
    QCOMPARE(readFile(pathOf(QStringLiteral("a.txt"))), QByteArray("a"));
    QCOMPARE(readFile(pathOf(QStringLiteral("b.txt"))), QByteArray("b"));
}

void FileOperationsTest::copiesFilesAndFolders()
{
    QDir work(pathOf(QString()));
    QVERIFY(writeFile(pathOf(QStringLiteral("f.txt")), "file"));
    QVERIFY(work.mkpath(QStringLiteral("d/sub")));
    QVERIFY(writeFile(pathOf(QStringLiteral("d/sub/inner.txt")), "inner"));
    QVERIFY(work.mkdir(QStringLiteral("dest")));

    const Outcome outcome = run([this] {
        m_operations->copy({urlOf(QStringLiteral("f.txt")), urlOf(QStringLiteral("d"))}, urlOf(QStringLiteral("dest")));
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(readFile(pathOf(QStringLiteral("dest/f.txt"))), QByteArray("file"));
    QCOMPARE(readFile(pathOf(QStringLiteral("dest/d/sub/inner.txt"))), QByteArray("inner"));
    QVERIFY(QFile::exists(pathOf(QStringLiteral("f.txt"))));
    QVERIFY(QFile::exists(pathOf(QStringLiteral("d/sub/inner.txt"))));
    // Only the top-level copies are reported.
    QCOMPARE(outcome.urls.size(), 2);
    QVERIFY(outcome.urls.contains(urlOf(QStringLiteral("dest/f.txt"))));
    QVERIFY(outcome.urls.contains(urlOf(QStringLiteral("dest/d"))));
}

void FileOperationsTest::movesFiles()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("m.txt")), "moved"));
    QVERIFY(QDir(pathOf(QString())).mkdir(QStringLiteral("dest")));
    const Outcome outcome = run([this] {
        m_operations->move({urlOf(QStringLiteral("m.txt"))}, urlOf(QStringLiteral("dest")));
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QVERIFY(!QFile::exists(pathOf(QStringLiteral("m.txt"))));
    QCOMPARE(readFile(pathOf(QStringLiteral("dest/m.txt"))), QByteArray("moved"));
}

void FileOperationsTest::copyIntoTheSameFolderPicksAFreeName()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("notes.txt")), "n"));
    const Outcome outcome = run([this] {
        m_operations->copy({urlOf(QStringLiteral("notes.txt"))}, urlOf(QString()));
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(entries(pathOf(QString())), QStringList({"notes (1).txt", "notes.txt"}));
    QCOMPARE(outcome.urls, QList<QUrl>({urlOf(QStringLiteral("notes (1).txt"))}));
}

void FileOperationsTest::clipboardCopyAndPaste()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("c.txt")), "clip"));
    QVERIFY(QDir(pathOf(QString())).mkdir(QStringLiteral("dest")));

    m_operations->copyToClipboard({urlOf(QStringLiteral("c.txt"))});
    QVERIFY(m_operations->canPaste());
    const Outcome outcome = run([this] {
        m_operations->paste(urlOf(QStringLiteral("dest")));
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(readFile(pathOf(QStringLiteral("dest/c.txt"))), QByteArray("clip"));
    QVERIFY(QFile::exists(pathOf(QStringLiteral("c.txt"))));
    // A copy can be pasted again.
    QVERIFY(m_operations->canPaste());
}

void FileOperationsTest::clipboardCutAndPaste()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("x.txt")), "cut"));
    QVERIFY(QDir(pathOf(QString())).mkdir(QStringLiteral("dest")));

    m_operations->cutToClipboard({urlOf(QStringLiteral("x.txt"))});
    QVERIFY(m_operations->canPaste());

    // Pasting into the folder it came from does nothing.
    Outcome outcome = run([this] {
        m_operations->paste(urlOf(QString()));
    });
    QVERIFY(outcome.finished);
    QVERIFY(QFile::exists(pathOf(QStringLiteral("x.txt"))));

    outcome = run([this] {
        m_operations->paste(urlOf(QStringLiteral("dest")));
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QVERIFY(!QFile::exists(pathOf(QStringLiteral("x.txt"))));
    QCOMPARE(readFile(pathOf(QStringLiteral("dest/x.txt"))), QByteArray("cut"));
    // What was cut is pasted once.
    QVERIFY(!m_operations->canPaste());
}

void FileOperationsTest::deletesPermanently()
{
    QVERIFY(writeFile(pathOf(QStringLiteral("gone.txt"))));
    QVERIFY(QDir(pathOf(QString())).mkpath(QStringLiteral("gone/deep")));
    QVERIFY(writeFile(pathOf(QStringLiteral("gone/deep/file"))));
    QVERIFY(writeFile(pathOf(QStringLiteral("kept.txt"))));

    const Outcome outcome = run([this] {
        m_operations->deletePermanently({urlOf(QStringLiteral("gone.txt")), urlOf(QStringLiteral("gone"))});
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(entries(pathOf(QString())), QStringList({"kept.txt"}));
}

void FileOperationsTest::trashRestoreAndEmpty()
{
    if (!KProtocolInfo::isKnownProtocol(QStringLiteral("trash"))) {
        QSKIP("The KIO trash worker (kio_trash) is not installed.");
    }
    const QString trashFiles = m_home.filePath(QStringLiteral(".local/share/Trash/files"));
    QVERIFY(writeFile(pathOf(QStringLiteral("doomed.txt")), "keep me"));

    Outcome outcome = run([this] {
        m_operations->moveToTrash({urlOf(QStringLiteral("doomed.txt"))});
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QVERIFY(!QFile::exists(pathOf(QStringLiteral("doomed.txt"))));
    QCOMPARE(entries(trashFiles), QStringList({"doomed.txt"}));
    QCOMPARE(outcome.urls.size(), 1);
    QCOMPARE(outcome.urls.first().scheme(), QStringLiteral("trash"));

    outcome = run([this, trashUrls = outcome.urls] {
        m_operations->restoreFromTrash(trashUrls);
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(readFile(pathOf(QStringLiteral("doomed.txt"))), QByteArray("keep me"));
    QCOMPARE(entries(trashFiles), QStringList());

    outcome = run([this] {
        m_operations->moveToTrash({urlOf(QStringLiteral("doomed.txt"))});
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(entries(trashFiles).size(), 1);

    outcome = run([this] {
        m_operations->emptyTrash();
    });
    QVERIFY2(outcome.finished, qPrintable(outcome.message));
    QCOMPARE(entries(trashFiles), QStringList());
    QVERIFY(!QFile::exists(pathOf(QStringLiteral("doomed.txt"))));
}

void FileOperationsTest::refusesToStartPrograms()
{
    const QString program = pathOf(QStringLiteral("program"));
    QVERIFY(QFile::copy(QCoreApplication::applicationFilePath(), program));
    QVERIFY(QFile::setPermissions(program, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));

    QSignalSpy failed(m_operations.get(), &FileOperations::failed);
    m_operations->open(urlOf(QStringLiteral("program")));
    // Refused before any job starts, so nothing is launched.
    QCOMPARE(failed.count(), 1);
    QVERIFY(!m_operations->isBusy());
    const QString message = failed.first().at(1).toString();
    QVERIFY2(message.contains(QStringLiteral("program")), qPrintable(message));

    const QMimeType mime = QMimeDatabase().mimeTypeForFile(program);
    if (mime.inherits(QStringLiteral("application/x-executable")) || mime.inherits(QStringLiteral("application/x-sharedlib"))
        || mime.inherits(QStringLiteral("application/x-pie-executable"))) {
        QVERIFY2(message.contains(QStringLiteral("is a program")), qPrintable(message));
    } else {
        qInfo() << "The MIME database types the test binary as" << mime.name() << "- checked only that it is refused";
    }
}

void FileOperationsTest::neverRunsDesktopEntries()
{
    if (KApplicationTrader::preferredService(QStringLiteral("text/plain"))) {
        QSKIP("A text editor is installed; opening the entry as text would start it.");
    }
    const QString marker = pathOf(QStringLiteral("ran"));
    const QString entry = pathOf(QStringLiteral("launcher.desktop"));
    QVERIFY(writeFile(entry,
                      QByteArrayLiteral("[Desktop Entry]\nType=Application\nName=Launcher\nExec=touch ") + QFile::encodeName(marker)
                          + QByteArrayLiteral("\n")));
    QVERIFY(QFile::setPermissions(entry, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));

    QSignalSpy failed(m_operations.get(), &FileOperations::failed);
    m_operations->open(QUrl::fromLocalFile(entry));
    // Desktop entries are only ever opened as text; with no text editor that
    // is refused.
    QCOMPARE(failed.count(), 1);
    QTest::qWait(500);
    QVERIFY(!QFile::exists(marker));
}

void FileOperationsTest::refusesToOpenItemsInTheTrash()
{
    QSignalSpy failed(m_operations.get(), &FileOperations::failed);
    m_operations->open(QUrl(QStringLiteral("trash:/0-file.txt")));
    QCOMPARE(failed.count(), 1);
    QVERIFY(!m_operations->isBusy());
}

QTEST_MAIN(FileOperationsTest)

#include "tst_fileoperations.moc"
