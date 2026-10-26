// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QHash>
#include <QList>
#include <QQmlEngine>
#include <QString>
#include <QStringList>
#include <QTimer>

#include <functional>

// Game Center's library (M0.5, ADR-0017): the games among the installed apps
// (desktop entries whose Categories hold Game, emulators marked) and Steam's
// installed games, sorted by name and filtered by kind and search text.
// Starting a game goes through its desktop entry or steam://rungameid/<id>;
// with game mode on, desktop-entry games start through gamemoderun and
// notifications are held back while they run.
class GameLibrary : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(int totalCount READ totalCount NOTIFY countChanged)
    // "all", "steam", "apps" or "emulators".
    Q_PROPERTY(QString filter READ filter WRITE setFilter NOTIFY filterChanged)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    // The Steam client's desktop id when Steam is installed, else empty.
    Q_PROPERTY(QString steamDesktopId READ steamDesktopId NOTIFY countChanged)
    Q_PROPERTY(bool gameModeAvailable READ gameModeAvailable CONSTANT)
    Q_PROPERTY(bool gameMode READ gameMode WRITE setGameMode NOTIFY gameModeChanged)
    Q_PROPERTY(int running READ running NOTIFY runningChanged)

public:
    enum Role {
        NameRole = Qt::UserRole + 1,
        GameIdRole,
        SourceRole,
        EmulatorRole,
        IconRole,
        LastPlayedRole,
    };
    Q_ENUM(Role)

    struct Entry {
        QString name;
        QString gameId; // a desktop id, or "steam:<appid>"
        QString source; // "steam", "flatpak" or "app"
        bool emulator = false;
        QString icon; // a theme icon name or an absolute file path
        QDateTime lastPlayed;
    };
    // How a game is started: kind "desktop" (target: a desktop id), "url"
    // (target: steam://rungameid/<id>) or "command" (target: a program and
    // its arguments, separated by spaces); false when it cannot be started.
    using Launcher = std::function<bool(const QString &kind, const QString &target, bool gameMode)>;

    explicit GameLibrary(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int totalCount() const;
    QString filter() const;
    void setFilter(const QString &filter);
    QString search() const;
    void setSearch(const QString &search);
    QString steamDesktopId() const;
    bool gameModeAvailable() const;
    bool gameMode() const;
    void setGameMode(bool on);
    int running() const;

    Q_INVOKABLE void reload();
    Q_INVOKABLE bool launch(int row);
    Q_INVOKABLE bool launchGame(const QString &gameId);
    Q_INVOKABLE QVariantMap get(int row) const;
    // Sun Store on its Games category, and the Steam client.
    Q_INVOKABLE bool getGames();
    Q_INVOKABLE bool openSteam();

    // For tests.
    void setSteamRoots(const QStringList &roots);
    void setLauncher(Launcher launcher);
    void setGameModeAvailable(bool available);
    void setConfigPath(const QString &path);

    static bool matches(const Entry &entry, const QString &filter, const QString &search);

Q_SIGNALS:
    void countChanged();
    void filterChanged();
    void searchChanged();
    void gameModeChanged();
    void runningChanged();
    void launched(const QString &gameId);
    void launchFailed(const QString &name);

private:
    void applyFilter();
    bool defaultLaunch(const QString &kind, const QString &target, bool gameMode);
    void readConfig();
    void watchProcess(qint64 pid);
    void checkProcesses();
    void holdNotifications(bool hold);

    QList<Entry> m_all;
    QList<int> m_rows; // indexes into m_all
    QString m_filter = QStringLiteral("all");
    QString m_search;
    QString m_steamDesktopId;
    QStringList m_steamRoots;
    Launcher m_launcher;
    bool m_gameModeAvailable = false;
    bool m_gameMode = false;
    QString m_configPath;
    QHash<QString, QDateTime> m_played;
    QList<qint64> m_pids;
    QTimer m_processTimer;
    uint m_inhibitCookie = 0;
    bool m_inhibiting = false;
};
