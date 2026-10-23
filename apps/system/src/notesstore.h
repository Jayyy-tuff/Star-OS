// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QList>
#include <QQmlEngine>
#include <QString>

// The desktop's sticky notes, saved as JSON in
// $XDG_DATA_HOME/staros/notes.json (on Star Storage when the live medium
// keeps changes there). One instance per QML engine; the file is reloaded when
// another process or engine changes it.
class NotesStore : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(QString filePath READ filePath CONSTANT)

public:
    enum Role {
        NoteIdRole = Qt::UserRole + 1,
        NoteTextRole,
        PosXRole,
        PosYRole,
    };
    Q_ENUM(Role)

    static constexpr int MaxNotes = 200;
    static constexpr int MaxTextLength = 10000;

    explicit NotesStore(QObject *parent = nullptr);
    // For tests: another file.
    explicit NotesStore(const QString &filePath, QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString filePath() const;

    // Returns the new note's id, or an empty string when the limit is reached.
    Q_INVOKABLE QString addNote(const QString &text);
    Q_INVOKABLE void updateNote(const QString &noteId, const QString &text);
    Q_INVOKABLE void moveNote(const QString &noteId, double posX, double posY);
    Q_INVOKABLE void removeNote(const QString &noteId);
    Q_INVOKABLE void reload();

Q_SIGNALS:
    void countChanged();

private:
    struct Note {
        QString id;
        QString text;
        double x = 0;
        double y = 0;
        bool operator==(const Note &other) const = default;
    };

    int indexOf(const QString &noteId) const;
    bool save();
    void watch();

    QString m_filePath;
    QList<Note> m_notes;
    QFileSystemWatcher m_watcher;
};
