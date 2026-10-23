// SPDX-License-Identifier: GPL-3.0-or-later
#include <QCommandLineParser>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/QQmlExtensionPlugin>

// The StarOS.Storage QML module is a static library; this links its plugin.
Q_IMPORT_QML_PLUGIN(StarOS_StoragePlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("staros-storage"));
    QCoreApplication::setApplicationVersion(QStringLiteral(STAROS_STORAGE_VERSION));
    // The Wayland app id, which the shell and the session test match on.
    QGuiApplication::setDesktopFileName(QStringLiteral("org.staros.storage"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QCoreApplication::translate("main", "Star Storage: keep the live system's changes on a disk"));
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
    engine.loadFromModule("StarOS.Storage", "Main");
    return app.exec();
}
