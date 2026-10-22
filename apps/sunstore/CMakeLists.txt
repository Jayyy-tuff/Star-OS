# SPDX-License-Identifier: GPL-3.0-or-later
#
# Sun Store (M0.3, docs/architecture/m03-glass-files-store-design.md section 3,
# ADR-0010): a Qt Quick store for Flatpak apps from Flathub, installed per user
# through the flatpak command line. The QML module StarOS.SunStore is compiled
# into the binary; StarOS.Shell is imported at run time from the shell tree.

cmake_minimum_required(VERSION 3.22)

project(staros-sunstore VERSION 0.3.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.12.0")
set(KF_MIN_VERSION "6.31.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick)
find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS Archive)

qt_policy(SET QTP0001 NEW)

set(STAROS_SHELL_QML_DIR "${PROJECT_SOURCE_DIR}/../../shell/qml"
    CACHE PATH "Directory that contains StarOS/Shell/qmldir")
get_filename_component(STAROS_SHELL_QML_DIR "${STAROS_SHELL_QML_DIR}" ABSOLUTE)

add_subdirectory(src)

if(BUILD_TESTING)
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test QuickTest)
    add_subdirectory(tests)
endif()

install(FILES org.staros.sunstore.desktop DESTINATION ${KDE_INSTALL_APPDIR})
