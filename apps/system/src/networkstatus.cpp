// SPDX-License-Identifier: GPL-3.0-or-later
#include "networkstatus.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMetaType>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <algorithm>

namespace
{
const QString NetworkdService = QStringLiteral("org.freedesktop.network1");
const QString NetworkdPath = QStringLiteral("/org/freedesktop/network1");
const QString NetworkdManager = QStringLiteral("org.freedesktop.network1.Manager");
const QString IwdService = QStringLiteral("net.connman.iwd");
const QString IwdDevice = QStringLiteral("net.connman.iwd.Device");
const QString IwdStation = QStringLiteral("net.connman.iwd.Station");
const QString IwdNetwork = QStringLiteral("net.connman.iwd.Network");
const QString AgentPath = QStringLiteral("/org/staros/IwdAgent");

using InterfaceMap = QMap<QString, QVariantMap>;
using ObjectMap = QMap<QDBusObjectPath, InterfaceMap>;
using OrderedNetwork = std::pair<QDBusObjectPath, qint16>;
}

Q_DECLARE_METATYPE(InterfaceMap)
Q_DECLARE_METATYPE(ObjectMap)

const QDBusArgument &operator>>(const QDBusArgument &argument, OrderedNetwork &network)
{
    argument.beginStructure();
    argument >> network.first >> network.second;
    argument.endStructure();
    return argument;
}

QDBusArgument &operator<<(QDBusArgument &argument, const OrderedNetwork &network)
{
    argument.beginStructure();
    argument << network.first << network.second;
    argument.endStructure();
    return argument;
}

Q_DECLARE_METATYPE(OrderedNetwork)
Q_DECLARE_METATYPE(QList<OrderedNetwork>)

IwdAgent::IwdAgent(NetworkStatus *status)
    : QObject(status)
    , m_status(status)
{
}

void IwdAgent::answer(const QString &passphrase)
{
    if (!m_hasPending) {
        return;
    }
    m_hasPending = false;
    QDBusConnection::systemBus().send(m_pending.createReply(passphrase));
}

void IwdAgent::cancel()
{
    if (!m_hasPending) {
        return;
    }
    m_hasPending = false;
    QDBusConnection::systemBus().send(
        m_pending.createErrorReply(QStringLiteral("net.connman.iwd.Agent.Error.Canceled"), QStringLiteral("Canceled by the person")));
}

void IwdAgent::Release()
{
    cancel();
}

QString IwdAgent::RequestPassphrase(const QDBusObjectPath &network)
{
    cancel();
    setDelayedReply(true);
    m_pending = message();
    m_hasPending = true;
    m_status->requestPassphrase(m_status->networkNameOf(network.path()));
    return {};
}

QString IwdAgent::RequestPrivateKeyPassphrase(const QDBusObjectPath &network)
{
    return RequestPassphrase(network);
}

void IwdAgent::Cancel(const QString &reason)
{
    Q_UNUSED(reason)
    m_hasPending = false;
    Q_EMIT m_status->passphraseDone();
}

NetworkStatus::NetworkStatus(QObject *parent)
    : QObject(parent)
{
    qDBusRegisterMetaType<InterfaceMap>();
    qDBusRegisterMetaType<ObjectMap>();
    qDBusRegisterMetaType<OrderedNetwork>();
    qDBusRegisterMetaType<QList<OrderedNetwork>>();
    m_timer.setInterval(5000);
    connect(&m_timer, &QTimer::timeout, this, &NetworkStatus::refresh);
    m_timer.start();
    refresh();
}

QString NetworkStatus::state() const
{
    return m_summary.state;
}

QString NetworkStatus::kind() const
{
    return m_summary.kind;
}

QString NetworkStatus::networkName() const
{
    return m_summary.networkName;
}

bool NetworkStatus::wifiAvailable() const
{
    return m_wifiAvailable;
}

bool NetworkStatus::wifiEnabled() const
{
    return m_wifiEnabled;
}

bool NetworkStatus::scanning() const
{
    return m_scanning;
}

QVariantList NetworkStatus::wifiNetworks() const
{
    return m_wifiNetworks;
}

int NetworkStatus::interval() const
{
    return m_timer.isActive() ? m_timer.interval() : 0;
}

void NetworkStatus::setInterval(int interval)
{
    if (interval == this->interval()) {
        return;
    }
    if (interval > 0) {
        m_timer.start(interval);
    } else {
        m_timer.stop();
    }
    Q_EMIT intervalChanged();
}

