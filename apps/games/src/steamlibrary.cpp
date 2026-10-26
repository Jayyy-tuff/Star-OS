// SPDX-License-Identifier: GPL-3.0-or-later
#include "steamlibrary.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSet>

namespace
{
constexpr qint64 MaxFileSize = 4 * 1024 * 1024;

class Tokenizer
{
public:
    explicit Tokenizer(const QByteArray &text)
        : m_text(text)
    {
    }

    // The next token: a string (quoted or bare), "{" or "}"; empty at the end.
    std::optional<QByteArray> next(bool *brace)
    {
        skipSpace();
        *brace = false;
        if (m_pos >= m_text.size()) {
            return std::nullopt;
        }
        const char c = m_text.at(m_pos);
        if (c == '{' || c == '}') {
            ++m_pos;
            *brace = true;
            return QByteArray(1, c);
        }
        QByteArray token;
        if (c == '"') {
            ++m_pos;
            while (m_pos < m_text.size() && m_text.at(m_pos) != '"') {
                char ch = m_text.at(m_pos++);
                if (ch == '\\' && m_pos < m_text.size()) {
                    const char escaped = m_text.at(m_pos++);
                    ch = escaped == 'n' ? '\n' : escaped == 't' ? '\t' : escaped;
                }
                token.append(ch);
            }
            ++m_pos;
            return token;
        }
        while (m_pos < m_text.size()) {
            const char ch = m_text.at(m_pos);
            if (QChar::isSpace(uchar(ch)) || ch == '{' || ch == '}' || ch == '"') {
                break;
            }
            token.append(ch);
            ++m_pos;
        }
        return token;
    }

private:
    void skipSpace()
    {
        while (m_pos < m_text.size()) {
            const char c = m_text.at(m_pos);
            if (QChar::isSpace(uchar(c))) {
                ++m_pos;
            } else if (c == '/' && m_pos + 1 < m_text.size() && m_text.at(m_pos + 1) == '/') {
                while (m_pos < m_text.size() && m_text.at(m_pos) != '\n') {
                    ++m_pos;
                }
            } else {
                break;
            }
        }
    }

    const QByteArray &m_text;
    qsizetype m_pos = 0;
};

QVariantMap parseObject(Tokenizer &tokens, int depth)
{
    QVariantMap map;
    bool brace = false;
    while (true) {
        const std::optional<QByteArray> key = tokens.next(&brace);
        if (!key || (brace && *key == "}")) {
            return map;
        }
        if (brace) {
            continue; // a stray "{"
        }
        const std::optional<QByteArray> value = tokens.next(&brace);
        if (!value) {
            return map;
        }
        const QString name = QString::fromUtf8(*key).toLower();
        if (brace && *value == "{") {
            map.insert(name, depth < 16 ? parseObject(tokens, depth + 1) : QVariantMap());
        } else if (brace) {
            return map; // "}" after a key
        } else {
            map.insert(name, QString::fromUtf8(*value));
        }
    }
}

QByteArray readSmallFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.size() > MaxFileSize) {
        return {};
    }
    return file.readAll();
}
}

namespace SteamLibrary
{
QVariantMap parseKeyValues(const QByteArray &text)
{
    Tokenizer tokens(text);
    return parseObject(tokens, 0);
}

QStringList libraryFolders(const QByteArray &libraryFoldersVdf)
{
    const QVariantMap root = parseKeyValues(libraryFoldersVdf).value(QStringLiteral("libraryfolders")).toMap();
    QStringList folders;
    for (auto it = root.cbegin(); it != root.cend(); ++it) {
        bool numeric = false;
        it.key().toInt(&numeric);
        if (!numeric) {
            continue;
        }
        const QString path = it.value().typeId() == QMetaType::QVariantMap
            ? it.value().toMap().value(QStringLiteral("path")).toString()
            : it.value().toString();
        if (!path.isEmpty() && !folders.contains(path)) {
            folders.append(path);
        }
    }
    return folders;
}

bool isTool(const QString &appId, const QString &name)
{
    static const QSet<QString> tools{
        QStringLiteral("228980"), // Steamworks Common Redistributables
        QStringLiteral("1070560"), // Steam Linux Runtime 1.0 (scout)
        QStringLiteral("1391110"), // Steam Linux Runtime 2.0 (soldier)
        QStringLiteral("1628350"), // Steam Linux Runtime 3.0 (sniper)
    };
    return tools.contains(appId) || name.startsWith(QLatin1String("Proton"))
        || name.startsWith(QLatin1String("Steam Linux Runtime")) || name.startsWith(QLatin1String("Steamworks"));
}

std::optional<Game> parseManifest(const QByteArray &acf)
{
    const QVariantMap state = parseKeyValues(acf).value(QStringLiteral("appstate")).toMap();
    Game game;
    game.appId = state.value(QStringLiteral("appid")).toString();
    game.name = state.value(QStringLiteral("name")).toString();
    bool ok = false;
    const qint64 flags = state.value(QStringLiteral("stateflags")).toString().toLongLong(&ok);
    // StateFlags bit 4: fully installed.
    if (game.appId.isEmpty() || game.name.isEmpty() || !ok || !(flags & 4) || isTool(game.appId, game.name)) {
        return std::nullopt;
    }
    const qint64 lastPlayed = state.value(QStringLiteral("lastplayed")).toString().toLongLong();
    if (lastPlayed > 0) {
        game.lastPlayed = QDateTime::fromSecsSinceEpoch(lastPlayed);
    }
    return game;
}

QStringList defaultRoots(const QString &home)
{
    return {
        home + QStringLiteral("/.local/share/Steam"),
        home + QStringLiteral("/.steam/steam"),
        home + QStringLiteral("/.var/app/com.valvesoftware.Steam/.local/share/Steam"),
        home + QStringLiteral("/.var/app/com.valvesoftware.Steam/data/Steam"),
    };
}

QList<Game> scan(const QStringList &roots)
{
    QList<Game> games;
    QSet<QString> seenFolders;
    QSet<QString> seenGames;
    for (const QString &root : roots) {
        QStringList folders{root};
        folders += libraryFolders(readSmallFile(root + QStringLiteral("/steamapps/libraryfolders.vdf")));
        for (const QString &folder : std::as_const(folders)) {
            const QString canonical = QFileInfo(folder).canonicalFilePath();
            if (canonical.isEmpty() || seenFolders.contains(canonical)) {
                continue;
            }
            seenFolders.insert(canonical);
            const QDir apps(canonical + QStringLiteral("/steamapps"));
            const QStringList manifests = apps.entryList({QStringLiteral("appmanifest_*.acf")}, QDir::Files, QDir::Name);
            for (const QString &manifest : manifests) {
                const std::optional<Game> game = parseManifest(readSmallFile(apps.filePath(manifest)));
                if (game && !seenGames.contains(game->appId)) {
                    seenGames.insert(game->appId);
                    games.append(*game);
                }
            }
        }
    }
    return games;
}
}
