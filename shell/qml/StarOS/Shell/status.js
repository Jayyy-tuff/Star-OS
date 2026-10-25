// SPDX-License-Identifier: GPL-3.0-or-later
.pragma library

// Words for StarOS.System's SystemStatus (or a plain object with the same
// properties): where changes are kept, storage, memory and battery. Used by
// the taskbar's tray and quick settings.

function value(status, name) {
    const v = status ? Number(status[name]) : 0;
    return isFinite(v) ? v : 0;
}

function fraction(part, whole) {
    return whole > 0 ? Math.min(1, Math.max(0, part / whole)) : 0;
}

// Decimal units, as disks are sold: "9.8 GB", "16 GB", "512 MB".
function formatBytes(bytes) {
    const units = ["B", "kB", "MB", "GB", "TB"];
    let v = Math.max(0, bytes);
    let i = 0;
    while (v >= 1000 && i < units.length - 1) {
        v /= 1000;
        i += 1;
    }
    const digits = i === 0 || v >= 100 ? 0 : 1;
    return v.toFixed(digits).replace(/\.0$/, "") + " " + units[i];
}

function storageLine(status) {
    const free = formatBytes(value(status, "storageFree"));
    const total = formatBytes(value(status, "storageTotal"));
    const mode = status ? String(status.storageMode) : "";
    if (mode === "star-storage") {
        return qsTr("Star Storage: %1 free of %2.").arg(free).arg(total);
    }
    if (mode === "live") {
        return qsTr("Live session: changes are lost at shutdown. %1 free of %2.").arg(free).arg(total);
    }
    return qsTr("Storage: %1 free of %2.").arg(free).arg(total);
}

function memoryLine(status) {
    return qsTr("Memory: %1 of %2 in use.")
        .arg(formatBytes(value(status, "memoryTotal") - value(status, "memoryAvailable")))
        .arg(formatBytes(value(status, "memoryTotal")));
}

function batteryLine(status) {
    if (!status || !status.batteryPresent) {
        return "";
    }
    return (status.charging ? qsTr("Battery: %1 %, charging.") : qsTr("Battery: %1 %."))
        .arg(Math.round(value(status, "batteryPercent")));
}

function summary(status) {
    if (!status) {
        return "";
    }
    return [storageLine(status), memoryLine(status), batteryLine(status)].filter(line => line !== "").join(" ");
}

// The network symbol for the tray and quick settings, from StarOS.System's
// NetworkStatus (state, kind, wifiAvailable, wifiEnabled) or a plain object.
function networkSymbol(network) {
    if (!network) {
        return "wired";
    }
    if (network.kind === "wifi" && network.state !== "offline") {
        return "wifi";
    }
    if (network.kind === "wired" && network.state !== "offline") {
        return "wired";
    }
    return network.wifiAvailable ? "wifi-off" : "wired";
}

function networkText(network) {
    if (!network) {
        return "";
    }
    switch (network.state) {
    case "connected":
        return network.kind === "wifi" ? (network.networkName || qsTr("Wi-Fi, connected")) : qsTr("Wired, connected");
    case "limited":
        return qsTr("Connected, no internet");
    case "connecting":
        return qsTr("Connecting…");
    default:
        return network.wifiAvailable && !network.wifiEnabled ? qsTr("Wi-Fi is off") : qsTr("Not connected");
    }
}

// The volume symbol from AudioControl (available, volume, muted).
function volumeSymbol(audio) {
    if (!audio || !audio.available || audio.muted || audio.volume === 0) {
        return "volume-mute";
    }
    return audio.volume < 50 ? "volume-low" : "volume";
}
