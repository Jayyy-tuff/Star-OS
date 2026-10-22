// SPDX-License-Identifier: GPL-3.0-or-later
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QUrl>
#include <QVariantMap>
#include <QtQml/QQmlExtensionPlugin>

// The StarOS.Files QML module is a static library; this links its plugin.
Q_IMPORT_QML_PLUGIN(StarOS_FilesPlugin)

namespace
{
// The folder to show first: the argument's folder (its parent for a file), a
// trash: URL, or nothing for the home folder.
QUrl startUrl(const QStringList &arguments)
{
    if (arguments.isEmpty()) {
        return {};
    }
    const QUrl url = QUrl::fromUserInput(arguments.constFirst(), QDir::currentPath(), QUrl::AssumeLocalFile);
    if (url.isLocalFile()) {
        const QFileInfo info(url.toLocalFile());
        return info.isFile() ? QUrl::fromLocalFile(info.absolutePath()) : url;
    }
    return url.scheme() == QLatin1String("trash") ? url : QUrl();
}
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("staros-files"));
    QCoreApplication::setApplicationVersion(QStringLiteral(STAROS_FILES_VERSION));
    // The Wayland app id, which the shell and the session test match on.
    QGuiApplication::setDesktopFileName(QStringLiteral("org.staros.files"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QCoreApplication::translate("main", "Star OS file manager"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.addPositionalArgument(QStringLiteral("folder"),
                                 QCoreApplication::translate("main", "The folder to show (a path or URL)."),
                                 QStringLiteral("[folder]"));
    parser.process(app);

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        [] {
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.setInitialProperties({{QStringLiteral("initialUrl"), startUrl(parser.positionalArguments())}});
    engine.loadFromModule("StarOS.Files", "Main");
    return app.exec();
}
