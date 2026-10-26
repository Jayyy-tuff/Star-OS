// SPDX-License-Identifier: GPL-3.0-or-later
#include "themeiconprovider.h"

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/QQmlExtensionPlugin>

// The StarOS.Games QML module is a static library; this links its plugin.
Q_IMPORT_QML_PLUGIN(StarOS_GamesPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("staros-games"));
    QCoreApplication::setApplicationVersion(QStringLiteral(STAROS_GAMES_VERSION));
    // The Wayland app id, which the shell and the session test match on.
    QGuiApplication::setDesktopFileName(QStringLiteral("org.staros.games"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QCoreApplication::translate("main", "Star OS Game Center: your games in one place"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.process(app);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("icon"), new ThemeIconProvider);
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        [] {
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.loadFromModule("StarOS.Games", "Main");
    return app.exec();
}
