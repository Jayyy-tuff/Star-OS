// SPDX-License-Identifier: GPL-3.0-or-later
#include "systemstatus.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStorageInfo>

#include <algorithm>

namespace
{
QString readText(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.read(64 * 1024));
}
}

SystemStatus::SystemStatus(QObject *parent)
    : SystemStatus(Paths(), &SystemStatus::probeStorage, parent)
{
}

SystemStatus::SystemStatus(const Paths &paths, Probe probe, QObject *parent)
    : QObject(parent)
    , m_paths(paths)
    , m_probe(std::move(probe))
{
    m_timer.setInterval(5000);
    connect(&m_timer, &QTimer::timeout, this, &SystemStatus::refresh);
    m_timer.start();
    refresh();
}

SystemStatus::Volume SystemStatus::probeStorage(const QString &path)
{
    Volume volume;
    QStorageInfo info(path);
    if (!info.isValid()) {
        return volume;
    }
    volume.valid = true;
    volume.rootPath = info.rootPath();
    volume.fileSystemType = QString::fromUtf8(info.fileSystemType());
    volume.device = QString::fromUtf8(info.device());
    volume.total = info.bytesTotal();
    volume.free = info.bytesAvailable();
    return volume;
}

QString SystemStatus::storageMode() const
{
    return m_storageMode;
}

qint64 SystemStatus::storageTotal() const
{
    return m_storageTotal;
}

qint64 SystemStatus::storageFree() const
{
    return m_storageFree;
}

QString SystemStatus::storageDevice() const
{
    return m_storageDevice;
}

qint64 SystemStatus::memoryTotal() const
{
    return m_memoryTotal;
}

qint64 SystemStatus::memoryAvailable() const
{
    return m_memoryAvailable;
}

int SystemStatus::cpuUsage() const
{
    return m_cpuUsage;
}

bool SystemStatus::batteryPresent() const
{
    return m_batteryPresent;
}

int SystemStatus::batteryPercent() const
{
    return m_batteryPercent;
}

bool SystemStatus::charging() const
{
    return m_charging;
}

int SystemStatus::interval() const
{
    return m_timer.isActive() ? m_timer.interval() : 0;
}

void SystemStatus::setInterval(int interval)
{
    if (interval == this->interval()) {
        return;
    }
    if (interval > 0) {
        m_timer.start(interval);
    } else {
        m_timer.stop();
    }
    Q_EMIT intervalChanged();
}

void SystemStatus::refresh()
{
    readStorage();
    readMemory();
    readCpu();
    readBattery();
    Q_EMIT changed();
}

void SystemStatus::readStorage()
{
    const Volume cowspace = QFileInfo(m_paths.cowspace).isDir() ? m_probe(m_paths.cowspace) : Volume();
    // Only a file system mounted at the cowspace path counts, not the one
    // that merely contains the directory.
    const bool mounted = cowspace.valid
        && QDir::cleanPath(cowspace.rootPath) == QDir::cleanPath(m_paths.cowspace);
    Volume volume;
    if (mounted) {
        const QStringList cmdline = readText(m_paths.cmdline).split(QLatin1Char(' '), Qt::SkipEmptyParts);
        const bool cowDevice = std::any_of(cmdline.cbegin(), cmdline.cend(), [](const QString &arg) {
            return arg.startsWith(QLatin1String("cow_label=")) || arg.startsWith(QLatin1String("cow_device="));
        });
        if (cowspace.fileSystemType == QLatin1String("tmpfs")) {
            m_storageMode = QStringLiteral("live");
        } else if (cowDevice) {
            m_storageMode = QStringLiteral("star-storage");
        } else {
            m_storageMode = QStringLiteral("live");
        }
        volume = cowspace;
    } else {
        m_storageMode = QStringLiteral("installed");
        volume = m_probe(m_paths.root);
    }
    m_storageTotal = volume.valid ? volume.total : 0;
    m_storageFree = volume.valid ? volume.free : 0;
    m_storageDevice = volume.valid ? volume.device : QString();
}

void SystemStatus::readMemory()
{
    m_memoryTotal = 0;
    m_memoryAvailable = 0;
    const QStringList lines = readText(m_paths.meminfo).split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        const QStringList parts = line.simplified().split(QLatin1Char(' '));
        if (parts.size() < 2) {
            continue;
        }
        bool ok = false;
        const qint64 kib = parts.at(1).toLongLong(&ok);
        if (!ok) {
            continue;
        }
        if (parts.at(0) == QLatin1String("MemTotal:")) {
            m_memoryTotal = kib * 1024;
        } else if (parts.at(0) == QLatin1String("MemAvailable:")) {
            m_memoryAvailable = kib * 1024;
        }
    }
}

// The first line of /proc/stat: "cpu user nice system idle iowait irq
// softirq steal ..." in clock ticks since boot; idle and iowait are idle.
void SystemStatus::readCpu()
{
    const QString text = readText(m_paths.stat);
    const QStringList fields = text.left(text.indexOf(QLatin1Char('\n'))).simplified().split(QLatin1Char(' '));
    if (fields.size() < 5 || fields.at(0) != QLatin1String("cpu")) {
        m_cpuUsage = -1;
        return;
    }
    quint64 total = 0;
    quint64 idle = 0;
    for (qsizetype i = 1; i < std::min<qsizetype>(fields.size(), 9); ++i) {
        const quint64 ticks = fields.at(i).toULongLong();
        total += ticks;
        if (i == 4 || i == 5) {
            idle += ticks;
        }
    }
    if (m_cpuTotal > 0 && total > m_cpuTotal && idle >= m_cpuIdle) {
        const double busy = 1.0 - double(idle - m_cpuIdle) / double(total - m_cpuTotal);
        m_cpuUsage = qBound(0, int(busy * 100.0 + 0.5), 100);
    }
    m_cpuIdle = idle;
    m_cpuTotal = total;
}

void SystemStatus::readBattery()
{
    int count = 0;
    int sum = 0;
    bool charging = false;
    const QDir dir(m_paths.powerSupply);
    const QStringList supplies = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System, QDir::Name);
    for (const QString &name : supplies) {
        const QString path = dir.filePath(name);
        if (readText(path + QStringLiteral("/type")).trimmed() != QLatin1String("Battery")) {
            continue;
        }
        bool ok = false;
        const int capacity = readText(path + QStringLiteral("/capacity")).trimmed().toInt(&ok);
        if (!ok) {
            continue;
        }
        sum += qBound(0, capacity, 100);
        count += 1;
        charging = charging || readText(path + QStringLiteral("/status")).trimmed() == QLatin1String("Charging");
    }
    m_batteryPresent = count > 0;
    m_batteryPercent = count > 0 ? sum / count : 0;
    m_charging = m_batteryPresent && charging;
}
