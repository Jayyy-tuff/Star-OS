// SPDX-License-Identifier: GPL-3.0-or-later
#include "fileoperations.h"

#include <KApplicationTrader>
#include <KIO/CopyJob>
#include <KIO/DeleteJob>
#include <KIO/EmptyTrashJob>
#include <KIO/Global>
#include <KIO/MkdirJob>
#include <KIO/OpenUrlJob>
#include <KIO/RestoreJob>
#include <KJob>
#include <KService>

#include <QClipboard>
#include <QFileInfo>
#include <QGuiApplication>
#include <QMimeData>
#include <QMimeDatabase>
#include <QMimeType>
#include <QStringList>

#include <algorithm>

namespace
{
const QString OpOpen = QStringLiteral("open");
const QString OpCopy = QStringLiteral("copy");
const QString OpMove = QStringLiteral("move");
const QString OpPaste = QStringLiteral("paste");
const QString OpRename = QStringLiteral("rename");
const QString OpNewFolder = QStringLiteral("newFolder");
const QString OpTrash = QStringLiteral("trash");
const QString OpRestore = QStringLiteral("restore");
const QString OpEmptyTrash = QStringLiteral("emptyTrash");
const QString OpDelete = QStringLiteral("delete");

const QString CutSelectionMime = QStringLiteral("application/x-kde-cutselection");

// Executable text, the same test as KIO::OpenUrlJob's.
bool isScript(const QMimeType &mime)
{
    return mime.inherits(QStringLiteral("application/x-executable"))
        && (mime.inherits(QStringLiteral("text/plain")) || mime.name().startsWith(QLatin1String("text/")));
}

bool isProgram(const QMimeType &mime)
{
    if (isScript(mime)) {
        return false;
    }
    // Position-independent executables are typed as shared libraries by older
    // shared-mime-info releases; application/x-pie-executable by newer ones.
    static const QStringList programTypes = {
        QStringLiteral("application/x-executable"),
        QStringLiteral("application/x-sharedlib"),
        QStringLiteral("application/x-pie-executable"),
        QStringLiteral("application/x-ms-dos-executable"),
        QStringLiteral("application/vnd.microsoft.portable-executable"),
    };
    return std::any_of(programTypes.cbegin(), programTypes.cend(), [&mime](const QString &type) {
        return mime.inherits(type);
    });
}

QUrl childUrl(const QUrl &folder, const QString &name)
{
    QUrl child = folder;
    const QString path = folder.path();
    child.setPath(path.endsWith(QLatin1Char('/')) ? path + name : path + QLatin1Char('/') + name);
    return child;
}
}

FileOperations::FileOperations(QObject *parent)
    : QObject(parent)
{
    connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &FileOperations::canPasteChanged);
}

FileOperations::~FileOperations() = default;

bool FileOperations::isBusy() const
{
    return !m_running.isEmpty();
}

int FileOperations::progress() const
{
    return m_progress;
}

QString FileOperations::statusText() const
{
    return m_order.isEmpty() ? QString() : m_running.value(m_order.constLast()).status;
}

bool FileOperations::canPaste() const
{
    const QMimeData *data = QGuiApplication::clipboard()->mimeData();
    return data && data->hasUrls();
}

QString FileOperations::nameError(const QString &name) const
{
    if (name.trimmed().isEmpty()) {
        return tr("Enter a name.");
    }
    if (name.contains(QLatin1Char('/'))) {
        return tr("A name cannot contain “/”.");
    }
    if (name == QLatin1String(".") || name == QLatin1String("..")) {
        return tr("“%1” cannot be used as a name.").arg(name);
    }
    return QString();
}

