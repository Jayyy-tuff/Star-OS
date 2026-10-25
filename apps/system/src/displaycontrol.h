// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QTimer>

class QDBusServiceWatcher;

// Screen brightness through PowerDevil's org.kde.ScreenBrightness and night
// light through KWin, for quick settings (M0.5, ADR-0014). Brightness is
// only available where PowerDevil reports a display with adjustable
// brightness; night light where KWin says it is.
class DisplayControl : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool brightnessAvailable READ brightnessAvailable NOTIFY brightnessChanged)
    // Percent of the display's range.
    Q_PROPERTY(int brightness READ brightness WRITE setBrightness NOTIFY brightnessChanged)
    Q_PROPERTY(bool nightLightAvailable READ nightLightAvailable NOTIFY nightLightChanged)
    Q_PROPERTY(bool nightLight READ nightLight WRITE setNightLight NOTIFY nightLightChanged)

public:
    explicit DisplayControl(QObject *parent = nullptr);

    bool brightnessAvailable() const;
    int brightness() const;
    void setBrightness(int percent);
    bool nightLightAvailable() const;
    bool nightLight() const;
    void setNightLight(bool on);

    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void brightnessChanged();
    void nightLightChanged();

private Q_SLOTS:
    void onBrightnessChanged(const QString &display, int value, const QString &sourceClient, const QString &sourceContext);
    void onNightLightPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated);

private:
    void readBrightness();
    void readNightLight();

    QString m_display;
    int m_value = 0;
    int m_maximum = 0;
    bool m_nightLightAvailable = false;
    bool m_nightLight = false;
    QDBusServiceWatcher *m_watcher = nullptr;
};
