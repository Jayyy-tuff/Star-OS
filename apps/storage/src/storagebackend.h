// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QVariantList>

#include <functional>

// Star Storage's backend: runs staros-storage-helper, which lists the disks as
// the person and erases one or sets the next start as root through pkexec.
// The helper decides what is allowed; this class only shows what it says.
//
// state: "loading", "ready", "working" (erasing), "done" or "error".
class StorageBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY stateChanged)
    // While erasing: what the helper is doing ("Making a partition on sdb").
    Q_PROPERTY(QString step READ step NOTIFY stepChanged)
    // After erasing: the new partition, e.g. "/dev/sdb1".
    Q_PROPERTY(QString partition READ partition NOTIFY stateChanged)
    // The helper's disks: name, path, model, size, transport, removable,
    // usable, reason, reasonText, starStorage and partitions.
    Q_PROPERTY(QVariantList disks READ disks NOTIFY disksChanged)
    // Disks that already have Star Storage.
    Q_PROPERTY(QStringList existing READ existing NOTIFY disksChanged)
    Q_PROPERTY(bool uefi READ uefi NOTIFY disksChanged)
    // UEFI and started from Star OS's own boot menu (or not known otherwise):
    // Star Storage can choose the next start.
    Q_PROPERTY(bool canChooseBoot READ canChooseBoot NOTIFY disksChanged)
    Q_PROPERTY(bool alwaysStarStorage READ alwaysStarStorage NOTIFY disksChanged)
    // A boot change is running.
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // The outcome of the last boot change.
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)

public:
    using Restarter = std::function<void()>;

    explicit StorageBackend(QObject *parent = nullptr);

    QString state() const;
    QString errorString() const;
    QString step() const;
    QString partition() const;
    QVariantList disks() const;
    QStringList existing() const;
    bool uefi() const;
    bool canChooseBoot() const;
    bool alwaysStarStorage() const;
    bool busy() const;
    QString message() const;

    // For tests: other programs instead of the helper and pkexec, and what
    // restarting does.
    void setHelper(const QString &program);
    void setPkexec(const QString &program);
    void setRestarter(Restarter restarter);

    // Lists the disks again; an error or a finished set-up is cleared.
    Q_INVOKABLE void refresh();
    // Erases the disk `name`; `confirmation` is what the person typed.
    Q_INVOKABLE void format(const QString &name, const QString &confirmation);
    // "next", "always" or "never".
    Q_INVOKABLE void setBoot(const QString &mode);
    // Sets the next start to Star Storage, then restarts the computer.
    Q_INVOKABLE void restartIntoStarStorage();

Q_SIGNALS:
    void stateChanged();
    void stepChanged();
    void disksChanged();
    void busyChanged();
    void messageChanged();

private:
    void setState(const QString &state, const QString &error = QString());
    void setStep(const QString &step);
    void setBusy(bool busy);
    void setMessage(const QString &message);
    // Runs the helper's list; the state only changes from "loading".
    void listDisks();
    void listFinished(int exitCode, QProcess::ExitStatus status);
    void readFormatOutput();
    void formatFinished(int exitCode, QProcess::ExitStatus status);
    void runBoot(const QString &mode, bool restart);
    void bootFinished(const QString &mode, bool restart, int exitCode, QProcess::ExitStatus status);
    QString pkexecError(int exitCode) const;

    QString m_state = QStringLiteral("loading");
    QString m_errorString;
    QString m_step;
    QString m_partition;
    QString m_formatError;
    QVariantList m_disks;
    QStringList m_existing;
    bool m_uefi = false;
    bool m_canChooseBoot = false;
    bool m_always = false;
    bool m_busy = false;
    QString m_message;
    QString m_helper;
    QString m_pkexec = QStringLiteral("/usr/bin/pkexec");
    Restarter m_restarter;
    QProcess *m_list = nullptr;
    QProcess *m_format = nullptr;
    QProcess *m_boot = nullptr;
    QByteArray m_formatBuffer;
};
