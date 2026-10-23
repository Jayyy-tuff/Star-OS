// SPDX-License-Identifier: GPL-3.0-or-later
// StorageBackend with shell scripts in place of the helper and pkexec: the
// disk list, erasing with its steps, refusals and errors, boot choices and
// restarting. The fake pkexec records its arguments and runs them.
#include "storagebackend.h"

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using namespace Qt::StringLiterals;

namespace
{
const QByteArray listJson = R"({"disks": [
 {"name": "vdb", "path": "/dev/vdb", "model": "", "size": 10737418240, "transport": "virtio",
  "removable": false, "usable": true, "reason": "", "reasonText": "", "starStorage": false, "partitions": []},
 {"name": "sr0x", "path": "/dev/sda", "model": "SanDisk Ultra", "size": 32000000000, "transport": "usb",
  "removable": true, "usable": false, "reason": "medium", "reasonText": "This is the Star OS medium.",
  "starStorage": false, "partitions": []},
 {"name": "vdc", "path": "/dev/vdc", "model": "", "size": 21474836480, "transport": "virtio",
  "removable": false, "usable": true, "reason": "", "reasonText": "", "starStorage": true,
  "partitions": [{"name": "vdc1", "path": "/dev/vdc1", "size": 21473787904, "fstype": "ext4", "label": "STAROS_DATA"}]}
], "existing": ["vdc"], "uefi": true, "systemdBoot": %SYSTEMDBOOT%, "always": %ALWAYS%})";
}

class BackendTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void listsDisks();
    void bootChoiceNeedsUefiAndItsOwnMenu_data();
    void bootChoiceNeedsUefiAndItsOwnMenu();
    void listErrorIsShown();
    void missingHelperIsAnError();
    void refreshClearsAnError();
    void formatShowsStepsThenDone();
    void formatErrorFromTheHelper();
    void permissionNotGiven();
    void formatOnlyWhenReady();
    void bootChoices();
    void bootErrorIsAMessage();
    void restartIntoStarStorage();

private:
    QString writeScript(const QString &name, const QByteArray &body);
    QString helper(const QByteArray &systemdBoot = "true", const QByteArray &always = "false",
                   const QByteArray &list = {}, const QByteArray &format = {}, const QByteArray &boot = {});
    QStringList pkexecCalls() const;
    void ready(StorageBackend &backend);

    std::unique_ptr<QTemporaryDir> m_dir;
    QString m_pkexec;
};

void BackendTest::init()
{
    m_dir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_dir->isValid());
    m_pkexec = writeScript(u"pkexec"_s, "printf '%s\\n' \"$*\" >> '" + m_dir->filePath(u"pkexec-calls"_s).toUtf8() + "'\nexec \"$@\"\n");
}

QString BackendTest::writeScript(const QString &name, const QByteArray &body)
{
    const QString path = m_dir->filePath(name);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return {};
    }
    file.write("#!/bin/sh\n" + body);
    file.close();
    file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    return path;
}

// A helper script: `list`, `format` and `boot` print what is given, or what
// the real helper prints when all goes well.
QString BackendTest::helper(const QByteArray &systemdBoot, const QByteArray &always, const QByteArray &list,
                            const QByteArray &format, const QByteArray &boot)
{
    QByteArray listing = listJson;
    // One line, as the real helper prints it.
    listing.replace("%SYSTEMDBOOT%", systemdBoot).replace("%ALWAYS%", always).replace('\n', ' ');
    const QByteArray listBody = list.isEmpty() ? "cat <<'JSON'\n" + listing + "\nJSON\n" : list;
    const QByteArray formatBody = format.isEmpty()
        ? "echo '{\"step\": \"wipe\", \"message\": \"Erasing '\"$2\"'\"}'\n"
          "echo '{\"step\": \"format\", \"message\": \"Formatting /dev/'\"$2\"'1\"}'\n"
          "echo '{\"done\": true, \"disk\": \"'\"$2\"'\", \"partition\": \"/dev/'\"$2\"'1\", \"label\": \"STAROS_DATA\"}'\n"
        : format;
    const QByteArray bootBody = boot.isEmpty() ? "echo '{\"done\": true, \"boot\": \"'\"$2\"'\"}'\n" : boot;
    return writeScript(u"helper"_s,
                       "case \"$1\" in\nlist)\n" + listBody + ";;\nformat)\n" + formatBody + ";;\nboot)\n" + bootBody + ";;\nesac\n");
}

QStringList BackendTest::pkexecCalls() const
{
    QFile file(m_dir->filePath(u"pkexec-calls"_s));
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    QStringList calls = QString::fromUtf8(file.readAll()).split(u'\n', Qt::SkipEmptyParts);
    for (QString &call : calls) {
        call.replace(m_dir->path() + u'/', QString());
    }
    return calls;
}

