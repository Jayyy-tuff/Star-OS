// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QDBusContext>
#include <QDBusMessage>
#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QTimer>
#include <QVariantList>

class NetworkStatus;

// iwd calls this agent for a Wi-Fi passphrase; the reply is delayed until
// the person types one (NetworkStatus::submitPassphrase) or cancels.
class IwdAgent : public QObject, protected QDBusContext
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "net.connman.iwd.Agent")

public:
    explicit IwdAgent(NetworkStatus *status);

    void answer(const QString &passphrase);
    void cancel();

public Q_SLOTS:
    void Release();
    QString RequestPassphrase(const QDBusObjectPath &network);
    QString RequestPrivateKeyPassphrase(const QDBusObjectPath &network);
    void Cancel(const QString &reason);

private:
    NetworkStatus *m_status;
    QDBusMessage m_pending;
    bool m_hasPending = false;
};

// Where the computer is connected, from systemd-networkd, and Wi-Fi through
// iwd, for the tray and quick settings (M0.5, ADR-0014).
//
// state: "connected" (a routable address), "limited" (a link without a
// route), "connecting", "offline". kind: "wired", "wifi" or "".
class NetworkStatus : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString kind READ kind NOTIFY changed)
    // The Wi-Fi network's name; empty for wired.
    Q_PROPERTY(QString networkName READ networkName NOTIFY changed)
    Q_PROPERTY(bool wifiAvailable READ wifiAvailable NOTIFY wifiChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY wifiChanged)
    Q_PROPERTY(bool scanning READ scanning NOTIFY wifiChanged)
    // {path, name, strength (0..4), secured, connected, known}, strongest first.
    Q_PROPERTY(QVariantList wifiNetworks READ wifiNetworks NOTIFY wifiChanged)
    // Milliseconds between refreshes; 0 stops refreshing.
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)

public:
    struct Link {
        QString name;
        QString type;
        QString operationalState;
        QString administrativeState;
        QString ssid;
    };
    struct Summary {
        QString state = QStringLiteral("offline");
        QString kind;
        QString networkName;
    };

    explicit NetworkStatus(QObject *parent = nullptr);

    QString state() const;
    QString kind() const;
    QString networkName() const;
    bool wifiAvailable() const;
    bool wifiEnabled() const;
    bool scanning() const;
    QVariantList wifiNetworks() const;
    int interval() const;
    void setInterval(int interval);

    // systemd-networkd's Describe() JSON, as a summary.
    static QList<Link> parseLinks(const QByteArray &json);
    static Summary summarize(const QList<Link> &links);
    // iwd reports signal strength in 100 * dBm.
    static int strengthBars(int signal);

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setWifiEnabled(bool enabled);
    Q_INVOKABLE void scan();
    Q_INVOKABLE void connectTo(const QString &networkPath);
    Q_INVOKABLE void disconnectWifi();
    Q_INVOKABLE void submitPassphrase(const QString &passphrase);
    Q_INVOKABLE void cancelPassphrase();

    // For the agent.
    QString networkNameOf(const QString &path) const;
    void requestPassphrase(const QString &networkName);

Q_SIGNALS:
    void changed();
    void wifiChanged();
    void intervalChanged();
    void passphraseRequested(const QString &networkName);
    void passphraseDone();
    void connectFailed(const QString &networkName, const QString &error);

private:
    void readNetworkd();
    void readIwd();
    void readOrderedNetworks();
    void registerAgent();

    Summary m_summary;
    QTimer m_timer;
    bool m_wifiAvailable = false;
    bool m_wifiEnabled = false;
    bool m_scanning = false;
    QString m_devicePath;
    QString m_stationPath;
    QVariantMap m_networks; // path -> {name, secured, connected, known}
    QVariantList m_wifiNetworks;
    IwdAgent *m_agent = nullptr;
    bool m_agentRegistered = false;
};
