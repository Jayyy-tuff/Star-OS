// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QTimer>

#include <functional>

// Storage, memory, processor and battery for the taskbar meter, the desktop's
// System widget, Files and Star Storage.
//
// storageMode:
//   "star-storage"  the live medium keeps changes on a Star Storage disk:
//                   /run/archiso/cowspace is a disk file system and the
//                   kernel command line names a copy-on-write device
//   "live"          changes are kept in memory (cowspace is tmpfs)
//   "installed"     no live medium; the root file system is reported
class SystemStatus : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString storageMode READ storageMode NOTIFY changed)
    Q_PROPERTY(qint64 storageTotal READ storageTotal NOTIFY changed)
    Q_PROPERTY(qint64 storageFree READ storageFree NOTIFY changed)
    Q_PROPERTY(QString storageDevice READ storageDevice NOTIFY changed)
    Q_PROPERTY(qint64 memoryTotal READ memoryTotal NOTIFY changed)
    Q_PROPERTY(qint64 memoryAvailable READ memoryAvailable NOTIFY changed)
    // Percent of processor time in use since the last refresh; -1 until two
    // readings of /proc/stat exist.
    Q_PROPERTY(int cpuUsage READ cpuUsage NOTIFY changed)
    Q_PROPERTY(bool batteryPresent READ batteryPresent NOTIFY changed)
    Q_PROPERTY(int batteryPercent READ batteryPercent NOTIFY changed)
    Q_PROPERTY(bool charging READ charging NOTIFY changed)
    // Milliseconds between refreshes; 0 stops refreshing.
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)

public:
    // What a mounted file system reports for a path.
    struct Volume {
        bool valid = false;
        QString rootPath;
        QString fileSystemType;
        QString device;
        qint64 total = 0;
        qint64 free = 0;
    };
    using Probe = std::function<Volume(const QString &path)>;

    struct Paths {
        QString cowspace = QStringLiteral("/run/archiso/cowspace");
        QString cmdline = QStringLiteral("/proc/cmdline");
        QString meminfo = QStringLiteral("/proc/meminfo");
        QString stat = QStringLiteral("/proc/stat");
        QString powerSupply = QStringLiteral("/sys/class/power_supply");
        QString root = QStringLiteral("/");
    };

    explicit SystemStatus(QObject *parent = nullptr);
    // For tests: other files, and a probe instead of QStorageInfo.
    SystemStatus(const Paths &paths, Probe probe, QObject *parent = nullptr);

    QString storageMode() const;
    qint64 storageTotal() const;
    qint64 storageFree() const;
    QString storageDevice() const;
    qint64 memoryTotal() const;
    qint64 memoryAvailable() const;
    int cpuUsage() const;
    bool batteryPresent() const;
    int batteryPercent() const;
    bool charging() const;
    int interval() const;
    void setInterval(int interval);

    static Volume probeStorage(const QString &path);

    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void changed();
    void intervalChanged();

private:
    void readStorage();
    void readMemory();
    void readCpu();
    void readBattery();

    Paths m_paths;
    Probe m_probe;
    QTimer m_timer;
    QString m_storageMode;
    qint64 m_storageTotal = 0;
    qint64 m_storageFree = 0;
    QString m_storageDevice;
    qint64 m_memoryTotal = 0;
    qint64 m_memoryAvailable = 0;
    int m_cpuUsage = -1;
    quint64 m_cpuIdle = 0;
    quint64 m_cpuTotal = 0;
    bool m_batteryPresent = false;
    int m_batteryPercent = 0;
    bool m_charging = false;
};
