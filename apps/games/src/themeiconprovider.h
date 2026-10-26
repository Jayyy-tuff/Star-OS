// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QQuickImageProvider>

// "image://icon/<name>": an icon from the icon theme (games name theirs in
// their desktop entries; Steam installs steam_icon_<appid>). An empty image
// when the theme has none, so the view shows its own artwork instead.
class ThemeIconProvider : public QQuickImageProvider
{
public:
    ThemeIconProvider();
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
};
