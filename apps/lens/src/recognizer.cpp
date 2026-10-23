// SPDX-License-Identifier: GPL-3.0-or-later
#include "recognizer.h"

#include <Prison/Format>
#include <Prison/ImageScanner>
#include <Prison/ScanResult>

#include <QBuffer>
#include <QCoreApplication>
#include <QMetaEnum>
#include <QProcess>
#include <QRegularExpression>
#include <QUrl>

namespace
{
QString tr(const char *text)
{
    return QCoreApplication::translate("Recognizer", text);
}

// Tesseract reads small text better when it is larger.
QImage prepare(const QImage &image)
{
    QImage gray = image.convertToFormat(QImage::Format_Grayscale8);
    gray.setDevicePixelRatio(1);
    if (gray.width() < 1200 && gray.height() < 1200) {
        gray = gray.scaled(gray.size() * 2, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    return gray;
}
}

namespace Recognizer
{
QString readText(const QImage &image, const QString &tesseract, QString *error)
{
    if (image.isNull()) {
        return {};
    }
    QByteArray png;
    QBuffer buffer(&png);
    buffer.open(QIODevice::WriteOnly);
    prepare(image).save(&buffer, "PNG");

    QProcess process;
    process.setProgram(tesseract);
    // stdin/stdout: no temporary files. psm 3: automatic page layout.
    process.setArguments({QStringLiteral("stdin"), QStringLiteral("stdout"), QStringLiteral("-l"), QStringLiteral("eng"),
                          QStringLiteral("--psm"), QStringLiteral("3")});
    process.start();
    if (!process.waitForStarted(10000)) {
        if (error) {
            *error = tr("Text recognition is not available: %1 could not be started.").arg(tesseract);
        }
        return {};
    }
    process.write(png);
    process.closeWriteChannel();
    if (!process.waitForFinished(60000) || process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        process.kill();
        if (error) {
            const QString detail = QString::fromUtf8(process.readAllStandardError()).trimmed().section(QLatin1Char('\n'), -1);
            *error = tr("Text recognition failed. %1").arg(detail);
        }
        return {};
    }
    QString text = QString::fromUtf8(process.readAllStandardOutput());
    text.remove(QChar(0x0c)); // page break
    text.replace(QRegularExpression(QStringLiteral("[ \\t]+\\n")), QStringLiteral("\n"));
    text.replace(QRegularExpression(QStringLiteral("\\n{3,}")), QStringLiteral("\n\n"));
    return text.trimmed();
}

void readCode(const QImage &image, QString *code, QString *format)
{
    code->clear();
    format->clear();
    if (image.isNull()) {
        return;
    }
    const Prison::ScanResult result = Prison::ImageScanner::scan(image);
    if (!result.hasContent()) {
        return;
    }
    *code = result.hasText() ? result.text() : QString::fromLatin1(result.binaryData().toHex(' '));
    const QMetaEnum formats = QMetaEnum::fromType<Prison::Format::BarcodeFormat>();
    const char *name = formats.valueToKey(int(result.format()));
    *format = name ? QString::fromLatin1(name) : QString();
}

QStringList findLinks(const QString &text)
{
    static const QRegularExpression pattern(QStringLiteral("\\b(?:https?://|www\\.)[^\\s<>\"'`]+"),
                                            QRegularExpression::CaseInsensitiveOption);
    QStringList links;
    auto it = pattern.globalMatch(text);
    while (it.hasNext()) {
        QString link = it.next().captured(0);
        while (!link.isEmpty() && QStringLiteral(".,;:!?)]}").contains(link.back())) {
            link.chop(1);
        }
        if (link.startsWith(QLatin1String("www."), Qt::CaseInsensitive)) {
            link.prepend(QStringLiteral("https://"));
        }
        const QUrl url(link, QUrl::StrictMode);
        if (url.isValid() && !url.host().isEmpty() && !links.contains(link)) {
            links.append(link);
        }
    }
    return links;
}

Result recognize(const QImage &image, const QString &tesseract)
{
    Result result;
    result.text = readText(image, tesseract, &result.error);
    readCode(image, &result.code, &result.codeFormat);
    result.links = findLinks(result.text + QLatin1Char('\n') + result.code);
    return result;
}
}
