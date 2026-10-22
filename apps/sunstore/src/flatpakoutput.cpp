// SPDX-License-Identifier: GPL-3.0-or-later
#include "flatpakoutput.h"

#include <QCoreApplication>
#include <QPair>
#include <QRegularExpression>

namespace
{
QList<QStringList> rows(const QString &output)
{
    QList<QStringList> result;
    const QStringList lines = output.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
    for (const QString &line : lines) {
        if (!line.trimmed().isEmpty()) {
            result.append(line.split(QLatin1Char('\t')));
        }
    }
    return result;
}

QString cell(const QStringList &row, qsizetype column)
{
    return column < row.size() ? row.at(column).trimmed() : QString();
}

QString tr(const char *text)
{
    return QCoreApplication::translate("FlatpakOutput", text);
}

// A minimal key file reader: [group] headers and key=value lines.
QHash<QString, QHash<QString, QString>> keyFile(const QString &text)
{
    QHash<QString, QHash<QString, QString>> groups;
    QString group;
    const QStringList lines = text.split(QLatin1Char('\n'));
    for (const QString &raw : lines) {
        const QString line = raw.trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))) {
            group = line.mid(1, line.size() - 2);
            continue;
        }
        const qsizetype equals = line.indexOf(QLatin1Char('='));
        if (equals > 0 && !group.isEmpty()) {
            groups[group].insert(line.left(equals).trimmed(), line.mid(equals + 1).trimmed());
        }
    }
    return groups;
}

QStringList listValue(const QHash<QString, QString> &group, const QString &key)
{
    QStringList values;
    const QStringList parts = group.value(key).split(QLatin1Char(';'), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        const QString value = part.trimmed();
        // A leading '!' removes a permission; it grants nothing.
        if (!value.isEmpty() && !value.startsWith(QLatin1Char('!'))) {
            values.append(value);
        }
    }
    return values;
}

QString filesystemText(QString entry)
{
    bool readOnly = false;
    if (entry.endsWith(QLatin1String(":ro"))) {
        readOnly = true;
        entry.chop(3);
    } else if (entry.endsWith(QLatin1String(":rw")) || entry.endsWith(QLatin1String(":create"))) {
        entry = entry.left(entry.lastIndexOf(QLatin1Char(':')));
    }
    QString what;
    if (entry == QLatin1String("host") || entry == QLatin1String("host-os") || entry == QLatin1String("host-etc")) {
        what = entry == QLatin1String("host") ? tr("All files on this computer") : tr("System files (%1)").arg(entry);
    } else if (entry == QLatin1String("home") || entry == QLatin1String("~")) {
        what = tr("Your home folder");
    } else if (entry.startsWith(QLatin1String("xdg-"))) {
        what = tr("Your %1 folder").arg(entry.mid(4));
    } else {
        what = tr("The folder %1").arg(entry);
    }
    return readOnly ? tr("%1 (read only)").arg(what) : what;
}
}

namespace FlatpakOutput
{
QStringList remoteNames(const QString &output)
{
    QStringList names;
    for (const QStringList &row : rows(output)) {
        const QString name = cell(row, 0);
        if (!name.isEmpty()) {
            names.append(name);
        }
    }
    return names;
}

QList<InstalledApp> installedApps(const QString &output)
{
    QList<InstalledApp> apps;
    for (const QStringList &row : rows(output)) {
        InstalledApp app{cell(row, 0), cell(row, 1), cell(row, 2), cell(row, 3)};
        if (isValidAppId(app.id)) {
            if (app.name.isEmpty()) {
                app.name = app.id;
            }
            apps.append(app);
        }
    }
    return apps;
}

QHash<QString, QString> updates(const QString &output)
{
    QHash<QString, QString> result;
    for (const QStringList &row : rows(output)) {
        const QString id = cell(row, 0);
        if (isValidAppId(id)) {
            result.insert(id, cell(row, 1));
        }
    }
    return result;
}

QStringList permissions(const QString &metadata)
{
    const auto groups = keyFile(metadata);
    const QHash<QString, QString> context = groups.value(QStringLiteral("Context"));
    QStringList result;

    const QStringList shared = listValue(context, QStringLiteral("shared"));
    if (shared.contains(QLatin1String("network"))) {
        result.append(tr("Network access"));
    }
    const QStringList sockets = listValue(context, QStringLiteral("sockets"));
    if (sockets.contains(QLatin1String("x11"))) {
        result.append(tr("X11 display: can see other X11 windows and their input"));
    }
    if (sockets.contains(QLatin1String("pulseaudio"))) {
        result.append(tr("Sound playback and recording"));
    }
    if (sockets.contains(QLatin1String("system-bus"))) {
        result.append(tr("Full access to the system bus"));
    }
    if (sockets.contains(QLatin1String("session-bus"))) {
        result.append(tr("Full access to the session bus"));
    }
    if (sockets.contains(QLatin1String("ssh-auth"))) {
        result.append(tr("Your SSH keys (through the SSH agent)"));
    }
    if (sockets.contains(QLatin1String("cups"))) {
        result.append(tr("Printing"));
    }
    if (sockets.contains(QLatin1String("pcsc")) || sockets.contains(QLatin1String("gpg-agent"))) {
        result.append(tr("Smart cards and GPG keys"));
    }
    const QStringList devices = listValue(context, QStringLiteral("devices"));
    if (devices.contains(QLatin1String("all"))) {
        result.append(tr("All devices, such as webcams and USB devices"));
    } else {
        if (devices.contains(QLatin1String("dri"))) {
            result.append(tr("Graphics acceleration"));
        }
        if (devices.contains(QLatin1String("input"))) {
            result.append(tr("Input devices"));
        }
        if (devices.contains(QLatin1String("usb"))) {
            result.append(tr("USB devices"));
        }
        if (devices.contains(QLatin1String("kvm"))) {
            result.append(tr("Virtualisation"));
        }
    }
    const QStringList filesystems = listValue(context, QStringLiteral("filesystems"));
    for (const QString &entry : filesystems) {
        result.append(filesystemText(entry));
    }

    const QList<QPair<QString, QString>> buses = {
        {QStringLiteral("Session Bus Policy"), tr("session")},
        {QStringLiteral("System Bus Policy"), tr("system")},
    };
    for (const auto &bus : buses) {
        const QHash<QString, QString> policy = groups.value(bus.first);
        QStringList names = policy.keys();
        names.sort();
        for (const QString &name : names) {
            const QString access = policy.value(name);
            if (access == QLatin1String("talk")) {
                result.append(tr("Talks to %1 on the %2 bus").arg(name, bus.second));
            } else if (access == QLatin1String("own")) {
                result.append(tr("Owns %1 on the %2 bus").arg(name, bus.second));
            }
        }
    }
    return result;
}

bool isValidAppId(const QString &id)
{
    static const QRegularExpression pattern(
        QStringLiteral("^[A-Za-z_][A-Za-z0-9_]*(\\.[A-Za-z_][A-Za-z0-9_]*)+\\.[A-Za-z_][A-Za-z0-9_-]*$"));
    return id.size() <= 255 && pattern.match(id).hasMatch();
}
}