QList<NetworkStatus::Link> NetworkStatus::parseLinks(const QByteArray &json)
{
    QList<Link> links;
    const QJsonArray interfaces = QJsonDocument::fromJson(json).object().value(QLatin1String("Interfaces")).toArray();
    for (const QJsonValue &value : interfaces) {
        const QJsonObject object = value.toObject();
        Link link;
        link.name = object.value(QLatin1String("Name")).toString();
        link.type = object.value(QLatin1String("Type")).toString();
        link.operationalState = object.value(QLatin1String("OperationalState")).toString();
        link.administrativeState = object.value(QLatin1String("AdministrativeState")).toString();
        link.ssid = object.value(QLatin1String("SSID")).toString();
        links.append(link);
    }
    return links;
}

// The best link wins: routable, then a link with carrier, then one being
// configured; loopback and links networkd leaves alone are skipped.
NetworkStatus::Summary NetworkStatus::summarize(const QList<Link> &links)
{
    auto score = [](const Link &link) {
        if (link.operationalState == QLatin1String("routable")) {
            return 3;
        }
        if (link.administrativeState == QLatin1String("configuring")) {
            return 2;
        }
        if (link.operationalState == QLatin1String("degraded") || link.operationalState == QLatin1String("carrier")) {
            return 1;
        }
        return 0;
    };
    const Link *best = nullptr;
    for (const Link &link : links) {
        if (link.type == QLatin1String("loopback") || link.administrativeState == QLatin1String("unmanaged")) {
            continue;
        }
        if (score(link) > 0 && (!best || score(link) > score(*best))) {
            best = &link;
        }
    }
    Summary summary;
    if (!best) {
        return summary;
    }
    const int s = score(*best);
    summary.state = s == 3 ? QStringLiteral("connected") : s == 2 ? QStringLiteral("connecting") : QStringLiteral("limited");
    const bool wifi = best->type == QLatin1String("wlan");
    summary.kind = wifi ? QStringLiteral("wifi") : QStringLiteral("wired");
    summary.networkName = wifi ? best->ssid : QString();
    return summary;
}

int NetworkStatus::strengthBars(int signal)
{
    // -50 dBm or better: 4 bars; -80 dBm or worse: 1.
    const int dbm = signal / 100;
    return std::clamp((dbm + 90) / 10, 1, 4);
}

void NetworkStatus::refresh()
{
    readNetworkd();
    readIwd();
}

void NetworkStatus::readNetworkd()
{
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        return;
    }
    QDBusMessage message = QDBusMessage::createMethodCall(NetworkdService, NetworkdPath, NetworkdManager, QStringLiteral("Describe"));
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<QString> reply = *call;
        const Summary summary = reply.isError() ? Summary() : summarize(parseLinks(reply.value().toUtf8()));
        if (summary.state != m_summary.state || summary.kind != m_summary.kind || summary.networkName != m_summary.networkName) {
            m_summary = summary;
            Q_EMIT changed();
        }
    });
}

// The first station device iwd manages, and the networks it knows of.
void NetworkStatus::readIwd()
{
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!bus.isConnected()) {
        return;
    }
    QDBusMessage message = QDBusMessage::createMethodCall(IwdService, QStringLiteral("/"), QStringLiteral("org.freedesktop.DBus.ObjectManager"),
                                                          QStringLiteral("GetManagedObjects"));
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<ObjectMap> reply = *call;
        QString devicePath;
        QString stationPath;
        bool powered = false;
        bool scanning = false;
        QVariantMap networks;
        if (!reply.isError()) {
            const ObjectMap objects = reply.value();
            for (auto it = objects.cbegin(); it != objects.cend(); ++it) {
                const QString path = it.key().path();
                const InterfaceMap &interfaces = it.value();
                if (interfaces.contains(IwdDevice) && devicePath.isEmpty()
                    && interfaces.value(IwdDevice).value(QStringLiteral("Mode")).toString() == QLatin1String("station")) {
                    devicePath = path;
                    powered = interfaces.value(IwdDevice).value(QStringLiteral("Powered")).toBool();
                    if (interfaces.contains(IwdStation)) {
                        stationPath = path;
                        scanning = interfaces.value(IwdStation).value(QStringLiteral("Scanning")).toBool();
                    }
                }
                if (interfaces.contains(IwdNetwork)) {
                    const QVariantMap network = interfaces.value(IwdNetwork);
                    networks.insert(path,
                                    QVariantMap{
                                        {QStringLiteral("device"), network.value(QStringLiteral("Device")).value<QDBusObjectPath>().path()},
                                        {QStringLiteral("name"), network.value(QStringLiteral("Name")).toString()},
                                        {QStringLiteral("secured"), network.value(QStringLiteral("Type")).toString() != QLatin1String("open")},
                                        {QStringLiteral("connected"), network.value(QStringLiteral("Connected")).toBool()},
                                        {QStringLiteral("known"), network.contains(QStringLiteral("KnownNetwork"))},
                                    });
                }
            }
        }
        const bool available = !devicePath.isEmpty();
        const bool changedState = available != m_wifiAvailable || powered != m_wifiEnabled || scanning != m_scanning || devicePath != m_devicePath
            || networks != m_networks;
        m_wifiAvailable = available;
        m_wifiEnabled = powered;
        m_scanning = scanning;
        m_devicePath = devicePath;
        m_stationPath = stationPath;
        m_networks = networks;
        if (available) {
            registerAgent();
        }
        if (!m_stationPath.isEmpty()) {
            readOrderedNetworks();
        } else if (!m_wifiNetworks.isEmpty()) {
            m_wifiNetworks.clear();
            Q_EMIT wifiChanged();
            return;
        }
        if (changedState) {
            Q_EMIT wifiChanged();
        }
    });
}

