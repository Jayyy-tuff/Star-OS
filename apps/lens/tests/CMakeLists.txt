# SPDX-License-Identifier: GPL-3.0-or-later

# Every test runs headless: the offscreen platform and Qt Quick's software
# scene graph. No session bus, so nothing reaches KWin.
set(headless_env
    QT_QPA_PLATFORM=offscreen
    QT_QUICK_BACKEND=software
    DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/staros-lens-test
)

# Text recognition needs the Tesseract program and its English data; the
# package's checkdepends provide them.
find_program(TESSERACT_EXECUTABLE tesseract)
if(NOT TESSERACT_EXECUTABLE)
    message(STATUS "tesseract not found: text recognition is not tested")
endif()

# Recogniser and backend, with Prison generating the QR codes they read.
foreach(test_name tst_recognizer tst_backend)
    add_executable(${test_name} ${test_name}.cpp)
    target_link_libraries(${test_name} PRIVATE staros_lens_ui KF6::Prison Qt6::Test)
    if(TESSERACT_EXECUTABLE)
        target_compile_definitions(${test_name} PRIVATE TESSERACT_EXECUTABLE="${TESSERACT_EXECUTABLE}")
    endif()
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

# The view with a test double (Qt Quick Test, tests in qml/), and the real
# window, which cannot reach KWin here and must say so.
add_executable(tst_lensview tst_lensview.cpp)
target_compile_definitions(tst_lensview PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}"
)
target_link_libraries(tst_lensview PRIVATE staros_lens_uiplugin Qt6::Qml Qt6::QuickTest)
add_test(NAME tst_lensview COMMAND tst_lensview)

add_executable(tst_mainwindow tst_mainwindow.cpp)
target_compile_definitions(tst_mainwindow PRIVATE STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}")
target_link_libraries(tst_mainwindow PRIVATE staros_lens_uiplugin Qt6::Quick Qt6::Test)
add_test(NAME tst_mainwindow COMMAND tst_mainwindow)

set_tests_properties(tst_recognizer tst_backend tst_lensview tst_mainwindow
    PROPERTIES ENVIRONMENT "${headless_env}" TIMEOUT 180
)

find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_test(NAME desktop_file
        COMMAND ${DESKTOP_FILE_VALIDATE} ${PROJECT_SOURCE_DIR}/org.staros.lens.desktop)
else()
    message(STATUS "desktop-file-validate not found: the desktop file is not checked")
endif()