void FileOperations::open(const QUrl &url)
{
    const QString name = url.fileName();
    if (!url.isLocalFile()) {
        Q_EMIT failed(OpOpen,
             url.scheme() == QLatin1String("trash") ? tr("Restore this item from the Trash to open it.")
                                                    : tr("Files opens only files on this computer."));
        return;
    }
    const QFileInfo info(url.toLocalFile());
    if (!info.exists()) {
        Q_EMIT failed(OpOpen, tr("“%1” no longer exists.").arg(name));
        return;
    }
    if (info.isDir()) {
        Q_EMIT failed(OpOpen, tr("“%1” is a folder.").arg(name));
        return;
    }

    const QMimeType mime = QMimeDatabase().mimeTypeForFile(info);
    if (isProgram(mime)) {
        Q_EMIT failed(OpOpen, tr("“%1” is a program. Files does not start programs.").arg(name));
        return;
    }
    // Scripts and desktop entries can run commands, so they are opened as text.
    const bool asText = isScript(mime) || mime.inherits(QStringLiteral("application/x-desktop"));
    const QString openAs = asText ? QStringLiteral("text/plain") : mime.name();
    const KService::Ptr service = KApplicationTrader::preferredService(openAs);
    // OpenUrlJob treats these wrappers like "no application" and hands the
    // file to QDesktopServices.
    if (!service || service->exec() == QLatin1String("xdg-open") || service->exec() == QLatin1String("kde-open")) {
        Q_EMIT failed(OpOpen, tr("No installed application opens “%1” (%2).").arg(name, mime.comment()));
        return;
    }

    auto *job = new KIO::OpenUrlJob(url, openAs, this);
    job->setRunExecutables(false);
    job->setShowOpenOrExecuteDialog(false);
    start(job, OpOpen, tr("Opening “%1”…").arg(name));
    job->start();
}

void FileOperations::copy(const QList<QUrl> &urls, const QUrl &destination)
{
    transfer(OpCopy, urls, destination, false);
}

void FileOperations::move(const QList<QUrl> &urls, const QUrl &destination)
{
    transfer(OpMove, urls, destination, true);
}

void FileOperations::rename(const QUrl &url, const QString &newName)
{
    const QString name = newName.trimmed();
    const QString error = nameError(name);
    if (!error.isEmpty()) {
        Q_EMIT failed(OpRename, error);
        return;
    }
    if (name == url.fileName()) {
        Q_EMIT finished(OpRename, {url});
        return;
    }
    const QUrl destination = childUrl(url.adjusted(QUrl::RemoveFilename), name);
    // Checked here for a clear message; KIO also refuses (no UI delegate to ask).
    if (destination.isLocalFile() && QFileInfo::exists(destination.toLocalFile())) {
        Q_EMIT failed(OpRename, tr("“%1” already exists.").arg(name));
        return;
    }
    start(KIO::moveAs(url, destination), OpRename, tr("Renaming “%1”…").arg(url.fileName()), {destination});
}

void FileOperations::createFolder(const QUrl &parent, const QString &name)
{
    const QString clean = name.trimmed();
    const QString error = nameError(clean);
    if (!error.isEmpty()) {
        Q_EMIT failed(OpNewFolder, error);
        return;
    }
    const QUrl folder = childUrl(parent, clean);
    start(KIO::mkdir(folder), OpNewFolder, tr("Creating “%1”…").arg(clean), {folder});
}

void FileOperations::moveToTrash(const QList<QUrl> &urls)
{
    if (urls.isEmpty()) {
        return;
    }
    KIO::CopyJob *job = KIO::trash(urls);
    start(job, OpTrash, tr("Moving to the Trash…"));
    collectResults(job, urls);
}

void FileOperations::restoreFromTrash(const QList<QUrl> &trashUrls)
{
    if (trashUrls.isEmpty()) {
        return;
    }
    start(KIO::restoreFromTrash(trashUrls), OpRestore, tr("Restoring…"));
}

void FileOperations::emptyTrash()
{
    start(KIO::emptyTrash(), OpEmptyTrash, tr("Emptying the Trash…"));
}

void FileOperations::deletePermanently(const QList<QUrl> &urls)
{
    if (urls.isEmpty()) {
        return;
    }
    start(KIO::del(urls), OpDelete, tr("Deleting…"));
}

