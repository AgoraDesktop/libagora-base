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

target_include_directories(Foundation PUBLIC "${_agora_include_dir}")

# plist.h sits beside the sources, not under Foundation/.
target_include_directories(Foundation PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")

target_compile_options(Foundation PRIVATE
    -fobjc-runtime=gnustep-2.0
    -fblocks
    -Wno-objc-missing-super-calls
    -Wno-incomplete-implementation
    -Wno-objc-root-class)

target_link_libraries(Foundation
    PRIVATE
        objc
        CoreFoundation::CoreFoundation
        dispatch
        ICU::uc ICU::i18n ICU::data
        ZLIB::ZLIB
        CURL::libcurl
        OpenSSL::Crypto)

install(DIRECTORY . DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/Foundation
        FILES_MATCHING PATTERN "*.h")
install(TARGETS Foundation
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
