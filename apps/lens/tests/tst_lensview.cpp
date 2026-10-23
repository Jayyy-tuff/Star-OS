// SPDX-License-Identifier: GPL-3.0-or-later
// Qt Quick Test runner for the Star Lens view (tests in qml/). StarOS.Lens is
// linked in; StarOS.Shell is loaded from the repository's shell tree.
#include <QObject>
#include <QQmlEngine>
#include <QtQml/QQmlExtensionPlugin>
#include <QtQuickTest>

Q_IMPORT_QML_PLUGIN(StarOS_LensPlugin)

class Setup : public QObject
{
    Q_OBJECT

public Q_SLOTS:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        engine->addImportPath(QStringLiteral(STAROS_SHELL_QML_DIR));
    }
};

QUICK_TEST_MAIN_WITH_SETUP(lensview, Setup)

#include "tst_lensview.moc"
