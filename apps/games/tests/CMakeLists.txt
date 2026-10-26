# SPDX-License-Identifier: GPL-3.0-or-later

# The library sees only its own desktop files: a "system" and a Flatpak
# export directory under the build tree (on XDG_DATA_DIRS), and the
# test-mode user data. Nothing is started.
set(games_data ${CMAKE_CURRENT_BINARY_DIR}/games-data)

add_executable(tst_gamelibrary tst_gamelibrary.cpp)
target_link_libraries(tst_gamelibrary PRIVATE staros_games_ui Qt6::Test)
add_test(NAME tst_gamelibrary COMMAND tst_gamelibrary)
set_tests_properties(tst_gamelibrary PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_CURRENT_DESKTOP=KDE;STAROS_TEST_DATA=${games_data};XDG_DATA_DIRS=${games_data}/system:${games_data}/flatpak/exports/share;DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/staros-games-test"
    TIMEOUT 120)

# The view with a test double (Qt Quick Test, tests in qml/).
add_executable(tst_gameview tst_gameview.cpp)
target_compile_definitions(tst_gameview PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}"
)
target_link_libraries(tst_gameview PRIVATE staros_games_uiplugin Qt6::Qml Qt6::QuickTest)
add_test(NAME tst_gameview COMMAND tst_gameview)
set_tests_properties(tst_gameview PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/staros-games-test"
    TIMEOUT 180)

find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_test(NAME desktop_file
        COMMAND ${DESKTOP_FILE_VALIDATE} ${PROJECT_SOURCE_DIR}/org.staros.games.desktop)
else()
    message(STATUS "desktop-file-validate not found: the desktop file is not checked")
endif()
