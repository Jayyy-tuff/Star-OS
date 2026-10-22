# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module StarOS.SunStore with its C++ types, as a static library that
# the application and the tests link.
qt_add_library(staros_sunstore_ui STATIC)

set(qml_files
    qml/AppPage.qml
    qml/AppRow.qml
    qml/ConsentPage.qml
    qml/Main.qml
    qml/StoreButton.qml
    qml/StoreTextField.qml
    qml/StoreView.qml
)
foreach(qml_file IN LISTS qml_files)
    get_filename_component(alias "${qml_file}" NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()

qt_add_qml_module(staros_sunstore_ui
    URI StarOS.SunStore
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/StarOS/SunStore
    CLASS_NAME StarOS_SunStorePlugin
    IMPORT_PATH ${STAROS_SHELL_QML_DIR}
    SOURCES
        appsmodel.cpp appsmodel.h
        appstream.cpp appstream.h
        flatpakcli.cpp flatpakcli.h
        flatpakoutput.cpp flatpakoutput.h
        store.cpp store.h
    QML_FILES ${qml_files}
)

target_include_directories(staros_sunstore_ui PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(staros_sunstore_ui PRIVATE
    STAROS_SUNSTORE_FLATHUB_REPO="${KDE_INSTALL_FULL_DATADIR}/staros-sunstore/flathub.flatpakrepo"
)
target_link_libraries(staros_sunstore_ui
    PUBLIC
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        KF6::Archive
)

qt_add_executable(staros-sunstore main.cpp)
target_compile_definitions(staros-sunstore PRIVATE STAROS_SUNSTORE_VERSION="${PROJECT_VERSION}")
target_link_libraries(staros-sunstore PRIVATE staros_sunstore_uiplugin Qt6::Gui Qt6::Qml)

install(TARGETS staros-sunstore ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
