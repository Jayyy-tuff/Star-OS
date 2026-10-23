# SPDX-License-Identifier: GPL-3.0-or-later

# The QML module StarOS.Lens with its C++ types, as a static library that the
# application and the tests link.
qt_add_library(staros_lens_ui STATIC)

set(qml_files
    qml/LensDialog.qml
    qml/LensView.qml
    qml/Main.qml
    qml/ResultsPanel.qml
)
foreach(qml_file IN LISTS qml_files)
    get_filename_component(alias "${qml_file}" NAME)
    set_source_files_properties(${qml_file} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()

qt_add_qml_module(staros_lens_ui
    URI StarOS.Lens
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/StarOS/Lens
    CLASS_NAME StarOS_LensPlugin
    IMPORT_PATH ${STAROS_SHELL_QML_DIR}
    SOURCES
        captureprovider.cpp captureprovider.h
        lensbackend.cpp lensbackend.h
        recognizer.cpp recognizer.h
    QML_FILES ${qml_files}
)

target_include_directories(staros_lens_ui PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(staros_lens_ui
    PUBLIC
        Qt6::Core
        Qt6::Concurrent
        Qt6::DBus
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        KF6::GuiAddons
        KF6::KIOGui
        KF6::PrisonScanner
)

qt_add_executable(staros-lens main.cpp)
target_compile_definitions(staros-lens PRIVATE STAROS_LENS_VERSION="${PROJECT_VERSION}")
target_link_libraries(staros-lens PRIVATE staros_lens_uiplugin Qt6::Gui Qt6::Qml)

install(TARGETS staros-lens ${KDE_INSTALL_TARGETS_DEFAULT_ARGS})
