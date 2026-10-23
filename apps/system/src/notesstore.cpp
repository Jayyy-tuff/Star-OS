// SPDX-License-Identifier: GPL-3.0-or-later
#include "notesstore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>

#include <algorithm>
#include <cmath>

namespace
{
double clampPosition(double value)
{
    return std::isfinite(value) ? std::clamp(value, 0.0, 1.0) : 0.0;
}
}

NotesStore::NotesStore(QObject *parent)
    : NotesStore(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/staros/notes.json"), parent)
{
}

NotesStore::NotesStore(const QString &filePath, QObject *parent)
    : QAbstractListModel(parent)
    , m_filePath(filePath)
{
    // Saving replaces the file, so the folder is watched as well.
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &NotesStore::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &NotesStore::reload);
    reload();
}

int NotesStore::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_notes.size());
}

QVariant NotesStore::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    const Note &note = m_notes.at(index.row());
    switch (role) {
    case NoteIdRole:
        return note.id;
    case Qt::DisplayRole:
    case NoteTextRole:
        return note.text;
    case PosXRole:
        return note.x;
    case PosYRole:
        return note.y;
    }
    return {};
}

QHash<int, QByteArray> NotesStore::roleNames() const
{
    return {
        {NoteIdRole, "noteId"},
        {NoteTextRole, "noteText"},
        {PosXRole, "posX"},
        {PosYRole, "posY"},
    };
}

QString NotesStore::filePath() const
{
    return m_filePath;
}

int NotesStore::indexOf(const QString &noteId) const
{
    for (qsizetype i = 0; i < m_notes.size(); ++i) {
        if (m_notes.at(i).id == noteId) {
            return int(i);
        }
    }
    return -1;
}

QString NotesStore::add(const QString &text)
{
    if (m_notes.size() >= MaxNotes) {
        return {};
    }
    Note note;
    note.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    note.text = text.left(MaxTextLength);
    const int row = int(m_notes.size());
    beginInsertRows(QModelIndex(), row, row);
    m_notes.append(note);
    endInsertRows();
    Q_EMIT countChanged();
    save();
    return note.id;
}

void NotesStore::update(const QString &noteId, const QString &text)
{
    const int row = indexOf(noteId);
    const QString limited = text.left(MaxTextLength);
    if (row < 0 || m_notes.at(row).text == limited) {
        return;
    }
    m_notes[row].text = limited;
    Q_EMIT dataChanged(index(row), index(row), {NoteTextRole, Qt::DisplayRole});
    save();
}

void NotesStore::move(const QString &noteId, double posX, double posY)
{
    const int row = indexOf(noteId);
    if (row < 0) {
        return;
    }
    m_notes[row].x = clampPosition(posX);
    m_notes[row].y = clampPosition(posY);
    Q_EMIT dataChanged(index(row), index(row), {PosXRole, PosYRole});
    save();
}

void NotesStore::remove(const QString &noteId)
{
    const int row = indexOf(noteId);
    if (row < 0) {
        return;
    }
    beginRemoveRows(QModelIndex(), row, row);
    m_notes.removeAt(row);
    endRemoveRows();
    Q_EMIT countChanged();
    save();
}

bool NotesStore::save()
{
    QJsonArray notes;
    for (const Note &note : std::as_const(m_notes)) {
        notes.append(QJsonObject{
            {QStringLiteral("id"), note.id},
            {QStringLiteral("text"), note.text},
            {QStringLiteral("x"), note.x},
            {QStringLiteral("y"), note.y},
        });
    }
    const QJsonObject root{{QStringLiteral("version"), 1}, {QStringLiteral("notes"), notes}};
    QDir().mkpath(QFileInfo(m_filePath).absolutePath());
    QSaveFile file(m_filePath);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    const bool ok = file.commit();
    watch();
    return ok;
}

void NotesStore::reload()
{
    QList<Note> loaded;
    QFile file(m_filePath);
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonArray notes = QJsonDocument::fromJson(file.readAll()).object().value(QStringLiteral("notes")).toArray();
        for (const QJsonValue &value : notes) {
            const QJsonObject object = value.toObject();
            Note note;
            note.id = object.value(QStringLiteral("id")).toString();
            if (note.id.isEmpty() || loaded.size() >= MaxNotes) {
                continue;
            }
            note.text = object.value(QStringLiteral("text")).toString().left(MaxTextLength);
            note.x = clampPosition(object.value(QStringLiteral("x")).toDouble());
            note.y = clampPosition(object.value(QStringLiteral("y")).toDouble());
            loaded.append(note);
        }
    }
    watch();
    if (loaded == m_notes) {
        return;
    }
    const bool countChanges = loaded.size() != m_notes.size();
    beginResetModel();
    m_notes = loaded;
    endResetModel();
    if (countChanges) {
        Q_EMIT countChanged();
    }
}

void NotesStore::watch()
{
    const QString folder = QFileInfo(m_filePath).absolutePath();
    if (QFileInfo::exists(folder) && !m_watcher.directories().contains(folder)) {
        m_watcher.addPath(folder);
    }
    if (QFileInfo::exists(m_filePath) && !m_watcher.files().contains(m_filePath)) {
        m_watcher.addPath(m_filePath);
    }
}
