// SPDX-License-Identifier: GPL-3.0-or-later
#include "lensbackend.h"

#include "captureprovider.h"

#include <KIO/OpenUrlJob>
#include <KSystemClipboard>

#include <QClipboard>
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusUnixFileDescriptor>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFutureWatcher>
#include <QStandardPaths>
#include <QUrlQuery>
#include <QtConcurrent>

#include <fcntl.h>
#include <unistd.h>

namespace
{
// Reads KWin's raw image from the pipe until KWin closes it.
QImage readCapture(int fd, const QVariantMap &meta)
{
    QFile pipe;
    if (!pipe.open(fd, QIODevice::ReadOnly, QFileDevice::AutoCloseHandle)) {
        ::close(fd);
        return {};
    }
    const QByteArray data = pipe.readAll();
    if (meta.value(QStringLiteral("type")).toString() != QLatin1String("raw")) {
        return {};
    }
    const int width = meta.value(QStringLiteral("width")).toInt();
    const int height = meta.value(QStringLiteral("height")).toInt();
    const qsizetype stride = meta.value(QStringLiteral("stride")).toLongLong();
    const auto format = QImage::Format(meta.value(QStringLiteral("format")).toInt());
    if (width <= 0 || height <= 0 || stride <= 0 || data.size() < stride * height || format <= QImage::Format_Invalid
        || format >= QImage::NImageFormats) {
        return {};
    }
    const QImage view(reinterpret_cast<const uchar *>(data.constData()), width, height, stride, format);
    QImage image = view.copy();
    image.setDevicePixelRatio(meta.value(QStringLiteral("scale"), 1.0).toDouble());
    return image;
}

void openWithKio(const QUrl &url)
{
    auto *job = new KIO::OpenUrlJob(url);
    job->start();
}
}

LensBackend::LensBackend(QObject *parent)
    : QObject(parent)
    , m_picturesDir(QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + QStringLiteral("/Star Lens"))
    , m_opener(&openWithKio)
{
}

QString LensBackend::state() const
{
    return m_state;
}

QString LensBackend::errorString() const
{
    return m_errorString;
}

QUrl LensBackend::captureUrl() const
{
    if (m_capture.isNull()) {
        return {};
    }
    return QUrl(QStringLiteral("image://lens/capture?%1").arg(m_serial));
}

QSize LensBackend::captureSize() const
{
    return (m_capture.deviceIndependentSize()).toSize();
}

QRect LensBackend::selection() const
{
    return m_selection;
}

QString LensBackend::text() const
{
    return m_result.text;
}

QString LensBackend::code() const
{
    return m_result.code;
}

QString LensBackend::codeFormat() const
{
    return m_result.codeFormat;
}

QStringList LensBackend::links() const
{
    return m_result.links;
}

QString LensBackend::recognitionError() const
{
    return m_result.error;
}

QString LensBackend::message() const
{
    return m_message;
}

void LensBackend::setCapture(const QImage &image)
{
    m_capture = image;
    m_serial += 1;
    CaptureStore::set(image);
    Q_EMIT captureChanged();
    if (image.isNull()) {
        captureFailed(tr("The screenshot was empty."));
    } else {
        setState(QStringLiteral("selecting"));
    }
}

void LensBackend::setTesseract(const QString &program)
{
    m_tesseract = program;
}

void LensBackend::setOpener(Opener opener)
{
    m_opener = std::move(opener);
}

void LensBackend::setPicturesDir(const QString &dir)
{
    m_picturesDir = dir;
}

QImage LensBackend::selectedImage() const
{
    return m_selected;
}

void LensBackend::setState(const QString &state, const QString &error)
{
    if (state == m_state && error == m_errorString) {
        return;
    }
    m_state = state;
    m_errorString = error;
    Q_EMIT stateChanged();
}

void LensBackend::setMessage(const QString &message)
{
    m_message = message;
    Q_EMIT messageChanged();
}

void LensBackend::captureFailed(const QString &error)
{
    setState(QStringLiteral("error"), tr("Star Lens could not take a screenshot: %1").arg(error));
}

QRect LensBackend::toPixels(const QRectF &logical, const QImage &capture)
{
    const qreal scale = capture.devicePixelRatio() > 0 ? capture.devicePixelRatio() : 1;
    const QRectF pixels(logical.x() * scale, logical.y() * scale, logical.width() * scale, logical.height() * scale);
    return pixels.toAlignedRect().intersected(capture.rect());
}

void LensBackend::capture()
{
    setState(QStringLiteral("capturing"));
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) {
        captureFailed(tr("no pipe for the image."));
        return;
    }
    QDBusPendingCall call = [&] {
        QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin.ScreenShot2"),
                                                              QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                                              QStringLiteral("org.kde.KWin.ScreenShot2"),
                                                              QStringLiteral("CaptureActiveScreen"));
        const QVariantMap options{{QStringLiteral("include-cursor"), false}, {QStringLiteral("native-resolution"), true}};
        message << options << QVariant::fromValue(QDBusUnixFileDescriptor(fds[1]));
        return QDBusConnection::sessionBus().asyncCall(message, 15000);
    }();
    // Only KWin's copy of the write end may stay open, so reading ends.
    ::close(fds[1]);
    const int readFd = fds[0];

    auto *watcher = new QDBusPendingCallWatcher(call, this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, readFd](QDBusPendingCallWatcher *self) {
        self->deleteLater();
        const QDBusPendingReply<QVariantMap> reply = *self;
        if (reply.isError()) {
            ::close(readFd);
            captureFailed(reply.error().message());
            return;
        }
        const QVariantMap meta = reply.value();
        auto *reader = new QFutureWatcher<QImage>(this);
        connect(reader, &QFutureWatcher<QImage>::finished, this, [this, reader] {
            reader->deleteLater();
            const QImage image = reader->result();
            if (image.isNull()) {
                captureFailed(tr("KWin sent no usable image."));
            } else {
                setCapture(image);
            }
        });
        reader->setFuture(QtConcurrent::run(readCapture, readFd, meta));
    });
}

