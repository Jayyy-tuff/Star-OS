# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module StarOS.Files with its C++ types, as a static library, so that
# the tests link the same module as the application. Linking the generated
# static plugin (staros_files_uiplugin) and Q_IMPORT_QML_PLUGIN(StarOS_FilesPlugin)
# makes the module available to a QML engine.
qt_add_library(staros_files_ui STATIC)

set(qml_files
    qml/ConfirmDialog.qml
    qml/DialogFrame.qml
    qml/FileRow.qml
    qml/FilesButton.qml
    qml/FilesTextField.qml
    qml/FilesView.qml
    qml/Main.qml
    qml/NameDialog.qml
    qml/PlaceRow.qml
    qml/TypeIcon.qml
    qml/fileinfo.js
)
# Keep the QML files at the module root in the resources (no qml/ prefix).
foreach(qml_file IN LISTS qml_files)
    get_filename_component(alias "${qml_file}" NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()

qt_add_qml_module(staros_files_ui
    URI StarOS.Files
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/StarOS/Files
    CLASS_NAME StarOS_FilesPlugin
    IMPORT_PATH ${STAROS_SHELL_QML_DIR}
    SOURCES
        fileoperations.cpp fileoperations.h
        foldermodel.cpp foldermodel.h
        placesmodel.cpp placesmodel.h
    QML_FILES ${qml_files}
)

target_include_directories(staros_files_ui PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(staros_files_ui
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        KF6::CoreAddons
        KF6::KIOCore
        KF6::KIOGui
        KF6::Service
)

qt_add_executable(staros-files main.cpp)
target_compile_definitions(staros-files PRIVATE STAROS_FILES_VERSION="${PROJECT_VERSION}")
target_link_libraries(staros-files PRIVATE staros_files_uiplugin Qt6::Gui Qt6::Qml)

install(TARGETS staros-files ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
