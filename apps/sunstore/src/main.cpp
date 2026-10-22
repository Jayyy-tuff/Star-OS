// SPDX-License-Identifier: GPL-3.0-or-later
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/QQmlExtensionPlugin>

// The StarOS.SunStore QML module is a static library; this links its plugin.
Q_IMPORT_QML_PLUGIN(StarOS_SunStorePlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("staros-sunstore"));
    QCoreApplication::setApplicationVersion(QStringLiteral(STAROS_SUNSTORE_VERSION));
    // The Wayland app id, which the shell and the session test match on.
    QGuiApplication::setDesktopFileName(QStringLiteral("org.staros.sunstore"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QCoreApplication::translate("main", "Star OS app store for Flatpak apps from Flathub"));
    parser.addHelpOption();
    parser.addVersionOption();
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
    engine.loadFromModule("StarOS.SunStore", "Main");
    return app.exec();
}
