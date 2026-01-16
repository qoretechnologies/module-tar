cmake_minimum_required(VERSION 3.5.0)

project(qore-tar-module)

set(VERSION_MAJOR 1)
set(VERSION_MINOR 0)
set(VERSION_PATCH 0)

set(PROJECT_VERSION "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}")

if (${CMAKE_VERSION} VERSION_GREATER_EQUAL "3.12.0")
    cmake_policy(SET CMP0074 NEW)

    if (${CMAKE_VERSION} VERSION_GREATER_EQUAL "3.18.0")
        cmake_policy(SET CMP0053 NEW)
    endif()
endif()

cmake_policy(SET CMP0042 NEW)

if (UNIX AND NOT APPLE)
    set(LINUX TRUE)
endif()

find_package(Qore 2.0 REQUIRED)

# Find libarchive (required)
find_package(LibArchive REQUIRED)

# Find OpenSSL for encryption support
find_package(OpenSSL)

# Check for C++11.
include(CheckCXXCompilerFlag)
CHECK_CXX_COMPILER_FLAG("-std=c++11" COMPILER_SUPPORTS_CXX11)
if(COMPILER_SUPPORTS_CXX11)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")
else()
    message(FATAL_ERROR "The compiler ${CMAKE_CXX_COMPILER} has no C++11 support. Please use a different C++ compiler.")
endif()

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(QPP_SRC
    src/QC_TarFile.qpp
    src/QC_TarEntry.qpp
    src/QC_TarInputStream.qpp
    src/QC_TarOutputStream.qpp
)

set(CPP_SRC
    src/tar-module.cpp
    src/QoreTarFile.cpp
    src/TarInputStream.cpp
    src/TarOutputStream.cpp
)

qore_wrap_qpp_value(QPP_SOURCES ${QPP_SRC})

foreach (it ${QPP_SOURCES})
    GET_FILENAME_COMPONENT(_outfile ${it} NAME_WE)
    set(QPP_DOX ${QPP_DOX} ${CMAKE_CURRENT_BINARY_DIR}/${_outfile}.dox.h)
endforeach()

set(module_name "tar")

set(QMOD
    qlib/TarDataProvider
)

set(QORE_DOX_TMPL_SRC
  docs/mainpage.dox.tmpl
)

add_library(${module_name} MODULE ${CPP_SRC} ${QPP_SOURCES})

include_directories(${CMAKE_SOURCE_DIR}/src)
include_directories(${LibArchive_INCLUDE_DIRS})
target_include_directories(${module_name} PRIVATE $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>)

add_custom_target(QORE_INC_FILES DEPENDS ${QORE_INC_SRC})
add_dependencies(${module_name} QORE_INC_FILES)

target_link_libraries(${module_name} ${LibArchive_LIBRARIES} ${QORE_LIBRARY})

# Link CoreFoundation on macOS for Unicode normalization support
if(APPLE)
    target_link_libraries(${module_name} "-framework CoreFoundation")
endif()

if(OPENSSL_FOUND)
    target_compile_definitions(${module_name} PRIVATE HAVE_OPENSSL)
    target_include_directories(${module_name} PRIVATE ${OPENSSL_INCLUDE_DIR})
    target_link_libraries(${module_name} ${OPENSSL_LIBRARIES})
endif()

set(MODULE_DOX_INPUT ${CMAKE_CURRENT_BINARY_DIR}/mainpage.dox ${QPP_DOX})
string(REPLACE ";" " " MODULE_DOX_INPUT "${MODULE_DOX_INPUT}")

if (DEFINED ENV{DOXYGEN_EXECUTABLE})
    set(DOXYGEN_EXECUTABLE $ENV{DOXYGEN_EXECUTABLE})
endif()

set(DOXYGEN_IMAGE_PATH "${CMAKE_SOURCE_DIR}/docs/images" CACHE STRING "Doxygen image path" FORCE)
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/images")
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/doxygen/qlib/TarDataProvider")
file(WRITE
    "${CMAKE_BINARY_DIR}/doxygen/qlib/TarDataProvider/tar-logo.svg.dox.h"
    "/** @file tar-logo.svg.dox.h\n    @brief TAR DataProvider logo file.\n*/\n"
)
set(MODULE_DOX_INPUT ${CMAKE_BINARY_DIR})
qore_external_binary_module(${module_name} ${PROJECT_VERSION})

qore_dist(${PROJECT_VERSION})

qore_user_modules("${QMOD}")
qore_external_user_module("qlib/TarDataProvider" "")

qore_config_info()

if (DOXYGEN_FOUND)
    qore_wrap_dox(QORE_DOX_SRC ${QORE_DOX_TMPL_SRC})
    add_custom_target(QORE_MOD_DOX_FILES DEPENDS ${QORE_DOX_SRC})
    add_dependencies(docs-module QORE_MOD_DOX_FILES)
endif()
