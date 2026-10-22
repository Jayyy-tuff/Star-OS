// SPDX-License-Identifier: GPL-3.0-or-later
// The AppStream catalogue reader on data/appstream.xml: desktop apps only,
// untranslated texts, cached icons, and the gzip file older flatpak writes.

#include "appstream.h"

#include <KCompressionDevice>

#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QTemporaryDir>
#include <QTest>

#include <memory>

class AppStreamTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void init();
    void readsDesktopApps();
    void readsGzipCatalogue();
    void missingCatalogueIsEmpty();
    void rejectsOtherDocuments();

private:
    QByteArray fixture() const;
    void makeIcons(const QString &activeDir);

    std::unique_ptr<QTemporaryDir> m_dir;
};

QByteArray AppStreamTest::fixture() const
{
    QFile file(QStringLiteral(SUNSTORE_TEST_DATA "/appstream.xml"));
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return file.readAll();
}

void AppStreamTest::init()
{
    m_dir = std::make_unique<QTemporaryDir>();
    QVERIFY(m_dir->isValid());
}

// The Editor has a 128 px icon, the Game only a 64 px one.
void AppStreamTest::makeIcons(const QString &activeDir)
{
    QDir dir(activeDir);
    QVERIFY(dir.mkpath(QStringLiteral("icons/128x128")));
    QVERIFY(dir.mkpath(QStringLiteral("icons/64x64")));
    for (const char *path : {"icons/128x128/org.example.Editor.png", "icons/64x64/org.example.Editor.png", "icons/64x64/org.example.Game.png"}) {
        QFile icon(dir.filePath(QLatin1String(path)));
        QVERIFY(icon.open(QIODevice::WriteOnly));
    }
}

void AppStreamTest::readsDesktopApps()
{
    const QString active = m_dir->path();
    makeIcons(active);
    QFile catalogue(QDir(active).filePath(QStringLiteral("appstream.xml")));
    QVERIFY(catalogue.open(QIODevice::WriteOnly));
    QVERIFY(catalogue.write(fixture()) > 0);
    catalogue.close();

    const QList<CatalogueApp> apps = AppStream::loadActive(active);
    QCOMPARE(apps.size(), 2);

    const CatalogueApp &editor = apps.at(0);
    QCOMPARE(editor.id, QStringLiteral("org.example.Editor"));
    QCOMPARE(editor.name, QStringLiteral("Example Editor"));
    QCOMPARE(editor.summary, QStringLiteral("Edit plain text"));
    QCOMPARE(editor.description, QStringLiteral("Writes text files.\n\n• Fast\n• Small"));
    QCOMPARE(editor.iconPath, QDir(active).filePath(QStringLiteral("icons/128x128/org.example.Editor.png")));
    QCOMPARE(editor.developer, QStringLiteral("Example Developers"));
    QCOMPARE(editor.license, QStringLiteral("GPL-3.0-or-later"));
    QCOMPARE(editor.version, QStringLiteral("2.1"));
    QCOMPARE(editor.categories, QStringList({"Utility", "TextEditor"}));
    QVERIFY(editor.verified);

    const CatalogueApp &game = apps.at(1);
    QCOMPARE(game.id, QStringLiteral("org.example.Game"));
    QCOMPARE(game.name, QStringLiteral("Example Game"));
    QCOMPARE(game.developer, QStringLiteral("Game Maker"));
    QCOMPARE(game.iconPath, QDir(active).filePath(QStringLiteral("icons/64x64/org.example.Game.png")));
    QCOMPARE(game.categories, QStringList({"Game"}));
    QCOMPARE(game.description, QString());
    QCOMPARE(game.version, QString());
    QVERIFY(!game.verified);
}

void AppStreamTest::readsGzipCatalogue()
{
    const QString active = m_dir->path();
    {
        KCompressionDevice gzip(QDir(active).filePath(QStringLiteral("appstream.xml.gz")), KCompressionDevice::GZip);
        QVERIFY(gzip.open(QIODevice::WriteOnly));
        QVERIFY(gzip.write(fixture()) > 0);
        gzip.close();
    }
    const QList<CatalogueApp> apps = AppStream::loadActive(active);
    QCOMPARE(apps.size(), 2);
    QCOMPARE(apps.at(0).id, QStringLiteral("org.example.Editor"));
    // No icon files in this folder.
    QCOMPARE(apps.at(0).iconPath, QString());
}

void AppStreamTest::missingCatalogueIsEmpty()
{
    QVERIFY(AppStream::loadActive(m_dir->filePath(QStringLiteral("missing"))).isEmpty());
}

void AppStreamTest::rejectsOtherDocuments()
{
    QByteArray data("<?xml version=\"1.0\"?><component type=\"desktop-application\"><id>org.example.Editor</id></component>");
    QBuffer buffer(&data);
    QVERIFY(buffer.open(QIODevice::ReadOnly));
    QVERIFY(AppStream::parse(&buffer, QString()).isEmpty());
}

QTEST_GUILESS_MAIN(AppStreamTest)

#include "tst_appstream.moc"
