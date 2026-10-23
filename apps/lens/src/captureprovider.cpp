// SPDX-License-Identifier: GPL-3.0-or-later
#include "captureprovider.h"

QMutex CaptureStore::s_mutex;
QImage CaptureStore::s_image;

void CaptureStore::set(const QImage &image)
{
    QMutexLocker locker(&s_mutex);
    s_image = image;
}

QImage CaptureStore::get()
{
    QMutexLocker locker(&s_mutex);
    return s_image;
}

CaptureProvider::CaptureProvider()
    : QQuickImageProvider(QQuickImageProvider::Image)
{
}

QImage CaptureProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    Q_UNUSED(id)
    QImage image = CaptureStore::get();
    if (size) {
        *size = image.size();
    }
    if (!image.isNull() && requestedSize.isValid() && !requestedSize.isEmpty()) {
        image = image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    return image;
}
