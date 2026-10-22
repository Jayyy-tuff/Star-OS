// SPDX-License-Identifier: GPL-3.0-or-later
#include "flatpakcli.h"

#include <QProcess>

#include <memory>

QString FlatpakCli::Result::message() const
{
    const QStringList lines = errorOutput.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (auto it = lines.crbegin(); it != lines.crend(); ++it) {
        QString line = it->trimmed();
        if (line.isEmpty()) {
            continue;
        }
        if (line.startsWith(QLatin1String("error: "), Qt::CaseInsensitive)) {
            line = line.mid(7).trimmed();
        }
        return line;
    }
    if (!started) {
        return QObject::tr("flatpak could not be started.");
    }
    if (crashed) {
        return QObject::tr("flatpak stopped unexpectedly.");
    }
    return exitCode == 0 ? QString() : QObject::tr("flatpak failed (exit status %1).").arg(exitCode);
}

FlatpakCli::FlatpakCli(const QString &program, QObject *parent)
    : QObject(parent)
    , m_program(program)
{
}

QString FlatpakCli::program() const
{
    return m_program;
}

void FlatpakCli::run(const QStringList &arguments, Done done, Line line)
{
    auto *process = new QProcess(this);
    process->setProgram(m_program);
    process->setArguments(arguments);
    process->setStandardInputFile(QProcess::nullDevice());

    struct State {
        bool reported = false;
        QByteArray pending; // standard output not yet split into lines
        QByteArray output;
    };
    auto state = std::make_shared<State>();

    auto report = [process, state, done](const FlatpakCli::Result &result) {
        if (state->reported) {
            return;
        }
        state->reported = true;
        process->deleteLater();
        if (done) {
            done(result);
        }
    };

    connect(process, &QProcess::readyReadStandardOutput, this, [process, state, line] {
        const QByteArray data = process->readAllStandardOutput();
        state->output += data;
        if (!line) {
            return;
        }
        state->pending += data;
        // Progress may be redrawn with carriage returns.
        state->pending.replace('\r', '\n');
        qsizetype end;
        while ((end = state->pending.indexOf('\n')) >= 0) {
            const QString text = QString::fromUtf8(state->pending.left(end)).trimmed();
            state->pending.remove(0, end + 1);
            if (!text.isEmpty()) {
                line(text);
            }
        }
    });
    connect(process, &QProcess::errorOccurred, this, [process, report](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            FlatpakCli::Result result;
            result.errorOutput = process->errorString();
            report(result);
        }
    });
    connect(process, &QProcess::finished, this, [process, state, report](int exitCode, QProcess::ExitStatus status) {
        state->output += process->readAllStandardOutput();
        FlatpakCli::Result result;
        result.started = true;
        result.crashed = status == QProcess::CrashExit;
        result.exitCode = exitCode;
        result.output = QString::fromUtf8(state->output);
        result.errorOutput = QString::fromUtf8(process->readAllStandardError());
        report(result);
    });

    process->start(QIODevice::ReadOnly);
}

bool FlatpakCli::startDetached(const QStringList &arguments) const
{
    QProcess process;
    process.setProgram(m_program);
    process.setArguments(arguments);
    process.setStandardInputFile(QProcess::nullDevice());
    return process.startDetached();
}
