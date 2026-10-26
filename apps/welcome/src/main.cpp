// SPDX-License-Identifier: GPL-3.0-or-later
#include "welcomestate.h"

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QtQml/QQmlExtensionPlugin>

// The StarOS.Welcome QML module is a static library; this links its plugin.
Q_IMPORT_QML_PLUGIN(StarOS_WelcomePlugin)

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("staros-welcome"));
    QCoreApplication::setApplicationVersion(QStringLiteral(STAROS_WELCOME_VERSION));
    // The Wayland app id, which the shell and the session test match on.
    QGuiApplication::setDesktopFileName(QStringLiteral("org.staros.welcome"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QCoreApplication::translate("main", "A short tour of Star OS"));
    parser.addHelpOption();
    parser.addVersionOption();
    // From /etc/xdg/autostart: only for a user who has not seen the tour.
    const QCommandLineOption autostartOption(QStringLiteral("autostart"),
                                             QCoreApplication::translate("main", "Open only if the tour was never finished or skipped."));
    parser.addOption(autostartOption);
    parser.process(app);

    if (parser.isSet(autostartOption) && WelcomeState::shownBefore(WelcomeState::defaultConfigPath())) {
        return 0;
    }

    QQmlApplicationEngine engine;
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        [] {
            QCoreApplication::exit(1);
        },
        Qt::QueuedConnection);
    engine.loadFromModule("StarOS.Welcome", "Main");
    return app.exec();
}