void BackendTest::ready(StorageBackend &backend)
{
    backend.setPkexec(m_pkexec);
    backend.refresh();
    QTRY_VERIFY2_WITH_TIMEOUT(backend.state() == u"ready"_s,
                              qPrintable(backend.state() + u": "_s + backend.errorString()), 20000);
}

void BackendTest::listsDisks()
{
    StorageBackend backend;
    backend.setHelper(helper());
    QCOMPARE(backend.state(), u"loading"_s);
    QSignalSpy disks(&backend, &StorageBackend::disksChanged);
    ready(backend);
    QCOMPARE(disks.count(), 1);
    QCOMPARE(backend.disks().size(), 3);
    const QVariantMap first = backend.disks().constFirst().toMap();
    QCOMPARE(first.value(u"name"_s).toString(), u"vdb"_s);
    QCOMPARE(first.value(u"size"_s).toLongLong(), 10737418240LL);
    QCOMPARE(first.value(u"usable"_s).toBool(), true);
    QCOMPARE(backend.disks().at(1).toMap().value(u"reasonText"_s).toString(), u"This is the Star OS medium."_s);
    QCOMPARE(backend.disks().at(2).toMap().value(u"partitions"_s).toList().size(), 1);
    QCOMPARE(backend.existing(), QStringList{u"vdc"_s});
    QVERIFY(backend.uefi());
    QVERIFY(!backend.alwaysStarStorage());
    QVERIFY(pkexecCalls().isEmpty());
}

void BackendTest::bootChoiceNeedsUefiAndItsOwnMenu_data()
{
    QTest::addColumn<QByteArray>("systemdBoot");
    QTest::addColumn<QByteArray>("always");
    QTest::addColumn<bool>("canChoose");
    QTest::addColumn<bool>("isAlways");
    QTest::newRow("systemd-boot") << QByteArray("true") << QByteArray("true") << true << true;
    QTest::newRow("unknown loader") << QByteArray("null") << QByteArray("false") << true << false;
    QTest::newRow("another loader") << QByteArray("false") << QByteArray("false") << false << false;
}

void BackendTest::bootChoiceNeedsUefiAndItsOwnMenu()
{
    QFETCH(QByteArray, systemdBoot);
    QFETCH(QByteArray, always);
    QFETCH(bool, canChoose);
    QFETCH(bool, isAlways);
    StorageBackend backend;
    backend.setHelper(helper(systemdBoot, always));
    ready(backend);
    QCOMPARE(backend.canChooseBoot(), canChoose);
    QCOMPARE(backend.alwaysStarStorage(), isAlways);

    StorageBackend bios;
    bios.setHelper(helper("false", "false", "echo '{\"disks\": [], \"existing\": [], \"uefi\": false, \"systemdBoot\": false, \"always\": false}'\n"));
    ready(bios);
    QVERIFY(!bios.uefi());
    QVERIFY(!bios.canChooseBoot());
}

void BackendTest::listErrorIsShown()
{
    StorageBackend backend;
    backend.setHelper(helper("true", "false", "echo '{\"error\": \"lsblk failed: no devices\"}'\nexit 1\n"));
    backend.refresh();
    QTRY_COMPARE_WITH_TIMEOUT(backend.state(), u"error"_s, 20000);
    QCOMPARE(backend.errorString(), u"Star Storage could not list the disks: lsblk failed: no devices"_s);
}

void BackendTest::missingHelperIsAnError()
{
    StorageBackend backend;
    backend.setHelper(m_dir->filePath(u"missing-helper"_s));
    backend.refresh();
    QTRY_COMPARE_WITH_TIMEOUT(backend.state(), u"error"_s, 20000);
    QVERIFY2(backend.errorString().startsWith(u"Star Storage could not list the disks: "_s), qPrintable(backend.errorString()));
}

void BackendTest::refreshClearsAnError()
{
    StorageBackend backend;
    backend.setHelper(m_dir->filePath(u"missing-helper"_s));
    backend.refresh();
    QTRY_COMPARE_WITH_TIMEOUT(backend.state(), u"error"_s, 20000);
    backend.setHelper(helper());
    ready(backend);
    QVERIFY(backend.errorString().isEmpty());
}

