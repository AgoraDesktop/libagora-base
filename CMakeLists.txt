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
add_library(Foundation
    FNAuthenticationChallengeSender.m
    FNCURLURLProtocol.m
    FNPointerTable.m
    FNTextBreaking.m
    FNURLComponents.m
    FNWebSocketHandshake.m
    NSArray.m
    NSAttributedString.m
    NSBlockOperation.m
    NSBundle.m
    NSCache.m
    NSCachedURLResponse.m
    NSCalendar.m
    NSCharacterSet.m
    NSCoder.m
    NSCountedSet.m
    NSData.m
    NSDataCodec.m
    NSDataDetector.m
    NSDate.m
    NSDateComponents.m
    NSDateComponentsFormatter.m
    NSDateFormatter.m
    NSDateInterval.m
    NSDateIntervalFormatter.m
    NSDecimalNumber.m
    NSDictionary.m
    NSDirectoryEnumerator.m
    NSDistributedNotificationCenter.m
    NSEnergyFormatter.m
    NSEnumerator.m
    NSError.m
    NSException.m
    NSFileCoordinator.m
    NSFileManager.m
    NSFileProviderService.m
    NSFileSecurity.m
    NSFileVersion.m
    NSFileWrapper.m
    NSFormatter.m
    NSGeometry.m
    NSHTTPURLResponse.m
    NSHashTable.m
    NSISO8601DateFormatter.m
    NSIndexPath.m
    NSIndexSet.m
    NSInvocation.m
    NSInvocationOperation.m
    NSKeyValueCoding.m
    NSKeyValueObserving.m
    NSKeyedArchiver.m
    NSLengthFormatter.m
    NSLinguisticTagger.m
    NSLocale.m
    NSLock.m
    NSMapTable.m
    NSMassFormatter.m
    NSMethodSignature.m
    NSNull.m
    NSNumber.m
    NSNumberFormatter.m
    NSObject.m
    NSOperation.m
    NSOrderedSet.m
    NSOrthography.m
    NSPointerArray.m
    NSPointerFunctions.m
    NSProcessInfo.m
    NSPropertyListSerialization.m
    NSPurgeableData.m
    NSRegularExpression.m
    NSRelativeDateTimeFormatter.m
    NSRunLoop.m
    NSScanner.m
    NSSecureUnarchiveFromDataTransformer.m
    NSSet.m
    NSSortDescriptor.m
    NSString.m
    NSTextCheckingResult.m
    NSThread.m
    NSTimeZone.m
    NSTinyString.m
    NSURL.m
    NSURLConnection.m
    NSURLError.m
    NSURLHandle.m
    NSURLProtocol.m
    NSURLRequest.m
    NSURLResponse.m
    NSValue.m
    NSXMLDTD.m
    NSXMLDocument.m
    NSXMLNode.m
    NSXMLParser.m
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
        ZLIB::ZLIB)

install(DIRECTORY . DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/Foundation
        FILES_MATCHING PATTERN "*.h")
install(TARGETS Foundation
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
