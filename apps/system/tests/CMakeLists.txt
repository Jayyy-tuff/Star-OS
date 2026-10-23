# SPDX-License-Identifier: GPL-3.0-or-later

# The tests compile the module's classes directly; the plugin itself has no
# library to link.
foreach(test_name tst_systemstatus tst_notesstore)
    add_executable(${test_name} ${test_name}.cpp
        ${PROJECT_SOURCE_DIR}/src/systemstatus.cpp
        ${PROJECT_SOURCE_DIR}/src/notesstore.cpp
    )
    target_include_directories(${test_name} PRIVATE ${PROJECT_SOURCE_DIR}/src)
    target_link_libraries(${test_name} PRIVATE Qt6::Core Qt6::Qml Qt6::Test)
    add_test(NAME ${test_name} COMMAND ${test_name})
endforeach()

# The installed layout: qmldir, type information and the plugin load.
add_test(NAME qml_import
    COMMAND ${CMAKE_COMMAND} -E env QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml
        $<TARGET_FILE:tst_qmlimport>)
add_executable(tst_qmlimport tst_qmlimport.cpp)
target_link_libraries(tst_qmlimport PRIVATE Qt6::Qml Qt6::Test)
add_dependencies(tst_qmlimport staros_system)

set_tests_properties(tst_systemstatus tst_notesstore qml_import PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen" TIMEOUT 120)
