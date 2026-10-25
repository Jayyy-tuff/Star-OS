// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QList>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QString>

class QAction;

namespace PulseAudioQt
{
class Sink;
}

// The default output's volume and mute through PulseAudioQt (PipeWire's Pulse
// server) for quick settings (M0.5, ADR-0014). With keysEnabled the volume
// keys change it and plasmashell's on-screen display shows the level.
class AudioControl : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // False while there is no output device (or no sound server).
    Q_PROPERTY(bool available READ available NOTIFY changed)
    // Percent of the normal volume, 0..100.
    Q_PROPERTY(int volume READ volume WRITE setVolume NOTIFY changed)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY changed)
    Q_PROPERTY(QString deviceName READ deviceName NOTIFY changed)
    Q_PROPERTY(bool keysEnabled READ keysEnabled WRITE setKeysEnabled NOTIFY keysEnabledChanged)

public:
    explicit AudioControl(QObject *parent = nullptr);

    bool available() const;
    int volume() const;
    void setVolume(int percent);
    bool muted() const;
    void setMuted(bool muted);
    QString deviceName() const;
    bool keysEnabled() const;
    void setKeysEnabled(bool enabled);

    Q_INVOKABLE void raise();
    Q_INVOKABLE void lower();
    Q_INVOKABLE void toggleMute();

    static constexpr int Step = 5;

Q_SIGNALS:
    void changed();
    void keysEnabledChanged();

private:
    void setSink(PulseAudioQt::Sink *sink);
    void showLevel();

    QPointer<PulseAudioQt::Sink> m_sink;
    QList<QAction *> m_actions;
    bool m_keysEnabled = false;
};
