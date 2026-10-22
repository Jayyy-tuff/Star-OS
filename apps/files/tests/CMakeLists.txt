# SPDX-License-Identifier: GPL-3.0-or-later

# Every test runs headless: the offscreen platform and Qt Quick's software
# scene graph (on which GlassSurface draws its opaque fallback).
set(headless_env
    QT_QPA_PLATFORM=offscreen
    QT_QUICK_BACKEND=software
)

# Model and operations against the real KIO, on temporary folders.
foreach(test_name tst_foldermodel tst_fileoperations tst_placesmodel)
    add_executable(${test_name} ${test_name}.cpp)
    target_link_libraries(${test_name} PRIVATE staros_files_ui Qt6::Test)
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

# The view with test doubles (Qt Quick Test, tests in qml/), and the real
# window. Both link StarOS.Files and load StarOS.Shell from the repository.
add_executable(tst_filesview tst_filesview.cpp)
target_compile_definitions(tst_filesview PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}"
)
target_link_libraries(tst_filesview PRIVATE staros_files_uiplugin Qt6::Qml Qt6::QuickTest)
add_test(NAME tst_filesview COMMAND tst_filesview)

add_executable(tst_mainwindow tst_mainwindow.cpp)
target_compile_definitions(tst_mainwindow PRIVATE STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}")
target_link_libraries(tst_mainwindow PRIVATE staros_files_uiplugin Qt6::Quick Qt6::Test)
add_test(NAME tst_mainwindow COMMAND tst_mainwindow)

set_tests_properties(tst_foldermodel tst_fileoperations tst_placesmodel tst_filesview tst_mainwindow
    PROPERTIES ENVIRONMENT "${headless_env}" TIMEOUT 180
)

find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_test(NAME desktop_file
        COMMAND ${DESKTOP_FILE_VALIDATE} ${PROJECT_SOURCE_DIR}/org.staros.files.desktop)
else()
    message(STATUS "desktop-file-validate not found: the desktop file is not checked")
endif()
