// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

// A fake flatpak program for the Sun Store tests: a POSIX shell script that
// appends each command line to <state>/log and answers from files in <state>:
//   remotes, installed, updates  printed by remotes, list, remote-ls
//   appstream.xml                copied to the active catalogue folder by
//                                update --appstream
//   metadata                     printed by remote-info
//   fail-<command>               printed to standard error, exit status 1
// install, uninstall and update change installed / updates like flatpak
// would; run creates ran-<app id>.

#include <QByteArray>
#include <QDir>
#include <QFile>
#include <QString>
#include <QStringList>

namespace FakeFlatpak
{
inline const char *Script = R"(#!/bin/sh
state='@STATE@'
active='@ACTIVE@'
printf '%s\n' "$*" >> "$state/log"
cmd=$1
for last; do :; done
if [ -f "$state/fail-$cmd" ]; then
    cat "$state/fail-$cmd" >&2
    exit 1
fi
case $cmd in
remotes)
    [ ! -f "$state/remotes" ] || cat "$state/remotes"
    ;;
remote-add)
    printf 'flathub\thttps://dl.flathub.org/repo/\n' > "$state/remotes"
    ;;
update)
    case " $* " in
    *" --appstream "*)
        mkdir -p "$active" && cp "$state/appstream.xml" "$active/appstream.xml"
        ;;
    *)
        echo "Updating app/org.example.Editor/x86_64/stable"
        rm -f "$state/updates"
        ;;
    esac
    ;;
list)
    [ ! -f "$state/installed" ] || cat "$state/installed"
    ;;
remote-ls)
    [ ! -f "$state/updates" ] || cat "$state/updates"
    ;;
install)
    echo "Installing app/$last/x86_64/stable"
    printf '%s\t%s\t2.1\tflathub\n' "$last" "$last" >> "$state/installed"
    ;;
uninstall)
    echo "Uninstalling app/$last/x86_64/stable"
    row=$(printf '%s\t' "$last")
    grep -v -F "$row" "$state/installed" > "$state/installed.new"
    mv "$state/installed.new" "$state/installed"
    ;;
remote-info)
    cat "$state/metadata"
    ;;
run)
    : > "$state/ran-$last"
    ;;
*)
    echo "error: unknown command $cmd" >&2
    exit 1
    ;;
esac
)";

// Writes the script as <stateDir>/<name> and returns its path, or an empty
// string on failure.
inline QString create(const QString &stateDir, const QString &activeDir, const QString &name = QStringLiteral("flatpak"))
{
    QString text = QString::fromUtf8(Script);
    text.replace(QStringLiteral("@STATE@"), stateDir);
    text.replace(QStringLiteral("@ACTIVE@"), activeDir);
    QFile file(QDir(stateDir).filePath(name));
    if (!file.open(QIODevice::WriteOnly) || file.write(text.toUtf8()) < 0) {
        return {};
    }
    file.close();
    if (!file.setPermissions(QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner)) {
        return {};
    }
    return file.fileName();
}

inline bool write(const QString &stateDir, const QString &name, const QByteArray &content)
{
    QFile file(QDir(stateDir).filePath(name));
    return file.open(QIODevice::WriteOnly) && file.write(content) == content.size();
}

inline QStringList log(const QString &stateDir)
{
    QFile file(QDir(stateDir).filePath(QStringLiteral("log")));
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return QString::fromUtf8(file.readAll()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
}
}
