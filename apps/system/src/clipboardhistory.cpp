// SPDX-License-Identifier: GPL-3.0-or-later
#include "clipboardhistory.h"

#include <QAction>
#include <QBuffer>
#include <QClipboard>
#include <QCryptographicHash>
#include <QKeySequence>
#include <QMimeData>

#include <KGlobalAccel>
#include <KSystemClipboard>

namespace
{
const QString SecretHint = QStringLiteral("x-kde-passwordManagerHint");

QByteArray hashText(const QString &text)
{
    return QCryptographicHash::hash(text.toUtf8(), QCryptographicHash::Sha1);
}

QByteArray hashImage(const QImage &image)
{
    QCryptographicHash hash(QCryptographicHash::Sha1);
    hash.addData(QByteArray::number(image.width()) + 'x' + QByteArray::number(image.height()));
    hash.addData(QByteArrayView(reinterpret_cast<const char *>(image.constBits()), image.sizeInBytes()));
    return hash.result();
}

QString thumbnailFor(const QImage &image)
{
    const QImage small = image.width() > ClipboardHistory::ThumbnailSize || image.height() > ClipboardHistory::ThumbnailSize
        ? image.scaled(ClipboardHistory::ThumbnailSize, ClipboardHistory::ThumbnailSize, Qt::KeepAspectRatio,
                       Qt::SmoothTransformation)
        : image;
    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    small.save(&buffer, "PNG");
    return QStringLiteral("data:image/png;base64,") + QString::fromLatin1(png.toBase64());
}
}

ClipboardHistory::ClipboardHistory(QObject *parent)
    : QAbstractListModel(parent)
    , m_clipboard(KSystemClipboard::instance())
{
    if (m_clipboard) {
        connect(m_clipboard, &KSystemClipboard::changed, this, [this](QClipboard::Mode mode) {
            if (mode == QClipboard::Clipboard) {
                onChanged();
            }
        });
        onChanged();
    }
}

ClipboardHistory::~ClipboardHistory() = default;

int ClipboardHistory::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant ClipboardHistory::data(const QModelIndex &index, int role) const
{
    if (!checkIndex(index, CheckIndexOption::IndexIsValid | CheckIndexOption::ParentIsInvalid)) {
        return {};
    }
    const Item &item = m_items.at(index.row());
    switch (role) {
    case KindRole:
        return item.image ? QStringLiteral("image") : QStringLiteral("text");
    case Qt::DisplayRole:
    case TextRole: {
        if (item.image) {
            return tr("Image");
        }
        const QString preview = item.text.left(PreviewLength * 4).simplified().left(PreviewLength);
        return preview.isEmpty() ? tr("Blank text") : preview;
    }
    case ThumbnailRole:
        return item.thumbnail;
    case DescriptionRole:
        return item.image ? tr("Image, %1 × %2 pixels").arg(item.picture.width()).arg(item.picture.height())
                          : tr("%n characters", nullptr, int(item.text.size()));
    case CopiedAtRole:
        return item.copiedAt;
    }
    return {};
}

QHash<int, QByteArray> ClipboardHistory::roleNames() const
{
    return {
        {KindRole, "kind"},
        {TextRole, "text"},
        {ThumbnailRole, "thumbnail"},
        {DescriptionRole, "description"},
        {CopiedAtRole, "copiedAt"},
    };
}

bool ClipboardHistory::keysEnabled() const
{
    return m_keysEnabled;
}

void ClipboardHistory::setKeysEnabled(bool enabled)
{
    if (enabled == m_keysEnabled) {
        return;
    }
    m_keysEnabled = enabled;
    if (enabled && !m_action) {
        m_action = new QAction(tr("Show Clipboard History"), this);
        m_action->setObjectName(QStringLiteral("show_clipboard_history"));
        m_action->setProperty("componentName", QStringLiteral("staros-shell"));
        m_action->setProperty("componentDisplayName", tr("Star OS shell"));
        KGlobalAccel::setGlobalShortcut(m_action, QKeySequence(Qt::META | Qt::Key_V));
        connect(m_action, &QAction::triggered, this, &ClipboardHistory::shortcutActivated);
    }
    if (m_action) {
        m_action->setEnabled(enabled);
    }
    Q_EMIT keysEnabledChanged();
}

