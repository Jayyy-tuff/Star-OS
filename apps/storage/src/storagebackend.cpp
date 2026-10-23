// SPDX-License-Identifier: GPL-3.0-or-later
#include "storagebackend.h"

#include <QJsonArray>
#include <QJsonDocument>

namespace
{
// The last JSON object among the lines a helper printed.
QJsonObject lastObject(const QByteArray &output)
{
    const QList<QByteArray> lines = output.split('\n');
    for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
        const QJsonDocument document = QJsonDocument::fromJson(it->trimmed());
        if (document.isObject()) {
            return document.object();
        }
    }
    return {};
}

void restartComputer()
{
    QProcess::startDetached(QStringLiteral("/usr/bin/systemctl"), {QStringLiteral("reboot")});
}
}

StorageBackend::StorageBackend(QObject *parent)
    : QObject(parent)
    , m_helper(QStringLiteral(STAROS_STORAGE_HELPER))
    , m_restarter(&restartComputer)
{
}

QString StorageBackend::state() const
{
    return m_state;
}

QString StorageBackend::errorString() const
{
    return m_errorString;
}

QString StorageBackend::step() const
{
    return m_step;
}

QString StorageBackend::partition() const
{
    return m_partition;
}

QVariantList StorageBackend::disks() const
{
    return m_disks;
}

QStringList StorageBackend::existing() const
{
    return m_existing;
}

bool StorageBackend::uefi() const
{
    return m_uefi;
}

bool StorageBackend::canChooseBoot() const
{
    return m_canChooseBoot;
}

bool StorageBackend::alwaysStarStorage() const
{
    return m_always;
}

bool StorageBackend::busy() const
{
    return m_busy;
}

QString StorageBackend::message() const
{
    return m_message;
}

void StorageBackend::setHelper(const QString &program)
{
    m_helper = program;
}

void StorageBackend::setPkexec(const QString &program)
{
    m_pkexec = program;
}

void StorageBackend::setRestarter(Restarter restarter)
{
    m_restarter = std::move(restarter);
}

void StorageBackend::setState(const QString &state, const QString &error)
{
    if (state == m_state && error == m_errorString) {
        return;
    }
    m_state = state;
    m_errorString = error;
    Q_EMIT stateChanged();
}

void StorageBackend::setStep(const QString &step)
{
    if (step != m_step) {
        m_step = step;
        Q_EMIT stepChanged();
    }
}

void StorageBackend::setBusy(bool busy)
{
    if (busy != m_busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

void StorageBackend::setMessage(const QString &message)
{
    m_message = message;
    Q_EMIT messageChanged();
}

QString StorageBackend::pkexecError(int exitCode) const
{
    if (exitCode == 126) {
        return tr("Permission was not given.");
    }
    if (exitCode == 127) {
        return tr("Star OS did not allow it, or the helper could not be started.");
    }
    return tr("The helper stopped with status %1.").arg(exitCode);
}

void StorageBackend::refresh()
{
    if (m_state == QLatin1String("working")) {
        return;
    }
    setState(QStringLiteral("loading"));
    listDisks();
}

void StorageBackend::listDisks()
{
    if (m_list) {
        return;
    }
    m_list = new QProcess(this);
    m_list->setProgram(m_helper);
    m_list->setArguments({QStringLiteral("list")});
    connect(m_list, &QProcess::finished, this, &StorageBackend::listFinished);
    connect(m_list, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            listFinished(-1, QProcess::CrashExit);
        }
    });
    // The helper and pkexec read nothing; no open input pipe is left behind.
    m_list->setStandardInputFile(QProcess::nullDevice());
    m_list->start(QIODevice::ReadOnly);
}

void StorageBackend::listFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_list) {
        return;
    }
    const QJsonObject result = lastObject(m_list->readAllStandardOutput());
    const QString problem = m_list->error() == QProcess::FailedToStart ? m_list->errorString() : result.value(QStringLiteral("error")).toString();
    m_list->deleteLater();
    m_list = nullptr;

    if (status != QProcess::NormalExit || exitCode != 0 || !result.value(QStringLiteral("disks")).isArray()) {
        if (m_state == QLatin1String("loading")) {
            const QString why = problem.isEmpty() ? tr("the helper stopped with status %1.").arg(exitCode) : problem;
            setState(QStringLiteral("error"), tr("Star Storage could not list the disks: %1").arg(why));
        }
        return;
    }
    m_disks = result.value(QStringLiteral("disks")).toArray().toVariantList();
    m_existing.clear();
    const QJsonArray existing = result.value(QStringLiteral("existing")).toArray();
    for (const QJsonValue &name : existing) {
        m_existing.append(name.toString());
    }
    m_uefi = result.value(QStringLiteral("uefi")).toBool();
    // null: the boot loader is not known; the helper checks again as root.
    const QJsonValue systemdBoot = result.value(QStringLiteral("systemdBoot"));
    m_canChooseBoot = m_uefi && !(systemdBoot.isBool() && !systemdBoot.toBool());
    m_always = result.value(QStringLiteral("always")).toBool();
    Q_EMIT disksChanged();
    if (m_state == QLatin1String("loading")) {
        setState(QStringLiteral("ready"));
    }
}

