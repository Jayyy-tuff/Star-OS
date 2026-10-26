// SPDX-License-Identifier: GPL-3.0-or-later
// Qt Quick Test runner for the Game Center view (tests in qml/). StarOS.Games
// is linked in; StarOS.Shell is loaded from the repository's shell tree.
#include <QObject>
#include <QQmlEngine>
#include <QtQml/QQmlExtensionPlugin>
#include <QtQuickTest>

Q_IMPORT_QML_PLUGIN(StarOS_GamesPlugin)

class Setup : public QObject
{
    Q_OBJECT

public Q_SLOTS:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->addImportPath(QStringLiteral(STAROS_SHELL_QML_DIR));
    }
};

QUICK_TEST_MAIN_WITH_SETUP(gameview, Setup)

#include "tst_gameview.moc"
