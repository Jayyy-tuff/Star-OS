// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QImage>
#include <QString>
#include <QStringList>

// Offline recognition for Star Lens: text with the Tesseract command line,
// one QR code or barcode with KDE's Prison scanner (ZXing), and the links in
// either. Blocking; Star Lens runs it on a worker thread.
namespace Recognizer
{
struct Result {
    QString text;
    QString code; // the barcode's text, empty if none
    QString codeFormat; // e.g. "QRCode", "EAN13"
    QStringList links; // http(s) URLs, "www." addresses as https
    QString error; // why text recognition did not run, if it did not
};

// Tesseract on the image (English); empty text when nothing is found.
QString readText(const QImage &image, const QString &tesseract, QString *error);
// The first QR code or barcode in the image.
void readCode(const QImage &image, QString *code, QString *format);
// Links in text, in order, without duplicates or trailing punctuation.
QStringList findLinks(const QString &text);

Result recognize(const QImage &image, const QString &tesseract = QStringLiteral("tesseract"));
}
