// SPDX-License-Identifier: GPL-3.0-or-later
#include "displaycontrol.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusServiceWatcher>
#include <QDBusVariant>

#include <KConfigGroup>
#include <KSharedConfig>

#include <algorithm>

namespace
{
const QString BrightnessService = QStringLiteral("org.kde.ScreenBrightness");
const QString BrightnessPath = QStringLiteral("/org/kde/ScreenBrightness");
const QString BrightnessInterface = QStringLiteral("org.kde.ScreenBrightness");
const QString DisplayInterface = QStringLiteral("org.kde.ScreenBrightness.Display");
const QString KWinService = QStringLiteral("org.kde.KWin");
const QString NightLightPath = QStringLiteral("/org/kde/KWin/NightLight");
const QString NightLightInterface = QStringLiteral("org.kde.KWin.NightLight");
const QString PropertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

QDBusMessage getAll(const QString &service, const QString &path, const QString &interface)
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, PropertiesInterface, QStringLiteral("GetAll"));
    message << interface;
    return message;
}
}

DisplayControl::DisplayControl(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        return;
    }
    bus.connect(BrightnessService, BrightnessPath, BrightnessInterface, QStringLiteral("BrightnessChanged"), this,
                SLOT(onBrightnessChanged(QString, int, QString, QString)));
    bus.connect(KWinService, NightLightPath, PropertiesInterface, QStringLiteral("PropertiesChanged"), this,
                SLOT(onNightLightPropertiesChanged(QString, QVariantMap, QStringList)));
    // PowerDevil and KWin may start after the shell, or restart.
    m_watcher = new QDBusServiceWatcher(this);
    m_watcher->setConnection(bus);
    m_watcher->setWatchMode(QDBusServiceWatcher::WatchForRegistration);
    m_watcher->addWatchedService(BrightnessService);
    m_watcher->addWatchedService(KWinService);
    connect(m_watcher, &QDBusServiceWatcher::serviceRegistered, this, &DisplayControl::refresh);
    refresh();
}

bool DisplayControl::brightnessAvailable() const
{
    return !m_display.isEmpty() && m_maximum > 0;
}

int DisplayControl::brightness() const
{
    return m_maximum > 0 ? qRound(100.0 * m_value / m_maximum) : 0;
}

void DisplayControl::setBrightness(int percent)
{
    if (!brightnessAvailable()) {
        return;
    }
    // Never fully dark from here.
    const int value = std::clamp(qRound(std::clamp(percent, 1, 100) * m_maximum / 100.0), 1, m_maximum);
    QDBusMessage message = QDBusMessage::createMethodCall(BrightnessService, BrightnessPath + QLatin1Char('/') + m_display, DisplayInterface,
                                                          QStringLiteral("SetBrightness"));
    message << value << uint(0);
    QDBusConnection::sessionBus().asyncCall(message);
    m_value = value;
    Q_EMIT brightnessChanged();
}

bool DisplayControl::nightLightAvailable() const
{
    return m_nightLightAvailable;
}

bool DisplayControl::nightLight() const
{
    return m_nightLight;
}

// KWin reads [NightColor] in kwinrc again when it changes (its config
// watcher); "Constant" keeps the warm colour on now, whatever the time.
void DisplayControl::setNightLight(bool on)
{
    KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("kwinrc"), KConfig::NoGlobals), QStringLiteral("NightColor"));
    group.writeEntry("Active", on, KConfig::Notify);
    if (on) {
        group.writeEntry("Mode", QStringLiteral("Constant"), KConfig::Notify);
    }
    group.sync();
    m_nightLight = on;
    Q_EMIT nightLightChanged();
    QTimer::singleShot(800, this, &DisplayControl::readNightLight);
}

void DisplayControl::refresh()
{
    readBrightness();
    readNightLight();
}

void DisplayControl::onBrightnessChanged(const QString &display, int value, const QString &sourceClient, const QString &sourceContext)
{
    Q_UNUSED(sourceClient)
    Q_UNUSED(sourceContext)
    if (display == m_display && value != m_value) {
        m_value = value;
        Q_EMIT brightnessChanged();
    }
}

void DisplayControl::onNightLightPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated)
{
    Q_UNUSED(changed)
    Q_UNUSED(invalidated)
    if (interface == NightLightInterface) {
        readNightLight();
    }
}

// The first display PowerDevil lists, the built-in one if there is one.
void DisplayControl::readBrightness()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        return;
    }
    QDBusMessage get = QDBusMessage::createMethodCall(BrightnessService, BrightnessPath, PropertiesInterface, QStringLiteral("Get"));
    get << BrightnessInterface << QStringLiteral("DisplaysDBusNames");
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(get), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<QDBusVariant> reply = *call;
        const QStringList displays = reply.isError() ? QStringList() : reply.value().variant().toStringList();
        if (displays.isEmpty()) {
            if (!m_display.isEmpty() || m_maximum != 0) {
                m_display.clear();
                m_maximum = 0;
                Q_EMIT brightnessChanged();
            }
            return;
        }
        for (const QString &display : displays) {
            auto *displayCall = new QDBusPendingCallWatcher(
                QDBusConnection::sessionBus().asyncCall(getAll(BrightnessService, BrightnessPath + QLatin1Char('/') + display, DisplayInterface)), this);
            connect(displayCall, &QDBusPendingCallWatcher::finished, this, [this, display, first = displays.constFirst()](QDBusPendingCallWatcher *call) {
                call->deleteLater();
                QDBusPendingReply<QVariantMap> reply = *call;
                if (reply.isError()) {
                    return;
                }
                const QVariantMap properties = reply.value();
                const bool internal = properties.value(QStringLiteral("IsInternal")).toBool();
                // The built-in display wins; otherwise the first one listed.
                if (!internal && display != first && !m_display.isEmpty()) {
                    return;
                }
                m_display = display;
                m_maximum = properties.value(QStringLiteral("MaxBrightness")).toInt();
                m_value = properties.value(QStringLiteral("Brightness")).toInt();
                Q_EMIT brightnessChanged();
            });
        }
    });
}

void DisplayControl::readNightLight()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        return;
    }
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(getAll(KWinService, NightLightPath, NightLightInterface)), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<QVariantMap> reply = *call;
        const QVariantMap properties = reply.isError() ? QVariantMap() : reply.value();
        const bool available = properties.value(QStringLiteral("available")).toBool();
        const bool enabled = properties.value(QStringLiteral("enabled")).toBool();
        if (available != m_nightLightAvailable || enabled != m_nightLight) {
            m_nightLightAvailable = available;
            m_nightLight = enabled;
            Q_EMIT nightLightChanged();
        }
    });
}