void NetworkStatus::readOrderedNetworks()
{
    QDBusMessage message = QDBusMessage::createMethodCall(IwdService, m_stationPath, IwdStation, QStringLiteral("GetOrderedNetworks"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<QList<OrderedNetwork>> reply = *call;
        QVariantList list;
        if (!reply.isError()) {
            const QList<OrderedNetwork> ordered = reply.value();
            for (const OrderedNetwork &item : ordered) {
                QVariantMap network = m_networks.value(item.first.path()).toMap();
                if (network.isEmpty()) {
                    continue;
                }
                network.insert(QStringLiteral("path"), item.first.path());
                network.insert(QStringLiteral("strength"), strengthBars(item.second));
                list.append(network);
            }
        }
        if (list != m_wifiNetworks) {
            m_wifiNetworks = list;
            Q_EMIT wifiChanged();
        }
    });
}

void NetworkStatus::registerAgent()
{
    if (m_agentRegistered) {
        return;
    }
    QDBusConnection bus = QDBusConnection::systemBus();
    if (!m_agent) {
        m_agent = new IwdAgent(this);
        if (!bus.registerObject(AgentPath, m_agent, QDBusConnection::ExportAllSlots)) {
            return;
        }
    }
    QDBusMessage message = QDBusMessage::createMethodCall(IwdService, QStringLiteral("/net/connman/iwd"), QStringLiteral("net.connman.iwd.AgentManager"),
                                                          QStringLiteral("RegisterAgent"));
    message << QVariant::fromValue(QDBusObjectPath(AgentPath));
    auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<> reply = *call;
        // "AlreadyExists" means it is registered.
        m_agentRegistered = !reply.isError() || reply.error().name().endsWith(QLatin1String("AlreadyExists"));
    });
}

void NetworkStatus::setWifiEnabled(bool enabled)
{
    if (m_devicePath.isEmpty()) {
        return;
    }
    QDBusMessage message =
        QDBusMessage::createMethodCall(IwdService, m_devicePath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
    message << IwdDevice << QStringLiteral("Powered") << QVariant::fromValue(QDBusVariant(enabled));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        readIwd();
    });
}

void NetworkStatus::scan()
{
    if (m_stationPath.isEmpty()) {
        return;
    }
    QDBusMessage message = QDBusMessage::createMethodCall(IwdService, m_stationPath, IwdStation, QStringLiteral("Scan"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        // Results arrive over a few seconds.
        readIwd();
        QTimer::singleShot(3000, this, &NetworkStatus::readIwd);
    });
}

void NetworkStatus::connectTo(const QString &networkPath)
{
    if (!m_networks.contains(networkPath)) {
        return;
    }
    const QString name = networkNameOf(networkPath);
    QDBusMessage message = QDBusMessage::createMethodCall(IwdService, networkPath, IwdNetwork, QStringLiteral("Connect"));
    // iwd answers when the connection is made or failed; asking for the
    // passphrase can take as long as the person types.
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message, 300000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, name](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        QDBusPendingReply<> reply = *call;
        if (reply.isError() && !reply.error().name().endsWith(QLatin1String("Aborted"))) {
            Q_EMIT connectFailed(name, reply.error().message());
        }
        Q_EMIT passphraseDone();
        refresh();
    });
}

void NetworkStatus::disconnectWifi()
{
    if (m_stationPath.isEmpty()) {
        return;
    }
    QDBusMessage message = QDBusMessage::createMethodCall(IwdService, m_stationPath, IwdStation, QStringLiteral("Disconnect"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this](QDBusPendingCallWatcher *call) {
        call->deleteLater();
        refresh();
    });
}

void NetworkStatus::submitPassphrase(const QString &passphrase)
{
    if (m_agent) {
        m_agent->answer(passphrase);
    }
}

void NetworkStatus::cancelPassphrase()
{
    if (m_agent) {
        m_agent->cancel();
    }
    Q_EMIT passphraseDone();
}

QString NetworkStatus::networkNameOf(const QString &path) const
{
    return m_networks.value(path).toMap().value(QStringLiteral("name")).toString();
}

void NetworkStatus::requestPassphrase(const QString &networkName)
{
    Q_EMIT passphraseRequested(networkName);
}
