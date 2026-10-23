# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module StarOS.Storage with its C++ backend, as a static library that
# the application and the tests link.
qt_add_library(staros_storage_ui STATIC)

set(qml_files
    qml/DiskRow.qml
    qml/Main.qml
    qml/StorageView.qml
)
foreach(qml_file IN LISTS qml_files)
    get_filename_component(alias "${qml_file}" NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()

qt_add_qml_module(staros_storage_ui
    URI StarOS.Storage
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/StarOS/Storage
    CLASS_NAME StarOS_StoragePlugin
    IMPORT_PATH ${STAROS_SHELL_QML_DIR}
    SOURCES
        storagebackend.cpp storagebackend.h
    QML_FILES ${qml_files}
)

target_include_directories(staros_storage_ui PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(staros_storage_ui PRIVATE STAROS_STORAGE_HELPER="${STAROS_STORAGE_HELPER}")
target_link_libraries(staros_storage_ui
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
)

qt_add_executable(staros-storage main.cpp)
target_compile_definitions(staros-storage PRIVATE STAROS_STORAGE_VERSION="${PROJECT_VERSION}")
target_link_libraries(staros-storage PRIVATE staros_storage_uiplugin Qt6::Gui Qt6::Qml)

install(TARGETS staros-storage ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