void LensBackend::select(qreal x, qreal y, qreal width, qreal height)
{
    if (m_capture.isNull() || m_state == QLatin1String("recognizing")) {
        return;
    }
    const QRect pixels = toPixels(QRectF(x, y, width, height), m_capture);
    if (pixels.width() < 4 || pixels.height() < 4) {
        return;
    }
    m_selection = QRectF(x, y, width, height).toAlignedRect();
    m_selected = m_capture.copy(pixels);
    m_selected.setDevicePixelRatio(1);
    setMessage(QString());
    setState(QStringLiteral("recognizing"));

    auto *watcher = new QFutureWatcher<Recognizer::Result>(this);
    connect(watcher, &QFutureWatcher<Recognizer::Result>::finished, this, [this, watcher] {
        watcher->deleteLater();
        m_result = watcher->result();
        Q_EMIT resultsChanged();
        setState(QStringLiteral("results"));
    });
    watcher->setFuture(QtConcurrent::run(&Recognizer::recognize, m_selected, m_tesseract));
}

void LensBackend::selectAgain()
{
    if (!m_capture.isNull() && m_state != QLatin1String("recognizing")) {
        setMessage(QString());
        setState(QStringLiteral("selecting"));
    }
}

void LensBackend::copy(QMimeData *data, const QString &message)
{
    if (auto *clipboard = KSystemClipboard::instance()) {
        clipboard->setMimeData(data, QClipboard::Clipboard);
        setMessage(message);
    } else {
        delete data;
    }
}

void LensBackend::copyText(const QString &part)
{
    auto *data = new QMimeData;
    data->setText(part.isEmpty() ? m_result.text : part);
    copy(data, tr("Text copied."));
}

void LensBackend::copyCode()
{
    auto *data = new QMimeData;
    data->setText(m_result.code);
    copy(data, tr("Code copied."));
}

void LensBackend::copyImage()
{
    auto *data = new QMimeData;
    data->setImageData(QVariant::fromValue(m_selected));
    copy(data, tr("Image copied."));
}

QString LensBackend::saveImage()
{
    if (m_selected.isNull() || !QDir().mkpath(m_picturesDir)) {
        setMessage(tr("The image could not be saved."));
        return {};
    }
    const QString name = QStringLiteral("Star Lens %1.png").arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd HH-mm-ss-zzz")));
    const QString path = QDir(m_picturesDir).filePath(name);
    if (!m_selected.save(path, "PNG")) {
        setMessage(tr("The image could not be saved."));
        return {};
    }
    setMessage(tr("Saved to %1").arg(path));
    return path;
}

void LensBackend::searchWeb()
{
    const QString query = m_result.text.isEmpty() ? m_result.code : m_result.text;
    if (query.trimmed().isEmpty()) {
        setMessage(tr("There is no text to search for."));
        return;
    }
    QUrl url(QStringLiteral("https://www.google.com/search"));
    QUrlQuery items;
    items.addQueryItem(QStringLiteral("q"), query.simplified().left(500));
    url.setQuery(items);
    m_opener(url);
    setMessage(tr("Opened the search in your browser."));
}

bool LensBackend::openLink(const QString &link)
{
    // Only links the recognition found, and only web addresses.
    const QUrl url(link, QUrl::StrictMode);
    if (!m_result.links.contains(link) || !url.isValid()
        || (url.scheme() != QLatin1String("https") && url.scheme() != QLatin1String("http"))) {
        return false;
    }
    m_opener(url);
    setMessage(tr("Opened %1 in your browser.").arg(link));
    return true;
}

void LensBackend::openGoogleLens()
{
    if (m_selected.isNull()) {
        return;
    }
    auto *data = new QMimeData;
    data->setImageData(QVariant::fromValue(m_selected));
    copy(data, QString());
    const QString path = saveImage();
    m_opener(QUrl(QStringLiteral("https://lens.google.com/")));
    setMessage(path.isEmpty() ? tr("Google Lens opened in your browser. Paste the image there (Ctrl+V).")
                              : tr("Google Lens opened in your browser. Paste the image there (Ctrl+V), or upload %1.").arg(path));
}

void LensBackend::quit()
{
    auto *clipboard = KSystemClipboard::instance();
    if (!clipboard || !clipboard->ownsClipboard()) {
        QCoreApplication::quit();
        return;
    }
    connect(clipboard, &KSystemClipboard::changed, this, [clipboard](QClipboard::Mode mode) {
        if (mode == QClipboard::Clipboard && !clipboard->ownsClipboard()) {
            QCoreApplication::quit();
        }
    });
}
