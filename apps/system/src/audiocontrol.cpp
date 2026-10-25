// SPDX-License-Identifier: GPL-3.0-or-later
#include "audiocontrol.h"

#include <QAction>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QKeySequence>

#include <KGlobalAccel>
#include <PulseAudioQt/Context>
#include <PulseAudioQt/Server>
#include <PulseAudioQt/Sink>

#include <algorithm>

namespace
{
// PA_VOLUME_NORM: 100 %.
constexpr qint64 NormalVolume = 65536;
}

AudioControl::AudioControl(QObject *parent)
    : QObject(parent)
{
    auto *context = PulseAudioQt::Context::instance();
    if (context && context->server()) {
        connect(context->server(), &PulseAudioQt::Server::defaultSinkChanged, this, &AudioControl::setSink);
        setSink(context->server()->defaultSink());
    }
}

bool AudioControl::available() const
{
    return m_sink != nullptr;
}

int AudioControl::volume() const
{
    if (!m_sink) {
        return 0;
    }
    return int(std::clamp<qint64>((m_sink->volume() * 100 + NormalVolume / 2) / NormalVolume, 0, 100));
}

void AudioControl::setVolume(int percent)
{
    if (!m_sink) {
        return;
    }
    const int clamped = std::clamp(percent, 0, 100);
    m_sink->setVolume(qint64(clamped) * NormalVolume / 100);
    if (clamped > 0 && m_sink->isMuted()) {
        m_sink->setMuted(false);
    }
}

bool AudioControl::muted() const
{
    return m_sink && m_sink->isMuted();
}

void AudioControl::setMuted(bool muted)
{
    if (m_sink) {
        m_sink->setMuted(muted);
    }
}

QString AudioControl::deviceName() const
{
    return m_sink ? m_sink->description() : QString();
}

bool AudioControl::keysEnabled() const
{
    return m_keysEnabled;
}

// The volume keys, registered with KGlobalAccel under the Star OS shell.
void AudioControl::setKeysEnabled(bool enabled)
{
    if (enabled == m_keysEnabled) {
        return;
    }
    m_keysEnabled = enabled;
    if (enabled && m_actions.isEmpty()) {
        struct Key {
            const char *name;
            QString text;
            Qt::Key key;
            void (AudioControl::*slot)();
        };
        const Key keys[] = {
            {"increase_volume", tr("Increase Volume"), Qt::Key_VolumeUp, &AudioControl::raise},
            {"decrease_volume", tr("Decrease Volume"), Qt::Key_VolumeDown, &AudioControl::lower},
            {"mute", tr("Mute"), Qt::Key_VolumeMute, &AudioControl::toggleMute},
        };
        for (const Key &key : keys) {
            auto *action = new QAction(key.text, this);
            action->setObjectName(QString::fromLatin1(key.name));
            action->setProperty("componentName", QStringLiteral("staros-shell"));
            action->setProperty("componentDisplayName", tr("Star OS shell"));
            KGlobalAccel::setGlobalShortcut(action, QKeySequence(key.key));
            connect(action, &QAction::triggered, this, key.slot);
            m_actions.append(action);
        }
    }
    for (QAction *action : std::as_const(m_actions)) {
        action->setEnabled(enabled);
    }
    Q_EMIT keysEnabledChanged();
}

void AudioControl::raise()
{
    setVolume(volume() + Step);
    showLevel();
}

void AudioControl::lower()
{
    setVolume(volume() - Step);
    showLevel();
}

void AudioControl::toggleMute()
{
    setMuted(!muted());
    showLevel();
}

void AudioControl::setSink(PulseAudioQt::Sink *sink)
{
    if (m_sink == sink) {
        return;
    }
    if (m_sink) {
        disconnect(m_sink, nullptr, this, nullptr);
    }
    m_sink = sink;
    if (m_sink) {
        connect(m_sink, &PulseAudioQt::Sink::volumeChanged, this, &AudioControl::changed);
        connect(m_sink, &PulseAudioQt::Sink::mutedChanged, this, &AudioControl::changed);
    }
    Q_EMIT changed();
}

// plasmashell's on-screen display (org.kde.osdService), as Plasma's own
// volume control uses it; the call is asynchronous.
void AudioControl::showLevel()
{
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/org/kde/osdService"),
                                                          QStringLiteral("org.kde.osdService"), QStringLiteral("volumeChanged"));
    message << (muted() ? 0 : volume()) << 100;
    QDBusConnection::sessionBus().asyncCall(message);
}
