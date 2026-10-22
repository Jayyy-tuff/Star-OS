// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "appsmodel.h"
#include "flatpakcli.h"

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QStringList>

// Sun Store's backend: the user's Flatpak installation through the flatpak
// command line (always --user; docs/architecture/m03-glass-files-store-design.md
// section 3). Flathub is added only after the person agrees (enableFlathub).
//
// state: "starting"     asking flatpak for the remotes
//        "needsConsent" Flathub is not set up; the consent page is shown
//        "loading"      first catalogue download
//        "ready"        the catalogue (possibly from an earlier download, see
//                       offline) and the installed apps are listed
//        "offline"      the catalogue could not be downloaded and there is
//                       no earlier copy
//        "error"        flatpak is missing or adding Flathub failed
class Store : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    // The last catalogue download failed; what is shown may be out of date.
    Q_PROPERTY(bool offline READ offline NOTIFY offlineChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    // An operation that changes the installation runs ("enable", "refresh",
    // "install", "remove" or "update"); others wait.
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString operation READ operation NOTIFY busyChanged)
    Q_PROPERTY(QString busyAppId READ busyAppId NOTIFY busyChanged)
    Q_PROPERTY(QString progressText READ progressText NOTIFY progressTextChanged)
    Q_PROPERTY(AppsModel *apps READ apps CONSTANT)

public:
    explicit Store(QObject *parent = nullptr);
    // For tests: the flatpak program, the user installation directory
    // (~/.local/share/flatpak) and the Flathub .flatpakrepo file.
    Store(const QString &program, const QString &dataDir, const QString &flathubRepoFile, QObject *parent = nullptr);

    QString state() const;
    bool offline() const;
    QString errorString() const;
    bool busy() const;
    QString operation() const;
    QString busyAppId() const;
    QString progressText() const;
    AppsModel *apps() const;

    // Flatpak's name for this machine's architecture.
    static QString flatpakArch();

    Q_INVOKABLE void start();
    Q_INVOKABLE void enableFlathub();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE bool install(const QString &appId);
    Q_INVOKABLE bool remove(const QString &appId);
    Q_INVOKABLE bool updateAll();
    Q_INVOKABLE bool open(const QString &appId);
    // Answers with permissionsReady or permissionsFailed.
    Q_INVOKABLE void requestPermissions(const QString &appId);

Q_SIGNALS:
    void stateChanged();
    void offlineChanged();
    void errorStringChanged();
    void busyChanged();
    void progressTextChanged();
    void operationFinished(const QString &operation, const QString &appId);
    void operationFailed(const QString &operation, const QString &appId, const QString &message);
    void permissionsReady(const QString &appId, const QStringList &permissions);
    void permissionsFailed(const QString &appId, const QString &message);

private:
    void setState(const QString &state);
    void setOffline(bool offline);
    void setErrorString(const QString &text);
    void setBusy(const QString &operation, const QString &appId);
    void setProgressText(const QString &text);
    void loadCatalogue();
    // Reloads the installed apps and then the available updates.
    void loadInstalled(std::function<void()> done = {});
    bool change(const QString &operation, const QString &appId, const QStringList &arguments);

    FlatpakCli *m_cli;
    AppsModel *m_apps;
    QString m_dataDir;
    QString m_flathubRepoFile;
    QString m_state = QStringLiteral("starting");
    bool m_offline = false;
    QString m_errorString;
    QString m_operation;
    QString m_busyAppId;
    QString m_progressText;
    int m_loadGeneration = 0;
};