void ClipboardHistory::onChanged()
{
    const QMimeData *mime = m_clipboard->mimeData(QClipboard::Clipboard);
    if (!mime || mime->formats().isEmpty()) {
        // The app that owned the copy went away (or cleared it): offer the
        // newest copy again, after this change has been delivered.
        QMetaObject::invokeMethod(this, &ClipboardHistory::restore, Qt::QueuedConnection);
        return;
    }
    if (mime->data(SecretHint) == "secret") {
        return;
    }
    Item item;
    item.copiedAt = QDateTime::currentDateTime();
    if (mime->hasText()) {
        item.text = mime->text();
        if (item.text.isEmpty() || item.text.size() > MaxTextLength) {
            return;
        }
        item.hash = hashText(item.text);
    } else if (mime->hasImage()) {
        item.picture = qvariant_cast<QImage>(mime->imageData());
        if (item.picture.isNull()) {
            return;
        }
        item.image = true;
        item.hash = hashImage(item.picture);
    } else {
        return;
    }
    add(std::move(item));
}

int ClipboardHistory::indexOf(const QByteArray &hash, bool image) const
{
    for (qsizetype i = 0; i < m_items.size(); ++i) {
        if (m_items.at(i).image == image && m_items.at(i).hash == hash) {
            return int(i);
        }
    }
    return -1;
}

void ClipboardHistory::add(Item item)
{
    const int existing = indexOf(item.hash, item.image);
    if (existing == 0) {
        return;
    }
    if (existing > 0) {
        beginMoveRows(QModelIndex(), existing, existing, QModelIndex(), 0);
        m_items.move(existing, 0);
        endMoveRows();
        return;
    }
    if (item.image) {
        item.thumbnail = thumbnailFor(item.picture);
    }
    beginInsertRows(QModelIndex(), 0, 0);
    m_items.prepend(std::move(item));
    endInsertRows();
    // The oldest copies go first; images, which can be large, are fewer.
    int images = 0;
    for (int row = 0; row < int(m_items.size());) {
        const bool image = m_items.at(row).image;
        images += image ? 1 : 0;
        if (row >= MaxItems || (image && images > MaxImages)) {
            beginRemoveRows(QModelIndex(), row, row);
            m_items.removeAt(row);
            endRemoveRows();
            continue;
        }
        ++row;
    }
    Q_EMIT countChanged();
}

QMimeData *ClipboardHistory::mimeFor(const Item &item) const
{
    auto *mime = new QMimeData;
    if (item.image) {
        mime->setImageData(item.picture);
    } else {
        mime->setText(item.text);
    }
    return mime;
}

void ClipboardHistory::restore()
{
    if (!m_clipboard) {
        return;
    }
    const QMimeData *mime = m_clipboard->mimeData(QClipboard::Clipboard);
    if (m_items.isEmpty() || (mime && !mime->formats().isEmpty())) {
        return;
    }
    // Never more than once a second, should the clipboard refuse the copy.
    const QDateTime now = QDateTime::currentDateTimeUtc();
    if (m_lastRestore.isValid() && m_lastRestore.msecsTo(now) < 1000) {
        return;
    }
    m_lastRestore = now;
    m_clipboard->setMimeData(mimeFor(m_items.first()), QClipboard::Clipboard);
}

void ClipboardHistory::copy(int row)
{
    if (!m_clipboard || row < 0 || row >= int(m_items.size())) {
        return;
    }
    if (row > 0) {
        beginMoveRows(QModelIndex(), row, row, QModelIndex(), 0);
        m_items.move(row, 0);
        endMoveRows();
    }
    m_clipboard->setMimeData(mimeFor(m_items.first()), QClipboard::Clipboard);
}

void ClipboardHistory::remove(int row)
{
    if (row < 0 || row >= int(m_items.size())) {
        return;
    }
    beginRemoveRows(QModelIndex(), row, row);
    m_items.removeAt(row);
    endRemoveRows();
    Q_EMIT countChanged();
}

void ClipboardHistory::clear()
{
    if (!m_items.isEmpty()) {
        beginResetModel();
        m_items.clear();
        endResetModel();
        Q_EMIT countChanged();
    }
    if (m_clipboard) {
        m_clipboard->clear(QClipboard::Clipboard);
    }
}
