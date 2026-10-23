// SPDX-License-Identifier: GPL-3.0-or-later
// SystemStatus on fixture files and a fake storage probe: the three storage
// modes, memory from /proc/meminfo and batteries from power_supply.

#include "systemstatus.h"

#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using namespace Qt::StringLiterals;

class SystemStatusTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void liveSessionInMemory();
    void starStorageDisk();
    void diskWithoutCowDeviceIsLive();
    void installedSystem();
    void memory();
    void batteries();
    void noBattery();
    void interval();

private:
    void write(const QString &relative, const QByteArray &content);
    std::unique_ptr<SystemStatus> make();

    std::unique_ptr<QTemporaryDir> m_dir;
    SystemStatus::Paths m_paths;
    QHash<QString, SystemStatus::Volume> m_volumes;
};

void SystemStatusTest::init()
{
    m_dir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_dir->isValid());
    QDir dir(m_dir->path());
    QVERIFY(dir.mkpath(u"cowspace"_s));
    QVERIFY(dir.mkpath(u"power_supply"_s));
    m_paths.cowspace = dir.filePath(u"cowspace"_s);
    m_paths.cmdline = dir.filePath(u"cmdline"_s);
    m_paths.meminfo = dir.filePath(u"meminfo"_s);
    m_paths.powerSupply = dir.filePath(u"power_supply"_s);
    m_paths.root = u"/"_s;
    m_volumes.clear();
    write(u"cmdline"_s, "initrd=\\arch\\boot\\x86_64\\initramfs-linux.img archisobasedir=arch cow_spacesize=50%\n");
    write(u"meminfo"_s, "MemTotal:        4028812 kB\nMemFree:          100000 kB\nMemAvailable:    3014656 kB\n");
}

void SystemStatusTest::write(const QString &relative, const QByteArray &content)
{
    const QString path = QDir(m_dir->path()).filePath(relative);
    QVERIFY(QDir().mkpath(QFileInfo(path).absolutePath()));
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    QVERIFY(file.write(content) == content.size());
}

std::unique_ptr<SystemStatus> SystemStatusTest::make()
{
    auto volumes = m_volumes;
    return std::make_unique<SystemStatus>(m_paths, [volumes](const QString &path) {
        return volumes.value(QDir::cleanPath(path));
    });
}

void SystemStatusTest::liveSessionInMemory()
{
    m_volumes.insert(m_paths.cowspace, {true, m_paths.cowspace, u"tmpfs"_s, u"cowspace"_s, 2000000000, 1500000000});
    auto status = make();
    QCOMPARE(status->storageMode(), u"live"_s);
    QCOMPARE(status->storageTotal(), 2000000000);
    QCOMPARE(status->storageFree(), 1500000000);
    QCOMPARE(status->storageDevice(), u"cowspace"_s);
}

void SystemStatusTest::starStorageDisk()
{
    write(u"cmdline"_s, "archisobasedir=arch cow_label=STAROS_DATA cow_directory=persistent_x/x86_64 cow_spacesize=50%\n");
    m_volumes.insert(m_paths.cowspace, {true, m_paths.cowspace, u"ext4"_s, u"/dev/vdb1"_s, 16000000000, 9800000000});
    auto status = make();
    QCOMPARE(status->storageMode(), u"star-storage"_s);
    QCOMPARE(status->storageFree(), 9800000000);
    QCOMPARE(status->storageDevice(), u"/dev/vdb1"_s);
}

void SystemStatusTest::diskWithoutCowDeviceIsLive()
{
    // A disk file system without cow_label on the command line is not Star
    // Storage (for example copytoram on a disk-backed cowspace).
    m_volumes.insert(m_paths.cowspace, {true, m_paths.cowspace, u"ext4"_s, u"/dev/sdb1"_s, 100, 50});
    QCOMPARE(make()->storageMode(), u"live"_s);
}

void SystemStatusTest::installedSystem()
{
    // The cowspace folder exists but nothing is mounted there.
    m_volumes.insert(m_paths.cowspace, {true, u"/"_s, u"btrfs"_s, u"/dev/nvme0n1p2"_s, 500, 400});
    m_volumes.insert(u"/"_s, {true, u"/"_s, u"btrfs"_s, u"/dev/nvme0n1p2"_s, 500000000000, 400000000000});
    auto status = make();
    QCOMPARE(status->storageMode(), u"installed"_s);
    QCOMPARE(status->storageTotal(), 500000000000);
    QCOMPARE(status->storageFree(), 400000000000);
    // No cowspace folder at all.
    QVERIFY(QDir(m_paths.cowspace).removeRecursively());
    QCOMPARE(make()->storageMode(), u"installed"_s);
}

void SystemStatusTest::memory()
{
    auto status = make();
    QCOMPARE(status->memoryTotal(), qint64(4028812) * 1024);
    QCOMPARE(status->memoryAvailable(), qint64(3014656) * 1024);
    write(u"meminfo"_s, "garbage\nMemTotal: x kB\n");
    status->refresh();
    QCOMPARE(status->memoryTotal(), 0);
}

void SystemStatusTest::batteries()
{
    write(u"power_supply/AC/type"_s, "Mains\n");
    write(u"power_supply/AC/online"_s, "1\n");
    write(u"power_supply/BAT0/type"_s, "Battery\n");
    write(u"power_supply/BAT0/capacity"_s, "80\n");
    write(u"power_supply/BAT0/status"_s, "Charging\n");
    write(u"power_supply/BAT1/type"_s, "Battery\n");
    write(u"power_supply/BAT1/capacity"_s, "60\n");
    write(u"power_supply/BAT1/status"_s, "Discharging\n");
    auto status = make();
    QVERIFY(status->batteryPresent());
    QCOMPARE(status->batteryPercent(), 70);
    QVERIFY(status->charging());
}

void SystemStatusTest::noBattery()
{
    write(u"power_supply/AC/type"_s, "Mains\n");
    auto status = make();
    QVERIFY(!status->batteryPresent());
    QCOMPARE(status->batteryPercent(), 0);
    QVERIFY(!status->charging());
}

void SystemStatusTest::interval()
{
    auto status = make();
    QCOMPARE(status->interval(), 5000);
    status->setInterval(0);
    QCOMPARE(status->interval(), 0);
    status->setInterval(1000);
    QCOMPARE(status->interval(), 1000);
}

QTEST_GUILESS_MAIN(SystemStatusTest)

#include "tst_systemstatus.moc"
