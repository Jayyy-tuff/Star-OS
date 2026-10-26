// SPDX-License-Identifier: GPL-3.0-or-later
#include "themeiconprovider.h"

#include <QIcon>

ThemeIconProvider::ThemeIconProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
{
}

QPixmap ThemeIconProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    const QSize wanted = requestedSize.isValid() && !requestedSize.isEmpty() ? requestedSize : QSize(128, 128);
    const QIcon icon = QIcon::hasThemeIcon(id) ? QIcon::fromTheme(id) : QIcon();
    const QPixmap pixmap = icon.isNull() ? QPixmap() : icon.pixmap(wanted);
    if (size) {
        *size = pixmap.size();
    }
    return pixmap;
}
