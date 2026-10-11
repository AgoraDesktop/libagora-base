#===----------------------------------------------------------------------===#
#
# Agora's build for Foundation (libagora-base).
#
# Foundation lives at this repository's root (imported from the Fiwix tree --
# see PROVENANCE.md). It is compiled with clang against:
#
#   * the Objective-C runtime, `libagora-objc` (find_package(libobjc CONFIG),
#     the `objc` target);
#   * Core Foundation, `libagora-core` (find_package(CoreFoundation CONFIG));
#   * libdispatch, `libagora-dispatch` (find_package(dispatch CONFIG));
#   * the system ICU and zlib.
#
# The source list is the subset of `.m` files the Fiwix tree actually compiles;
# the rest are staged headers with no implementation yet. It will grow as Agora
# implements them.
#
# The library's ownership is MANUAL -- no ARC -- matching the Fiwix policy (ARC
# is for code that *uses* Foundation, not for Foundation itself).
#
#===----------------------------------------------------------------------===#

cmake_minimum_required(VERSION 3.24)

project(AgoraBase LANGUAGES C OBJC ASM)

# The toll-free bridge is a JOINT property of this component and libagora-core, and the only
# thing that can see the pairing is a consumer of both -- see tests/bridges.m.
enable_testing()

include(GNUInstallDirs)

set(CMAKE_POSITION_INDEPENDENT_CODE YES)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
find_package(libobjc CONFIG REQUIRED)          # -> objc
find_package(CoreFoundation CONFIG REQUIRED)   # -> CoreFoundation::CoreFoundation
find_package(dispatch CONFIG REQUIRED)         # -> dispatch
find_package(ICU REQUIRED COMPONENTS uc i18n data)
find_package(ZLIB REQUIRED)
find_package(CURL REQUIRED)   # NSURLConnection/NSURLSession
# The system OpenSSL, on the same terms as the system ICU above: Agora does not vendor or pin a
# TLS library. FNWebSocketHandshake.m needs SHA1 and RAND_bytes from libcrypto.
find_package(OpenSSL REQUIRED)

# ---------------------------------------------------------------------------
# Include shim: the headers are included as <Foundation/...> but live at this
# repository's root, so expose the root as a `Foundation/` directory.
# ---------------------------------------------------------------------------
set(_agora_include_dir "${CMAKE_BINARY_DIR}/agora-include")
file(REMOVE_RECURSE "${_agora_include_dir}")
file(MAKE_DIRECTORY "${_agora_include_dir}")
file(CREATE_LINK "${CMAKE_CURRENT_SOURCE_DIR}" "${_agora_include_dir}/Foundation" SYMBOLIC)

# Core Graphics' headers are included as <CoreGraphics/...> and live in the sibling
# libagora-drawing component. Foundation needs only the geometry TYPES, which are
# header-only (structs plus the CG_INLINE makers), so that component is not linked yet.
set(AGORA_DRAWING_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../libagora-drawing"
    CACHE PATH "Source directory of the libagora-drawing component")
file(CREATE_LINK "${AGORA_DRAWING_DIR}" "${_agora_include_dir}/CoreGraphics" SYMBOLIC)

# ---------------------------------------------------------------------------
# The library
# ---------------------------------------------------------------------------
# EVERY .m IN THE DIRECTORY IS COMPILED IN, as Fiwix's own build does (its Foundation
# rules are generated "one rule per source from the directory listing"), so a new
# translation unit needs no edit here.
file(GLOB FOUNDATION_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.m")

# AGORA: EVERY LIBRARY IN THIS TREE IS SHARED. A consumer loads the whole .so, so an
# Objective-C category in it is registered whether or not anything references its symbols
# (a static archive drops such members and the categories silently stop answering) and a
# single copy of the runtime state is shared instead of one per binary. See README.md.
option(BUILD_SHARED_LIBS "Build shared libraries" ON)

add_library(Foundation SHARED
    ${FOUNDATION_SOURCES}
    plist.c
    NSInvocation_amd64.S)

set_target_properties(Foundation PROPERTIES OUTPUT_NAME agora-base)

# AGORA: THE OBJECTIVE-C RUNTIME IS A USAGE REQUIREMENT. A consumer of Foundation compiles Objective-C
# against the same runtime this library was built with; without this, clang falls back to the legacy
# GNUstep ABI and emits __objc_class_name_* references that libobjc2 does not define -- a link error in
# the consumer, with nothing in this library's own build to show for it. Found by the test suite on its
# first run.
target_compile_options(Foundation INTERFACE
    "-fobjc-runtime=gnustep-2.0"
    "-fblocks")

# THE SHIM GOES IN THE BUILD INTERFACE AND THE PREFIX IN THE INSTALL ONE, WHICH IS WHAT MAKES THIS TARGET
# EXPORTABLE AT ALL. A path inside the build tree cannot be put in an installed target's interface -- CMake
# refuses the export outright, saying so: "INTERFACE_INCLUDE_DIRECTORIES property contains path: ... which is
# prefixed in the build directory" -- and a consumer of the installed library needs ${INCLUDEDIR}, where
# these headers land under Foundation/. libagora-drawing has spelled it this way all along.
target_include_directories(Foundation
    PUBLIC
        "$<BUILD_INTERFACE:${_agora_include_dir}>"
        "$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>")

# plist.h sits beside the sources, not under Foundation/.
target_include_directories(Foundation PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

target_compile_options(Foundation PRIVATE
    -fobjc-runtime=gnustep-2.0
    -fblocks
    -Wno-objc-missing-super-calls
    -Wno-incomplete-implementation
    -Wno-objc-root-class)

target_link_libraries(Foundation
    PUBLIC
        CoreFoundation::CoreFoundation
    PRIVATE
        objc
        dispatch
        ICU::uc ICU::i18n ICU::data
        ZLIB::ZLIB
        CURL::libcurl
        OpenSSL::Crypto)

add_subdirectory(tests)

install(DIRECTORY . DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/Foundation
        FILES_MATCHING PATTERN "*.h")
install(TARGETS Foundation
    EXPORT FoundationTargets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

# ---------------------------------------------------------------------------
# AND IT IS EXPORTED, WHICH IT WAS NOT. Foundation installed its headers and its
# library and no CMake package at all, so `find_package(Foundation)` could not be
# written and a consumer had to spell the include and link paths out by hand --
# exactly the state libagora-drawing was in until a client was written against it.
#
# CORE FOUNDATION IS A PUBLIC DEPENDENCY HERE FOR THE SAME REASON IT IS IN THE
# DRAWING LIBRARY: a consumer of Foundation reaches Core Foundation itself --
# CFStringRef for a format, CFTypeID to ask what a bridged object is -- and a
# target that kept it PRIVATE would fail to link with "DSO missing from command
# line" at the first such call, which is how that was found there.
# ---------------------------------------------------------------------------
include(CMakePackageConfigHelpers)

install(EXPORT FoundationTargets
    FILE FoundationTargets.cmake
    NAMESPACE Foundation::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Foundation)

configure_package_config_file(cmake/FoundationConfig.cmake.in
    ${CMAKE_CURRENT_BINARY_DIR}/FoundationConfig.cmake
    INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Foundation)
write_basic_package_version_file(
    ${CMAKE_CURRENT_BINARY_DIR}/FoundationConfigVersion.cmake
    VERSION 1.0.0
    COMPATIBILITY SameMajorVersion)
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/FoundationConfig.cmake
    ${CMAKE_CURRENT_BINARY_DIR}/FoundationConfigVersion.cmake
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/Foundation)