void StorageBackend::format(const QString &name, const QString &confirmation)
{
    if (m_format || m_state != QLatin1String("ready")) {
        return;
    }
    m_formatBuffer.clear();
    m_formatError.clear();
    m_partition.clear();
    setStep(tr("Asking for permission…"));
    setState(QStringLiteral("working"));

    m_format = new QProcess(this);
    m_format->setProgram(m_pkexec);
    m_format->setArguments({m_helper, QStringLiteral("format"), name, confirmation});
    connect(m_format, &QProcess::readyReadStandardOutput, this, &StorageBackend::readFormatOutput);
    connect(m_format, &QProcess::finished, this, &StorageBackend::formatFinished);
    connect(m_format, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_formatError = tr("%1 could not be started.").arg(m_pkexec);
            formatFinished(-1, QProcess::CrashExit);
        }
    });
    // The helper and pkexec read nothing; no open input pipe is left behind.
    m_format->setStandardInputFile(QProcess::nullDevice());
    m_format->start(QIODevice::ReadOnly);
}

void StorageBackend::readFormatOutput()
{
    if (!m_format) {
        return;
    }
    m_formatBuffer += m_format->readAllStandardOutput();
    qsizetype newline;
    while ((newline = m_formatBuffer.indexOf('\n')) >= 0) {
        const QJsonObject line = QJsonDocument::fromJson(m_formatBuffer.left(newline).trimmed()).object();
        m_formatBuffer.remove(0, newline + 1);
        if (line.contains(QStringLiteral("step"))) {
            setStep(line.value(QStringLiteral("message")).toString());
        }
        if (line.value(QStringLiteral("done")).toBool()) {
            m_partition = line.value(QStringLiteral("partition")).toString();
        }
        if (line.contains(QStringLiteral("error"))) {
            m_formatError = line.value(QStringLiteral("error")).toString();
        }
    }
}

void StorageBackend::formatFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_format) {
        return;
    }
    m_formatBuffer += '\n';
    readFormatOutput();
    m_format->deleteLater();
    m_format = nullptr;
    if (status == QProcess::NormalExit && exitCode == 0 && !m_partition.isEmpty()) {
        setState(QStringLiteral("done"));
    } else {
        const QString why = m_formatError.isEmpty() ? pkexecError(exitCode) : m_formatError;
        setState(QStringLiteral("error"), tr("Star Storage was not set up. %1").arg(why));
    }
    listDisks();
}

void StorageBackend::setBoot(const QString &mode)
{
    runBoot(mode, false);
}

void StorageBackend::restartIntoStarStorage()
{
    runBoot(QStringLiteral("next"), true);
}

void StorageBackend::runBoot(const QString &mode, bool restart)
{
    if (m_boot) {
        return;
    }
    setBusy(true);
    setMessage(QString());
    m_boot = new QProcess(this);
    m_boot->setProgram(m_pkexec);
    m_boot->setArguments({m_helper, QStringLiteral("boot"), mode});
    connect(m_boot, &QProcess::finished, this, [this, mode, restart](int exitCode, QProcess::ExitStatus status) {
        bootFinished(mode, restart, exitCode, status);
    });
    connect(m_boot, &QProcess::errorOccurred, this, [this, mode, restart](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            bootFinished(mode, restart, 127, QProcess::CrashExit);
        }
    });
    // The helper and pkexec read nothing; no open input pipe is left behind.
    m_boot->setStandardInputFile(QProcess::nullDevice());
    m_boot->start(QIODevice::ReadOnly);
}

void StorageBackend::bootFinished(const QString &mode, bool restart, int exitCode, QProcess::ExitStatus status)
{
    if (!m_boot) {
        return;
    }
    const QJsonObject result = lastObject(m_boot->readAllStandardOutput());
    m_boot->deleteLater();
    m_boot = nullptr;
    setBusy(false);

    if (status != QProcess::NormalExit || exitCode != 0 || !result.value(QStringLiteral("done")).toBool()) {
        const QString why = result.value(QStringLiteral("error")).toString();
        setMessage(tr("The start was not changed. %1").arg(why.isEmpty() ? pkexecError(exitCode) : why));
        return;
    }
    if (restart) {
        setMessage(tr("Restarting into Star Storage…"));
        m_restarter();
        return;
    }
    if (mode == QLatin1String("next")) {
        setMessage(tr("Star OS starts with Star Storage next time."));
    } else if (mode == QLatin1String("always")) {
        setMessage(tr("Star OS now starts with Star Storage every time."));
    } else {
        setMessage(tr("Star OS no longer starts with Star Storage by default."));
    }
    listDisks();
}
