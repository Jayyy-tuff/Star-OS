// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>

#include <functional>

// Whether this user has seen the Welcome tour (ADR-0017), kept in
// ~/.config/staros-welcomerc, and opening the apps the tour shows.
class WelcomeState : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool shownBefore READ shownBefore NOTIFY shownBeforeChanged)

public:
    using Launcher = std::function<bool(const QString &desktopId)>;

    explicit WelcomeState(QObject *parent = nullptr);

    bool shownBefore() const;
    static bool shownBefore(const QString &configPath);
    static QString defaultConfigPath();

    // The tour was finished or skipped: it does not open by itself again.
    Q_INVOKABLE void finish();
    Q_INVOKABLE bool open(const QString &desktopId);

    // For tests.
    void setConfigPath(const QString &path);
    void setLauncher(Launcher launcher);

Q_SIGNALS:
    void shownBeforeChanged();
    void opened(const QString &desktopId);

private:
    QString m_configPath;
    Launcher m_launcher;
};
