# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module StarOS.Games with its C++ types, as a static library that the
# application and the tests link.
qt_add_library(staros_games_ui STATIC)

set(qml_files
    qml/GameCenterView.qml
    qml/GameTile.qml
    qml/Main.qml
)
foreach(qml_file IN LISTS qml_files)
    get_filename_component(alias "${qml_file}" NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()

qt_add_qml_module(staros_games_ui
    URI StarOS.Games
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/StarOS/Games
    CLASS_NAME StarOS_GamesPlugin
    IMPORT_PATH ${STAROS_SHELL_QML_DIR}
    SOURCES
        gamelibrary.cpp gamelibrary.h
        steamlibrary.cpp steamlibrary.h
        themeiconprovider.cpp themeiconprovider.h
    QML_FILES ${qml_files}
)

target_include_directories(staros_games_ui PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(staros_games_ui
    PUBLIC
        Qt6::Core
        Qt6::DBus
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        KF6::ConfigCore
        KF6::KIOGui
        KF6::Service
)

qt_add_executable(staros-games main.cpp)
target_compile_definitions(staros-games PRIVATE STAROS_GAMES_VERSION="${PROJECT_VERSION}")
target_link_libraries(staros-games PRIVATE staros_games_uiplugin staros_games_ui Qt6::Gui Qt6::Qml Qt6::Quick)

install(TARGETS staros-games ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
