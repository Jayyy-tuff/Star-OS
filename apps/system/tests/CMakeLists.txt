# SPDX-License-Identifier: GPL-3.0-or-later

# The tests compile the module's classes directly; the plugin itself has no
# library to link.
foreach(test_name tst_systemstatus tst_notesstore tst_applicationsmodel tst_controls tst_desktopservices)
    add_executable(${test_name} ${test_name}.cpp
        ${PROJECT_SOURCE_DIR}/src/applicationsmodel.cpp
        ${PROJECT_SOURCE_DIR}/src/audiocontrol.cpp
        ${PROJECT_SOURCE_DIR}/src/clipboardhistory.cpp
        ${PROJECT_SOURCE_DIR}/src/displaycontrol.cpp
        ${PROJECT_SOURCE_DIR}/src/gamemodesetting.cpp
        ${PROJECT_SOURCE_DIR}/src/networkstatus.cpp
        ${PROJECT_SOURCE_DIR}/src/systemstatus.cpp
        ${PROJECT_SOURCE_DIR}/src/notesstore.cpp
        ${PROJECT_SOURCE_DIR}/src/widgetstore.cpp
    )
    target_include_directories(${test_name} PRIVATE ${PROJECT_SOURCE_DIR}/src)
    target_link_libraries(${test_name} PRIVATE
        Qt6::Core Qt6::DBus Qt6::Gui Qt6::Qml Qt6::Test
        KF6::ConfigCore KF6::GlobalAccel KF6::GuiAddons KF6::KIOGui KF6::PulseAudioQt KF6::Service
    )
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

# The installed layout: qmldir, type information and the plugin load.
add_test(NAME qml_import
    COMMAND ${CMAKE_COMMAND} -E env QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml
        $<TARGET_FILE:tst_qmlimport>)
add_executable(tst_qmlimport tst_qmlimport.cpp)
target_link_libraries(tst_qmlimport PRIVATE Qt6::Qml Qt6::Test)
add_dependencies(tst_qmlimport staros_system)

set_tests_properties(tst_systemstatus tst_notesstore tst_controls tst_desktopservices qml_import PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen" TIMEOUT 120)
# The applications test sees only its own desktop files: a "system" and a
# Flatpak export directory under the build tree, and the test-mode user data.
set(apps_data ${CMAKE_CURRENT_BINARY_DIR}/apps-data)
set_tests_properties(tst_applicationsmodel PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_CURRENT_DESKTOP=KDE;STAROS_TEST_DATA=${apps_data};XDG_DATA_DIRS=${apps_data}/system:${apps_data}/flatpak/exports/share"
    TIMEOUT 120)
