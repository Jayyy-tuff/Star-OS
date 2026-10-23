// SPDX-License-Identifier: GPL-3.0-or-later
// LensBackend with a capture given by the test (no KWin): selections in
// logical pixels on a scale 2 screen, the results, copying, saving, and what
// is opened in the browser (a recording opener instead of KIO).
#include "lensbackend.h"

#include <Prison/Barcode>
#include <Prison/Prison>

#include <QClipboard>
#include <QDir>
#include <QGuiApplication>
#include <QPainter>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>
#include <QUrlQuery>

#include <memory>

using namespace Qt::StringLiterals;

namespace
{
const QString qrText = u"https://star-os.example/lens"_s;

// An 800 × 600 pixel screen at scale 2 (400 × 300 logical) with a QR code at
// pixels (100, 100)–(340, 340).
QImage screenWithQrCode()
{
    QImage screen(800, 600, QImage::Format_RGB32);
    screen.fill(Qt::white);
    auto code = Prison::Barcode::create(Prison::QRCode);
    if (!code) {
        return {};
    }
    code->setData(qrText);
    QPainter painter(&screen);
    painter.drawImage(100, 100, code->toImage(QSizeF(240, 240)));
    painter.end();
    screen.setDevicePixelRatio(2);
    return screen;
}
}

class BackendTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void toPixels();
    void startsCapturing();
    void captureWithoutKWinIsAnError();
    void emptyCaptureIsAnError();
    void selectionIsRecognised();
    void tinySelectionIsIgnored();
    void copyAndSave();
    void opensOnlyFoundLinks();
    void searchWeb();
    void googleLensCopiesSavesAndOpens();
    void selectAgain();

private:
    void recognise(LensBackend &lens);

    std::unique_ptr<QTemporaryDir> m_pictures;
    QList<QUrl> m_opened;
};

void BackendTest::init()
{
    m_pictures = std::make_unique<QTemporaryDir>();
    QVERIFY(m_pictures->isValid());
    m_opened.clear();
}

// Selects the QR code's area (logical 40, 40, 160 × 160) and waits for the
// results. Tesseract is left out: its absence is reported, codes still work.
void BackendTest::recognise(LensBackend &lens)
{
    const QImage screen = screenWithQrCode();
    QVERIFY2(!screen.isNull(), "Prison can generate QR codes");
    lens.setTesseract(u"/nonexistent/tesseract"_s);
    lens.setPicturesDir(m_pictures->filePath(u"Star Lens"_s));
    lens.setOpener([this](const QUrl &url) {
        m_opened.append(url);
    });
    lens.setCapture(screen);
    QCOMPARE(lens.state(), u"selecting"_s);
    lens.select(40, 40, 160, 160);
    QCOMPARE(lens.state(), u"recognizing"_s);
    QTRY_COMPARE_WITH_TIMEOUT(lens.state(), u"results"_s, 30000);
}

void BackendTest::toPixels()
{
    QImage capture(800, 600, QImage::Format_RGB32);
    capture.setDevicePixelRatio(2);
    QCOMPARE(LensBackend::toPixels(QRectF(10, 20, 30, 40), capture), QRect(20, 40, 60, 80));
    // Fractions grow to whole pixels; the result stays inside the capture.
    QCOMPARE(LensBackend::toPixels(QRectF(0.25, 0.25, 1, 1), capture), QRect(0, 0, 3, 3));
    QCOMPARE(LensBackend::toPixels(QRectF(350, 250, 100, 100), capture), QRect(700, 500, 100, 100));
    QImage plain(100, 100, QImage::Format_RGB32);
    QCOMPARE(LensBackend::toPixels(QRectF(10, 10, 20, 20), plain), QRect(10, 10, 20, 20));
}

void BackendTest::startsCapturing()
{
    LensBackend lens;
    QCOMPARE(lens.state(), u"capturing"_s);
    QVERIFY(lens.captureUrl().isEmpty());
    QVERIFY(lens.errorString().isEmpty());
}

void BackendTest::captureWithoutKWinIsAnError()
{
    // The tests run without a session bus, so the call to KWin fails.
    LensBackend lens;
    lens.capture();
    QTRY_COMPARE_WITH_TIMEOUT(lens.state(), u"error"_s, 20000);
    QVERIFY2(lens.errorString().startsWith(u"Star Lens could not take a screenshot: "_s), qPrintable(lens.errorString()));
    QVERIFY(lens.captureUrl().isEmpty());
}

