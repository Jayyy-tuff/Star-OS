# SPDX-License-Identifier: GPL-3.0-or-later
#
# StarOS.System (M0.4, docs/architecture/m04-apps-lens-storage-design.md
# section 3): a QML module for the shell and the apps with the system status
# (storage mode and space, memory, battery) and the sticky notes store.
# Installed as a plugin in Qt's QML directory, next to StarOS.Shell.

cmake_minimum_required(VERSION 3.22)

project(staros-system VERSION 0.4.0 LANGUAGES CXX)

set(QT_MIN_VERSION "6.12.0")
set(KF_MIN_VERSION "6.31.0")

find_package(ECM ${KF_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Qml)

qt_policy(SET QTP0001 NEW)

add_subdirectory(src)

if(BUILD_TESTING)
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)
    add_subdirectory(tests)
endif()
