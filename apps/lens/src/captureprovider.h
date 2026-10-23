// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QImage>
#include <QMutex>
#include <QQuickImageProvider>

// Serves the latest screen capture to QML as image://lens/capture?<serial>.
// LensBackend stores it; the image provider and the backend share it.
class CaptureStore
{
public:
    static void set(const QImage &image);
    static QImage get();

private:
    static QMutex s_mutex;
    static QImage s_image;
};

class CaptureProvider : public QQuickImageProvider
{
public:
    CaptureProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;
};
