// SPDX-License-Identifier: GPL-3.0-or-later
// ClipboardHistory on Qt's in-process clipboard (KSystemClipboard uses
// QClipboard off Wayland): copies are kept newest first without duplicates,
// secrets are skipped, images are limited, a copy comes back when the
// clipboard empties, and copy, remove and clear. WidgetStore: values are
// saved, shared and reloaded, and bad files are tolerated.

#include "clipboardhistory.h"
#include "gamemodesetting.h"
#include "widgetstore.h"

#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

using namespace Qt::StringLiterals;

class DesktopServicesTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase();
    void init();
    void keepsTextNewestFirst();
    void previewsText();
    void skipsSecrets();
    void keepsFewImages();
    void keepsTwentyCopies();
    void restoresWhenTheClipboardEmpties();
    void copyPutsItBack();
    void removeAndClear();
    void storeSavesAndShares();
    void storeReloadsExternalChanges();
    void storeToleratesBadFiles();
    void gameModeSetting();

private:
    static QString text(const ClipboardHistory &history, int row);
    static QImage picture(int width, int height, QColor colour);
    QClipboard *clipboard() const;

    std::unique_ptr<QTemporaryDir> m_dir;
};

void DesktopServicesTest::initTestCase()
{
    QStandardPaths::setTestModeEnabled(true);
}

void DesktopServicesTest::init()
{
    clipboard()->clear();
    m_dir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_dir->isValid());
}

QClipboard *DesktopServicesTest::clipboard() const
{
    return QGuiApplication::clipboard();
}

QString DesktopServicesTest::text(const ClipboardHistory &history, int row)
{
    return history.data(history.index(row), ClipboardHistory::TextRole).toString();
}

QImage DesktopServicesTest::picture(int width, int height, QColor colour)
{
    QImage image(width, height, QImage::Format_ARGB32);
    image.fill(colour);
    return image;
}

void DesktopServicesTest::keepsTextNewestFirst()
{
    ClipboardHistory history;
    QSignalSpy count(&history, &ClipboardHistory::countChanged);
    clipboard()->setText(u"one"_s);
    clipboard()->setText(u"two"_s);
    QCOMPARE(history.rowCount(), 2);
    QCOMPARE(text(history, 0), u"two"_s);
    QCOMPARE(text(history, 1), u"one"_s);
    QCOMPARE(history.data(history.index(0), ClipboardHistory::KindRole).toString(), u"text"_s);
    QVERIFY(history.data(history.index(0), ClipboardHistory::CopiedAtRole).toDateTime().isValid());
    // Copying it again moves it up instead of adding it twice.
    clipboard()->setText(u"one"_s);
    QCOMPARE(history.rowCount(), 2);
    QCOMPARE(text(history, 0), u"one"_s);
    QCOMPARE(count.count(), 2);
    QCOMPARE(history.property("count").toInt(), 2);
}

void DesktopServicesTest::previewsText()
{
    ClipboardHistory history;
    clipboard()->setText(u"  first line\n\n\tsecond   line  "_s);
    QCOMPARE(text(history, 0), u"first line second line"_s);
    QCOMPARE(history.data(history.index(0), ClipboardHistory::DescriptionRole).toString(), u"30 characters"_s);
    clipboard()->setText(QString(1000, u'x'));
    QCOMPARE(text(history, 0).size(), ClipboardHistory::PreviewLength);
    clipboard()->setText(u"   "_s);
    QCOMPARE(text(history, 0), u"Blank text"_s);
    // An empty text is not a copy.
    clipboard()->setText(QString());
    QCOMPARE(history.rowCount(), 3);
}

void DesktopServicesTest::skipsSecrets()
{
    ClipboardHistory history;
    auto *mime = new QMimeData;
    mime->setText(u"hunter2"_s);
    mime->setData(u"x-kde-passwordManagerHint"_s, "secret");
    clipboard()->setMimeData(mime);
    QCOMPARE(history.rowCount(), 0);
    clipboard()->setText(u"not secret"_s);
    QCOMPARE(history.rowCount(), 1);
}