void BackendTest::formatShowsStepsThenDone()
{
    StorageBackend backend;
    backend.setHelper(helper());
    ready(backend);
    QSignalSpy steps(&backend, &StorageBackend::stepChanged);
    backend.format(u"vdb"_s, u"vdb"_s);
    QCOMPARE(backend.state(), u"working"_s);
    QCOMPARE(backend.step(), u"Asking for permission…"_s);
    QTRY_COMPARE_WITH_TIMEOUT(backend.state(), u"done"_s, 20000);
    QCOMPARE(backend.partition(), u"/dev/vdb1"_s);
    QCOMPARE(backend.step(), u"Formatting /dev/vdb1"_s);
    QVERIFY(steps.count() >= 3);
    QCOMPARE(pkexecCalls(), QStringList{u"helper format vdb vdb"_s});
    // The list is read again and the state stays "done".
    QTest::qWait(200);
    QCOMPARE(backend.state(), u"done"_s);
}

void BackendTest::formatErrorFromTheHelper()
{
    StorageBackend backend;
    backend.setHelper(helper("true", "false", {},
                             "echo '{\"error\": \"vdb cannot be used. It is in use: one of its partitions is mounted.\"}'\nexit 1\n"));
    ready(backend);
    backend.format(u"vdb"_s, u"vdb"_s);
    QTRY_COMPARE_WITH_TIMEOUT(backend.state(), u"error"_s, 20000);
    QCOMPARE(backend.errorString(),
             u"Star Storage was not set up. vdb cannot be used. It is in use: one of its partitions is mounted."_s);
    QVERIFY(backend.partition().isEmpty());
}

void BackendTest::permissionNotGiven()
{
    StorageBackend backend;
    backend.setHelper(helper());
    ready(backend);
    backend.setPkexec(writeScript(u"pkexec-refuses"_s, "exit 126\n"));
    backend.format(u"vdb"_s, u"vdb"_s);
    QTRY_COMPARE_WITH_TIMEOUT(backend.state(), u"error"_s, 20000);
    QCOMPARE(backend.errorString(), u"Star Storage was not set up. Permission was not given."_s);
}

void BackendTest::formatOnlyWhenReady()
{
    StorageBackend backend;
    backend.setHelper(helper());
    backend.setPkexec(m_pkexec);
    // Still loading: nothing happens.
    backend.format(u"vdb"_s, u"vdb"_s);
    QCOMPARE(backend.state(), u"loading"_s);
    QTest::qWait(200);
    QVERIFY(pkexecCalls().isEmpty());
}

void BackendTest::bootChoices()
{
    StorageBackend backend;
    backend.setHelper(helper());
    ready(backend);
    QSignalSpy busy(&backend, &StorageBackend::busyChanged);
    backend.setBoot(u"always"_s);
    QVERIFY(backend.busy());
    QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(), 20000);
    QCOMPARE(busy.count(), 2);
    QCOMPARE(backend.message(), u"Star OS now starts with Star Storage every time."_s);
    backend.setBoot(u"never"_s);
    QTRY_COMPARE_WITH_TIMEOUT(backend.message(), u"Star OS no longer starts with Star Storage by default."_s, 20000);
    backend.setBoot(u"next"_s);
    QTRY_COMPARE_WITH_TIMEOUT(backend.message(), u"Star OS starts with Star Storage next time."_s, 20000);
    QCOMPARE(pkexecCalls(), (QStringList{u"helper boot always"_s, u"helper boot never"_s, u"helper boot next"_s}));
    QCOMPARE(backend.state(), u"ready"_s);
}

void BackendTest::bootErrorIsAMessage()
{
    StorageBackend backend;
    backend.setHelper(helper("true", "false", {}, {},
                             "echo '{\"error\": \"This computer started Star OS without UEFI.\"}'\nexit 1\n"));
    ready(backend);
    bool restarted = false;
    backend.setRestarter([&restarted] {
        restarted = true;
    });
    backend.restartIntoStarStorage();
    QTRY_VERIFY_WITH_TIMEOUT(!backend.busy(), 20000);
    QCOMPARE(backend.message(), u"The start was not changed. This computer started Star OS without UEFI."_s);
    QVERIFY(!restarted);
    QCOMPARE(backend.state(), u"ready"_s);
}

void BackendTest::restartIntoStarStorage()
{
    StorageBackend backend;
    backend.setHelper(helper());
    ready(backend);
    bool restarted = false;
    backend.setRestarter([&restarted] {
        restarted = true;
    });
    backend.restartIntoStarStorage();
    QTRY_VERIFY_WITH_TIMEOUT(restarted, 20000);
    QCOMPARE(backend.message(), u"Restarting into Star Storage…"_s);
    QCOMPARE(pkexecCalls(), QStringList{u"helper boot next"_s});
}

QTEST_GUILESS_MAIN(BackendTest)

#include "tst_backend.moc"
