# SPDX-License-Identifier: GPL-3.0-or-later

# The plugin is its own backing target, so the module is one shared library
# plus its qmldir and type information.
qt_add_qml_module(staros_system
    URI StarOS.System
    VERSION 1.0
    PLUGIN_TARGET staros_system
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/StarOS/System
    SOURCES
        applicationsmodel.cpp applicationsmodel.h
        audiocontrol.cpp audiocontrol.h
        clipboardhistory.cpp clipboardhistory.h
        displaycontrol.cpp displaycontrol.h
        networkstatus.cpp networkstatus.h
        notesstore.cpp notesstore.h
        systemstatus.cpp systemstatus.h
        widgetstore.cpp widgetstore.h
)

target_link_libraries(staros_system PRIVATE
    Qt6::Core Qt6::DBus Qt6::Gui Qt6::Qml
    KF6::ConfigCore KF6::GlobalAccel KF6::GuiAddons KF6::KIOGui KF6::PulseAudioQt KF6::Service
)
# KDECMakeSettings drops the prefix of MODULE libraries; the QML engine looks
# for lib<plugin>.so.
set_target_properties(staros_system PROPERTIES PREFIX "lib")

set(module_dir ${KDE_INSTALL_QMLDIR}/StarOS/System)
install(TARGETS staros_system DESTINATION ${module_dir})
install(FILES
    ${CMAKE_BINARY_DIR}/qml/StarOS/System/qmldir
    ${CMAKE_BINARY_DIR}/qml/StarOS/System/staros_system.qmltypes
    DESTINATION ${module_dir}
)
