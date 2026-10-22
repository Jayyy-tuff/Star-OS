// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QString>
#include <QStringList>

#include <functional>

// Runs the flatpak command line asynchronously, never through a shell: the
// arguments go to QProcess as a list, standard input is empty, and every run
// reports once. The program is fixed at construction; the app uses "flatpak"
// from PATH and the tests a fake script.
class FlatpakCli : public QObject
{
    Q_OBJECT

public:
    struct Result {
        bool started = false;
        bool crashed = false;
        int exitCode = -1;
        QString output;
        QString errorOutput;

        bool ok() const
        {
            return started && !crashed && exitCode == 0;
        }
        // The last line of standard error without flatpak's "error: " prefix,
        // or why the program did not run.
        QString message() const;
    };

    using Done = std::function<void(const Result &)>;
    using Line = std::function<void(const QString &)>;

    explicit FlatpakCli(const QString &program, QObject *parent = nullptr);

    QString program() const;

    // `line` gets each line of standard output as it arrives (progress).
    void run(const QStringList &arguments, Done done, Line line = {});
    bool startDetached(const QStringList &arguments) const;

private:
    QString m_program;
};
