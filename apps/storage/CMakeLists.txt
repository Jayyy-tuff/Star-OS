# SPDX-License-Identifier: GPL-3.0-or-later
#
# Star Storage (M0.4, docs/architecture/m04-apps-lens-storage-design.md
# section 6, ADR-0011): sets up a disk that keeps the live system's changes.
# The app lists disks and shows progress; the privileged work is done by
# helper/staros-storage-helper, run through pkexec under the polkit action
# org.staros.storage.manage. The QML module StarOS.Storage is compiled into
# the binary; StarOS.Shell and StarOS.System are imported at run time.

cmake_minimum_required(VERSION 3.22)

project(staros-storage VERSION 0.4.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.12.0")
set(KF_MIN_VERSION "6.31.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick)

qt_policy(SET QTP0001 NEW)

set(STAROS_SHELL_QML_DIR "${PROJECT_SOURCE_DIR}/../../shell/qml"
    CACHE PATH "Directory that contains StarOS/Shell/qmldir")
get_filename_component(STAROS_SHELL_QML_DIR "${STAROS_SHELL_QML_DIR}" ABSOLUTE)

# Where pkexec finds the helper; the polkit action names this path.
set(STAROS_STORAGE_HELPER "${CMAKE_INSTALL_PREFIX}/lib/staros/staros-storage-helper")

add_subdirectory(src)

if(BUILD_TESTING)
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test QuickTest)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    add_subdirectory(tests)
endif()

install(PROGRAMS helper/staros-storage-helper DESTINATION lib/staros)
install(FILES org.staros.storage.policy DESTINATION ${KDE_INSTALL_DATADIR}/polkit-1/actions)
install(FILES org.staros.storage.desktop DESTINATION ${KDE_INSTALL_APPDIR})