void FileOperations::copyToClipboard(const QList<QUrl> &urls)
{
    setClipboard(urls, false);
}

void FileOperations::cutToClipboard(const QList<QUrl> &urls)
{
    setClipboard(urls, true);
}

void FileOperations::paste(const QUrl &destination)
{
    const QMimeData *data = QGuiApplication::clipboard()->mimeData();
    const QList<QUrl> urls = data ? data->urls() : QList<QUrl>();
    if (urls.isEmpty()) {
        Q_EMIT failed(OpPaste, tr("The clipboard holds no files."));
        return;
    }
    const bool cut = data->data(CutSelectionMime).startsWith('1');
    transfer(OpPaste, urls, destination, cut);
}

void FileOperations::start(KJob *job, const QString &operation, const QString &status, const QList<QUrl> &results)
{
    m_running.insert(job, Running{operation, status, results});
    m_order.append(job);

    connect(job, &KJob::percentChanged, this, [this](KJob *job, unsigned long percent) {
        if (!m_order.isEmpty() && m_order.constLast() == job) {
            setProgress(int(percent));
        }
    });
    connect(job, &KJob::result, this, [this](KJob *job) {
        const Running running = m_running.take(job);
        m_order.removeOne(job);
        setProgress(-1);
        Q_EMIT statusTextChanged();
        if (m_running.isEmpty()) {
            Q_EMIT busyChanged();
        }

        if (job->error() == 0) {
            // What was cut is pasted once, as in Dolphin.
            const auto *copyJob = qobject_cast<KIO::CopyJob *>(job);
            if (running.operation == OpPaste && copyJob && copyJob->operationMode() == KIO::CopyJob::Move) {
                QGuiApplication::clipboard()->clear();
            }
            Q_EMIT finished(running.operation, running.results);
        } else if (job->error() != KIO::ERR_USER_CANCELED) {
            Q_EMIT failed(running.operation, job->errorString());
        }
    });

    setProgress(-1);
    Q_EMIT statusTextChanged();
    if (m_running.size() == 1) {
        Q_EMIT busyChanged();
    }
}

void FileOperations::collectResults(KIO::CopyJob *job, const QList<QUrl> &sources)
{
    // copyingDone also reports every file inside copied folders; only the
    // top-level items are results. For the Trash, "to" is the entry's URL.
    connect(job, &KIO::CopyJob::copyingDone, this, [this, sources](KIO::Job *job, const QUrl &from, const QUrl &to) {
        const auto running = m_running.find(job);
        if (running != m_running.end() && sources.contains(from)) {
            running->results.append(to);
        }
    });
}

void FileOperations::transfer(const QString &operation, const QList<QUrl> &urls, const QUrl &destination, bool moving)
{
    QList<QUrl> sources = urls;
    if (moving) {
        // Moving an item into the folder it is in already does nothing.
        const QUrl target = destination.adjusted(QUrl::StripTrailingSlash);
        sources.removeIf([&target](const QUrl &url) {
            return url.adjusted(QUrl::RemoveFilename | QUrl::StripTrailingSlash) == target;
        });
    }
    if (sources.isEmpty() || !destination.isValid()) {
        Q_EMIT finished(operation, {});
        return;
    }
    KIO::CopyJob *job = moving ? KIO::move(sources, destination) : KIO::copy(sources, destination);
    // A name that is taken gets a free one ("name (1)") instead of a question.
    job->setAutoRename(true);
    start(job, operation, moving ? tr("Moving…") : tr("Copying…"));
    collectResults(job, sources);
}

void FileOperations::setProgress(int progress)
{
    if (progress != m_progress) {
        m_progress = progress;
        Q_EMIT progressChanged();
    }
}

void FileOperations::setClipboard(const QList<QUrl> &urls, bool cut)
{
    auto *data = new QMimeData;
    data->setUrls(urls);
    data->setData(CutSelectionMime, cut ? QByteArrayLiteral("1") : QByteArrayLiteral("0"));
    QGuiApplication::clipboard()->setMimeData(data);
}