void DesktopServicesTest::keepsFewImages()
{
    ClipboardHistory history;
    clipboard()->setImage(picture(400, 200, Qt::red));
    QCOMPARE(history.rowCount(), 1);
    QCOMPARE(history.data(history.index(0), ClipboardHistory::KindRole).toString(), u"image"_s);
    QCOMPARE(history.data(history.index(0), ClipboardHistory::DescriptionRole).toString(),
             u"Image, 400 × 200 pixels"_s);
    const QString thumbnail = history.data(history.index(0), ClipboardHistory::ThumbnailRole).toString();
    QVERIFY(thumbnail.startsWith(u"data:image/png;base64,"_s));
    QImage small;
    QVERIFY(small.loadFromData(QByteArray::fromBase64(thumbnail.mid(thumbnail.indexOf(u',') + 1).toLatin1()), "PNG"));
    QCOMPARE(small.size(), QSize(ClipboardHistory::ThumbnailSize, ClipboardHistory::ThumbnailSize / 2));
    clipboard()->setText(u"text between"_s);
    const QColor colours[] = {Qt::green, Qt::blue, Qt::yellow, Qt::cyan, Qt::magenta};
    for (const QColor &colour : colours) {
        clipboard()->setImage(picture(40, 40, colour));
    }
    // Five images at most: the red one went, the text stays.
    QCOMPARE(history.rowCount(), 6);
    int images = 0;
    for (int row = 0; row < history.rowCount(); ++row) {
        images += history.data(history.index(row), ClipboardHistory::KindRole).toString() == u"image"_s ? 1 : 0;
    }
    QCOMPARE(images, ClipboardHistory::MaxImages);
    QCOMPARE(text(history, 5), u"text between"_s);
}

void DesktopServicesTest::keepsTwentyCopies()
{
    ClipboardHistory history;
    for (int i = 1; i <= 25; ++i) {
        clipboard()->setText(u"copy %1"_s.arg(i));
    }
    QCOMPARE(history.rowCount(), ClipboardHistory::MaxItems);
    QCOMPARE(text(history, 0), u"copy 25"_s);
    QCOMPARE(text(history, 19), u"copy 6"_s);
}

void DesktopServicesTest::restoresWhenTheClipboardEmpties()
{
    ClipboardHistory history;
    clipboard()->setText(u"keep me"_s);
    // The app that owned the copy quits: the clipboard is empty.
    clipboard()->clear();
    QTRY_COMPARE(clipboard()->text(), u"keep me"_s);
    QCOMPARE(history.rowCount(), 1);
}

void DesktopServicesTest::copyPutsItBack()
{
    ClipboardHistory history;
    clipboard()->setText(u"older"_s);
    clipboard()->setImage(picture(10, 10, Qt::red));
    history.copy(1);
    QCOMPARE(clipboard()->text(), u"older"_s);
    QCOMPARE(text(history, 0), u"older"_s);
    QCOMPARE(history.rowCount(), 2);
    history.copy(1);
    QCOMPARE(clipboard()->image().size(), QSize(10, 10));
    history.copy(7);
    history.copy(-1);
    QCOMPARE(history.rowCount(), 2);
}

void DesktopServicesTest::removeAndClear()
{
    ClipboardHistory history;
    clipboard()->setText(u"a"_s);
    clipboard()->setText(u"b"_s);
    clipboard()->setText(u"c"_s);
    history.remove(1);
    QCOMPARE(history.rowCount(), 2);
    QCOMPARE(text(history, 1), u"a"_s);
    history.remove(5);
    QCOMPARE(history.rowCount(), 2);
    history.clear();
    QCOMPARE(history.rowCount(), 0);
    QCOMPARE(clipboard()->text(), QString());
    // Nothing comes back after Clear, also once the change has settled.
    QTest::qWait(ClipboardHistory::SettleMs + 100);
    QCOMPARE(clipboard()->text(), QString());
    QCOMPARE(history.rowCount(), 0);
}

