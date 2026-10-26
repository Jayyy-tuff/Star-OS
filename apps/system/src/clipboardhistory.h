// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QImage>
#include <QList>
#include <QPointer>
#include <QQmlEngine>
#include <QString>

class KSystemClipboard;
class QAction;
class QMimeData;

// The clipboard history (M0.5, ADR-0014): the last copies of text and
// images, newest first, kept in memory only. When the clipboard empties
// because the app that owned it closed, the newest copy is offered again.
// Copies an app marks as secret (x-kde-passwordManagerHint) are not kept.
//
// KSystemClipboard reads the Wayland clipboard through the data-control
// protocol inside plasmashell, and QClipboard elsewhere (the tests).
class ClipboardHistory : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    // Meta+V through KGlobalAccel ("staros-shell"); emits shortcutActivated.
    Q_PROPERTY(bool keysEnabled READ keysEnabled WRITE setKeysEnabled NOTIFY keysEnabledChanged)

public:
    enum Role {
        KindRole = Qt::UserRole + 1,
        TextRole,
        ThumbnailRole,
        DescriptionRole,
        CopiedAtRole,
    };
    Q_ENUM(Role)

    static constexpr int MaxItems = 20;
    static constexpr int MaxImages = 5;
    static constexpr int MaxTextLength = 1000000;
    static constexpr int PreviewLength = 300;
    static constexpr int ThumbnailSize = 240;

    explicit ClipboardHistory(QObject *parent = nullptr);
    ~ClipboardHistory() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool keysEnabled() const;
    void setKeysEnabled(bool enabled);

    // Puts the copy back on the clipboard and moves it to the top.
    Q_INVOKABLE void copy(int row);
    Q_INVOKABLE void remove(int row);
    // Empties the history and the clipboard.
    Q_INVOKABLE void clear();

Q_SIGNALS:
    void countChanged();
    void keysEnabledChanged();
    void shortcutActivated();

private:
    struct Item {
        bool image = false;
        QString text;
        QImage picture;
        QByteArray hash;
        QString thumbnail;
        QDateTime copiedAt;
    };

    void onChanged();
    void add(Item item);
    void restore();
    QMimeData *mimeFor(const Item &item) const;
    int indexOf(const QByteArray &hash, bool image) const;

    KSystemClipboard *m_clipboard = nullptr;
    QList<Item> m_items;
    QPointer<QAction> m_action;
    bool m_keysEnabled = false;
    QDateTime m_lastRestore;
};
