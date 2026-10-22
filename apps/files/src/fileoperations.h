// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QHash>
#include <QList>
#include <QObject>
#include <QString>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

class KJob;

namespace KIO
{
class CopyJob;
}

// File operations as KIO jobs. No job has a UI delegate (Files does not link
// KIOWidgets), so KIO never shows a dialog: a name conflict or any other
// problem ends the job with an error, which is reported through failed() for
// the window to show inline. Questions (overwrite, confirm deletion) are the
// window's business before it calls in here.
class FileOperations : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool busy READ isBusy NOTIFY busyChanged)
    // Percent done of the most recently started operation, or -1 if unknown.
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(bool canPaste READ canPaste NOTIFY canPasteChanged)

public:
    explicit FileOperations(QObject *parent = nullptr);
    ~FileOperations() override;

    bool isBusy() const;
    int progress() const;
    QString statusText() const;
    bool canPaste() const;

    // Why a new file or folder name cannot be used, or an empty string.
    Q_INVOKABLE QString nameError(const QString &name) const;

    // Opens a local file in its preferred application. Programs are refused,
    // scripts and desktop entries are opened as text, and nothing is opened
    // when no application is installed for the type (KIO would otherwise
    // fall back to xdg-open, which may offer to run the file).
    Q_INVOKABLE void open(const QUrl &url);
    Q_INVOKABLE void copy(const QList<QUrl> &urls, const QUrl &destination);
    Q_INVOKABLE void move(const QList<QUrl> &urls, const QUrl &destination);
    Q_INVOKABLE void rename(const QUrl &url, const QString &newName);
    Q_INVOKABLE void createFolder(const QUrl &parent, const QString &name);
    Q_INVOKABLE void moveToTrash(const QList<QUrl> &urls);
    Q_INVOKABLE void restoreFromTrash(const QList<QUrl> &trashUrls);
    Q_INVOKABLE void emptyTrash();
    Q_INVOKABLE void deletePermanently(const QList<QUrl> &urls);

    // The system clipboard, in the format KDE applications use (text/uri-list
    // plus application/x-kde-cutselection), so Files and Dolphin interoperate.
    Q_INVOKABLE void copyToClipboard(const QList<QUrl> &urls);
    Q_INVOKABLE void cutToClipboard(const QList<QUrl> &urls);
    Q_INVOKABLE void paste(const QUrl &destination);

Q_SIGNALS:
    void busyChanged();
    void progressChanged();
    void statusTextChanged();
    void canPasteChanged();
    // urls: what the operation produced (new folder, renamed item, copies,
    // Trash entries), for the window to select. May be empty.
    void finished(const QString &operation, const QList<QUrl> &urls);
    void failed(const QString &operation, const QString &message);

private:
    struct Running {
        QString operation;
        QString status;
        QList<QUrl> results;
    };

    void start(KJob *job, const QString &operation, const QString &status, const QList<QUrl> &results = {});
    void collectResults(KIO::CopyJob *job, const QList<QUrl> &sources);
    void transfer(const QString &operation, const QList<QUrl> &urls, const QUrl &destination, bool moving);
    void setProgress(int progress);
    void setClipboard(const QList<QUrl> &urls, bool cut);

    QHash<KJob *, Running> m_running;
    QList<KJob *> m_order; // oldest first; the newest one is reported
    int m_progress = -1;
};