void DesktopServicesTest::storeSavesAndShares()
{
    const QString path = m_dir->filePath(u"staros/widgets.json"_s);
    WidgetStore store;
    store.setFilePath(path);
    QCOMPARE(store.values(), QVariantMap());
    QSignalSpy changed(&store, &WidgetStore::valuesChanged);
    store.setValue(u"shown"_s, QVariantMap{{u"clock"_s, true}, {u"weather"_s, false}});
    store.setValue(u"place"_s, QVariantMap{{u"name"_s, u"Berlin"_s}, {u"latitude"_s, 52.52}});
    QCOMPARE(changed.count(), 2);
    // The same value again changes nothing.
    store.setValue(u"place"_s, QVariantMap{{u"name"_s, u"Berlin"_s}, {u"latitude"_s, 52.52}});
    QCOMPARE(changed.count(), 2);

    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly));
    const QJsonObject saved = QJsonDocument::fromJson(file.readAll()).object();
    QCOMPARE(saved.value(u"version"_s).toInt(), 1);
    QCOMPARE(saved.value(u"place"_s).toObject().value(u"name"_s).toString(), u"Berlin"_s);

    WidgetStore second;
    second.setFilePath(path);
    QCOMPARE(second.value(u"shown"_s).toMap().value(u"weather"_s).toBool(), false);
    QCOMPARE(second.value(u"place"_s).toMap().value(u"latitude"_s).toDouble(), 52.52);
    QCOMPARE(second.value(u"missing"_s, 7).toInt(), 7);
    QVERIFY(!second.values().contains(u"version"_s));

    // An undefined value removes the key.
    store.setValue(u"place"_s, QVariant());
    QVERIFY(!store.values().contains(u"place"_s));
}

void DesktopServicesTest::storeReloadsExternalChanges()
{
    const QString path = m_dir->filePath(u"staros/widgets.json"_s);
    WidgetStore store;
    store.setFilePath(path);
    QSignalSpy changed(&store, &WidgetStore::valuesChanged);
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(R"({"version": 1, "shown": {"calendar": false}})");
    file.close();
    QTRY_VERIFY(changed.count() >= 1);
    QCOMPARE(store.value(u"shown"_s).toMap().value(u"calendar"_s).toBool(), false);
}

void DesktopServicesTest::storeToleratesBadFiles()
{
    const QString path = m_dir->filePath(u"widgets.json"_s);
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write("{not json");
    file.close();
    WidgetStore store;
    store.setFilePath(path);
    QCOMPARE(store.values(), QVariantMap());

    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write("{\"big\": \"" + QByteArray(WidgetStore::MaxFileSize, 'x') + "\"}");
    file.close();
    store.reload();
    QCOMPARE(store.values(), QVariantMap());
}

void DesktopServicesTest::gameModeSetting()
{
    const QString path = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + u"/staros-gamesrc"_s;
    QFile::remove(path);
    GameModeSetting setting;
    QVERIFY(!setting.enabled());
    QCOMPARE(setting.available(), !QStandardPaths::findExecutable(u"gamemoderun"_s).isEmpty());
    QSignalSpy changed(&setting, &GameModeSetting::enabledChanged);
    setting.setEnabled(true);
    QVERIFY(setting.enabled());
    QCOMPARE(changed.count(), 1);
    setting.setEnabled(true);
    QCOMPARE(changed.count(), 1);
    QFile file(path);
    QVERIFY(file.open(QIODevice::ReadOnly));
    QVERIFY(file.readAll().contains("GameMode=true"));
    // What Game Center would read.
    GameModeSetting other;
    QVERIFY(other.enabled());
}

QTEST_MAIN(DesktopServicesTest)
#include "tst_desktopservices.moc"
