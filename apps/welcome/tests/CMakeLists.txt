# SPDX-License-Identifier: GPL-3.0-or-later

# Headless: the offscreen platform and Qt Quick's software scene graph; no
# session bus, and nothing is started.
set(headless_env
    QT_QPA_PLATFORM=offscreen
    QT_QUICK_BACKEND=software
    DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/staros-welcome-test
)

add_executable(tst_welcomestate tst_welcomestate.cpp)
target_link_libraries(tst_welcomestate PRIVATE staros_welcome_ui Qt6::Test)
add_test(NAME tst_welcomestate COMMAND tst_welcomestate)

# The view with a test double (Qt Quick Test, tests in qml/).
add_executable(tst_welcomeview tst_welcomeview.cpp)
target_compile_definitions(tst_welcomeview PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}"
)
target_link_libraries(tst_welcomeview PRIVATE staros_welcome_uiplugin Qt6::Qml Qt6::QuickTest)
add_test(NAME tst_welcomeview COMMAND tst_welcomeview)

set_tests_properties(tst_welcomestate tst_welcomeview PROPERTIES ENVIRONMENT "${headless_env}" TIMEOUT 120)

find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_test(NAME desktop_file
        COMMAND ${DESKTOP_FILE_VALIDATE} ${PROJECT_SOURCE_DIR}/org.staros.welcome.desktop)
    add_test(NAME autostart_file
        COMMAND ${DESKTOP_FILE_VALIDATE} ${PROJECT_SOURCE_DIR}/org.staros.welcome.autostart.desktop)
else()
    message(STATUS "desktop-file-validate not found: the desktop files are not checked")
endif()
