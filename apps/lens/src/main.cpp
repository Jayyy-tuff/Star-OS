// SPDX-License-Identifier: GPL-3.0-or-later
#include "captureprovider.h"

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/QQmlExtensionPlugin>

// The StarOS.Lens QML module is a static library; this links its plugin.
Q_IMPORT_QML_PLUGIN(StarOS_LensPlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("staros-lens"));
    QCoreApplication::setApplicationVersion(QStringLiteral(STAROS_LENS_VERSION));
    // The Wayland app id, which the shell and the session test match on.
    QGuiApplication::setDesktopFileName(QStringLiteral("org.staros.lens"));
    // LensBackend::quit() decides when to end: a copy may outlive the window.
    QGuiApplication::setQuitOnLastWindowClosed(false);

    QCommandLineParser parser;
    parser.setApplicationDescription(QCoreApplication::translate("main", "Star Lens: read text and codes on the screen"));
    parser.addHelpOption();
    parser.addVersionOption();
    parser.process(app);

    QQmlApplicationEngine engine;
    engine.addImageProvider(QStringLiteral("lens"), new CaptureProvider);
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        [] {
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.loadFromModule("StarOS.Lens", "Main");
    return app.exec();
}
