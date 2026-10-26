# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module StarOS.Welcome with its C++ type, as a static library that
# the application and the tests link.
qt_add_library(staros_welcome_ui STATIC)

set(qml_files
    qml/Main.qml
    qml/WelcomeView.qml
)
foreach(qml_file IN LISTS qml_files)
    get_filename_component(alias "${qml_file}" NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()

qt_add_qml_module(staros_welcome_ui
    URI StarOS.Welcome
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/StarOS/Welcome
    CLASS_NAME StarOS_WelcomePlugin
    IMPORT_PATH ${STAROS_SHELL_QML_DIR}
    SOURCES
        welcomestate.cpp welcomestate.h
    QML_FILES ${qml_files}
)

target_include_directories(staros_welcome_ui PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(staros_welcome_ui
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        KF6::ConfigCore
        KF6::KIOGui
        KF6::Service
)

qt_add_executable(staros-welcome main.cpp)
target_compile_definitions(staros-welcome PRIVATE STAROS_WELCOME_VERSION="${PROJECT_VERSION}")
target_link_libraries(staros-welcome PRIVATE staros_welcome_uiplugin staros_welcome_ui Qt6::Gui Qt6::Qml Qt6::Quick)

install(TARGETS staros-welcome ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