void BackendTest::emptyCaptureIsAnError()
{
    LensBackend lens;
    lens.setCapture(QImage());
    QCOMPARE(lens.state(), u"error"_s);
    QCOMPARE(lens.errorString(), u"Star Lens could not take a screenshot: The screenshot was empty."_s);
}

void BackendTest::selectionIsRecognised()
{
    LensBackend lens;
    QSignalSpy capture(&lens, &LensBackend::captureChanged);
    recognise(lens);
    QCOMPARE(capture.count(), 1);
    QVERIFY(lens.captureUrl().toString().startsWith(u"image://lens/capture?"_s));
    QCOMPARE(lens.captureSize(), QSize(400, 300));

    QCOMPARE(lens.selection(), QRect(40, 40, 160, 160));
    // Cut out at full resolution.
    QCOMPARE(lens.selectedImage().size(), QSize(320, 320));
    QCOMPARE(lens.code(), qrText);
    QCOMPARE(lens.codeFormat(), u"QRCode"_s);
    QCOMPARE(lens.links(), QStringList{qrText});
    QVERIFY(lens.text().isEmpty());
    QVERIFY2(lens.recognitionError().contains(u"could not be started"_s), qPrintable(lens.recognitionError()));
}

void BackendTest::tinySelectionIsIgnored()
{
    LensBackend lens;
    lens.setCapture(screenWithQrCode());
    lens.select(10, 10, 1, 1);
    QCOMPARE(lens.state(), u"selecting"_s);
}

void BackendTest::copyAndSave()
{
    LensBackend lens;
    recognise(lens);
    QClipboard *clipboard = QGuiApplication::clipboard();

    lens.copyCode();
    QCOMPARE(clipboard->text(), qrText);
    QCOMPARE(lens.message(), u"Code copied."_s);
    lens.copyText(u"part"_s);
    QCOMPARE(clipboard->text(), u"part"_s);
    QCOMPARE(lens.message(), u"Text copied."_s);
    lens.copyImage();
    QCOMPARE(clipboard->image().size(), QSize(320, 320));
    QCOMPARE(lens.message(), u"Image copied."_s);

    const QString path = lens.saveImage();
    QVERIFY(path.startsWith(m_pictures->filePath(u"Star Lens/Star Lens "_s)));
    QVERIFY(path.endsWith(u".png"_s));
    QCOMPARE(QImage(path).size(), QSize(320, 320));
    QCOMPARE(lens.message(), u"Saved to %1"_s.arg(path));
}

void BackendTest::opensOnlyFoundLinks()
{
    LensBackend lens;
    recognise(lens);
    QVERIFY(!lens.openLink(u"https://elsewhere.example/"_s));
    QVERIFY(!lens.openLink(u"file:///etc/passwd"_s));
    QVERIFY(m_opened.isEmpty());
    QVERIFY(lens.openLink(qrText));
    QCOMPARE(m_opened, QList<QUrl>{QUrl(qrText)});
}

void BackendTest::searchWeb()
{
    LensBackend lens;
    recognise(lens);
    // No text was read, so the code is searched for.
    lens.searchWeb();
    QCOMPARE(m_opened.size(), 1);
    const QUrl url = m_opened.constFirst();
    QCOMPARE(url.scheme(), u"https"_s);
    QCOMPARE(url.host(), u"www.google.com"_s);
    QCOMPARE(url.path(), u"/search"_s);
    QCOMPARE(QUrlQuery(url).queryItemValue(u"q"_s, QUrl::FullyDecoded), qrText);
}

void BackendTest::googleLensCopiesSavesAndOpens()
{
    LensBackend lens;
    recognise(lens);
    lens.openGoogleLens();
    QCOMPARE(m_opened, QList<QUrl>{QUrl(u"https://lens.google.com/"_s)});
    QCOMPARE(QGuiApplication::clipboard()->image().size(), QSize(320, 320));
    const QStringList saved = QDir(m_pictures->filePath(u"Star Lens"_s)).entryList({u"*.png"_s});
    QCOMPARE(saved.size(), 1);
    QVERIFY2(lens.message().startsWith(u"Google Lens opened in your browser."_s), qPrintable(lens.message()));
}

void BackendTest::selectAgain()
{
    LensBackend lens;
    recognise(lens);
    lens.copyCode();
    lens.selectAgain();
    QCOMPARE(lens.state(), u"selecting"_s);
    QVERIFY(lens.message().isEmpty());
}

QTEST_MAIN(BackendTest)

#include "tst_backend.moc"
