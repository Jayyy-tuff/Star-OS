# SPDX-License-Identifier: GPL-3.0-or-later

# Every test runs headless: the offscreen platform and Qt Quick's software
# scene graph (on which GlassSurface draws its opaque fallback). None of them
# uses the network or the real flatpak: tst_store and tst_mainwindow run a fake
# flatpak script that they write into a temporary folder.
set(headless_env
    QT_QPA_PLATFORM=offscreen
    QT_QUICK_BACKEND=software
)

foreach(test_name tst_parsers tst_appstream tst_store)
    add_executable(${test_name} ${test_name}.cpp)
    target_compile_definitions(${test_name} PRIVATE SUNSTORE_TEST_DATA="${CMAKE_CURRENT_SOURCE_DIR}/data")
    target_link_libraries(${test_name} PRIVATE staros_sunstore_ui Qt6::Test)
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

# The view with a fake store (Qt Quick Test, tests in qml/), and the real
# window with a fake flatpak. Both load StarOS.Shell from the repository.
add_executable(tst_storeview tst_storeview.cpp)
target_compile_definitions(tst_storeview PRIVATE
    QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}"
)
target_link_libraries(tst_storeview PRIVATE staros_sunstore_uiplugin Qt6::Qml Qt6::QuickTest)
add_test(NAME tst_storeview COMMAND tst_storeview)

add_executable(tst_mainwindow tst_mainwindow.cpp)
target_compile_definitions(tst_mainwindow PRIVATE STAROS_SHELL_QML_DIR="${STAROS_SHELL_QML_DIR}")
target_link_libraries(tst_mainwindow PRIVATE staros_sunstore_uiplugin Qt6::Quick Qt6::Test)
add_test(NAME tst_mainwindow COMMAND tst_mainwindow)

set_tests_properties(tst_parsers tst_appstream tst_store tst_storeview tst_mainwindow
    PROPERTIES ENVIRONMENT "${headless_env}" TIMEOUT 180
)

find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_test(NAME desktop_file
        COMMAND ${DESKTOP_FILE_VALIDATE} ${PROJECT_SOURCE_DIR}/org.staros.sunstore.desktop)
else()
    message(STATUS "desktop-file-validate not found: the desktop file is not checked")
endif()
