// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "recognizer.h"

#include <QImage>
#include <QMimeData>
#include <QObject>
#include <QQmlEngine>
#include <QRect>
#include <QSize>
#include <QStringList>
#include <QUrl>

#include <functional>

// Star Lens: captures the active screen through KWin's ScreenShot2 interface
// (granted by org.staros.lens.desktop), crops the selected area and
// recognises it offline. Opening links and searches goes to the browser.
// Copies go through KSystemClipboard, which can keep serving them after the
// window is gone (see quit()).
//
// state: "capturing", "selecting", "recognizing", "results" or "error".
class LensBackend : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY stateChanged)
    // The capture for an Image (image://lens/...) and its size in logical
    // pixels (the screen's size).
    Q_PROPERTY(QUrl captureUrl READ captureUrl NOTIFY captureChanged)
    Q_PROPERTY(QSize captureSize READ captureSize NOTIFY captureChanged)
    Q_PROPERTY(QRect selection READ selection NOTIFY resultsChanged)
    Q_PROPERTY(QString text READ text NOTIFY resultsChanged)
    Q_PROPERTY(QString code READ code NOTIFY resultsChanged)
    Q_PROPERTY(QString codeFormat READ codeFormat NOTIFY resultsChanged)
    Q_PROPERTY(QStringList links READ links NOTIFY resultsChanged)
    Q_PROPERTY(QString recognitionError READ recognitionError NOTIFY resultsChanged)
    // The outcome of the last action ("Text copied", "Saved to …").
    Q_PROPERTY(QString message READ message NOTIFY messageChanged)

public:
    using Opener = std::function<void(const QUrl &)>;

    explicit LensBackend(QObject *parent = nullptr);

    QString state() const;
    QString errorString() const;
    QUrl captureUrl() const;
    QSize captureSize() const;
    QRect selection() const;
    QString text() const;
    QString code() const;
    QString codeFormat() const;
    QStringList links() const;
    QString recognitionError() const;
    QString message() const;

    // For tests: a capture instead of KWin's, the program for text
    // recognition, where URLs go and where images are saved.
    void setCapture(const QImage &image);
    void setTesseract(const QString &program);
    void setOpener(Opener opener);
    void setPicturesDir(const QString &dir);
    QImage selectedImage() const;

    // The pixels of a selection given in logical pixels, inside the capture.
    static QRect toPixels(const QRectF &logical, const QImage &capture);

    Q_INVOKABLE void capture();
    // Recognises the area (logical pixels of the capture).
    Q_INVOKABLE void select(qreal x, qreal y, qreal width, qreal height);
    Q_INVOKABLE void selectAgain();
    // Copies `part` (selected text), or all the text when it is empty.
    Q_INVOKABLE void copyText(const QString &part = QString());
    Q_INVOKABLE void copyCode();
    Q_INVOKABLE void copyImage();
    Q_INVOKABLE QString saveImage();
    Q_INVOKABLE void searchWeb();
    Q_INVOKABLE bool openLink(const QString &link);
    // Copies and saves the image and opens Google Lens in the browser, where
    // the person pastes it. The view asks first, every time.
    Q_INVOKABLE void openGoogleLens();
    // Ends Star Lens once the window is hidden. A Wayland copy is served by
    // the program that made it and Star OS has no clipboard manager, so after
    // a copy Star Lens keeps running, without a window, until something else
    // is copied.
    Q_INVOKABLE void quit();

Q_SIGNALS:
    void stateChanged();
    void captureChanged();
    void resultsChanged();
    void messageChanged();

private:
    void setState(const QString &state, const QString &error = QString());
    void setMessage(const QString &message);
    void captureFailed(const QString &error);
    void copy(QMimeData *data, const QString &message);

    QString m_state = QStringLiteral("capturing");
    QString m_errorString;
    QImage m_capture;
    int m_serial = 0;
    QRect m_selection; // logical
    QImage m_selected;
    Recognizer::Result m_result;
    QString m_message;
    QString m_tesseract = QStringLiteral("tesseract");
    QString m_picturesDir;
    Opener m_opener;
};
