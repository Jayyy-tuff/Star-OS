# SPDX-License-Identifier: GPL-3.0-or-later

# Every test runs headless: the offscreen platform and Qt Quick's software
# scene graph.
set(headless_env
    QT_QPA_PLATFORM=offscreen
    QT_QUICK_BACKEND=software
)

# The privileged helper: which disks it offers, what it refuses and the exact
# commands it would run (nothing is run).
add_test(NAME helper COMMAND ${Python3_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/test_helper.py)

# The backend with stand-ins for the helper and pkexec (shell scripts the test
# writes).
add_executable(tst_backend tst_backend.cpp)
target_link_libraries(tst_backend PRIVATE staros_storage_ui Qt6::Test)
add_test(NAME tst_backend COMMAND tst_backend)

# The view with test doubles (Qt Quick Test, tests in qml/).
add_executable(tst_storageview tst_storageview.cpp)
target_compile_definitions(tst_storageview PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}"
)
target_link_libraries(tst_storageview PRIVATE staros_storage_uiplugin Qt6::Qml Qt6::QuickTest)
add_test(NAME tst_storageview COMMAND tst_storageview)

# The real window, which needs StarOS.System (the staros-system package).
add_executable(tst_mainwindow tst_mainwindow.cpp)
target_compile_definitions(tst_mainwindow PRIVATE STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}")
target_link_libraries(tst_mainwindow PRIVATE staros_storage_uiplugin Qt6::Quick Qt6::Test)
add_test(NAME tst_mainwindow COMMAND tst_mainwindow)

set_tests_properties(tst_backend tst_storageview tst_mainwindow
    PROPERTIES ENVIRONMENT "${headless_env}" TIMEOUT 180
)

find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_test(NAME desktop_file
        COMMAND ${DESKTOP_FILE_VALIDATE} ${PROJECT_SOURCE_DIR}/org.staros.storage.desktop)
else()
    message(STATUS "desktop-file-validate not found: the desktop file is not checked")
endif()
