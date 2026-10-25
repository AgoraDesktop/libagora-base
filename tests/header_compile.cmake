# The header-compile gate: every public header stands alone, in three client modes.
#
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-License-Identifier: LGPL-3.0-or-later
#
# usage: cmake -DCLANG=<clang> -DSOURCE_DIR=<libagora-base> -DINCLUDE=<dir>[;<dir>...] -DWORK=<dir> \
#              -P header_compile.cmake
#
# **WHY THIS GATE EXISTS AND WHY IT IS NOT THE LIBRARY BUILD.** The library compiles because every `.m` imports the
# umbrella or a set of headers in an order that happens to satisfy each one. A CLIENT imports ONE header — that is
# what `<Foundation/NSFastEnumeration.h>` means — and five headers had never been asked to stand alone: two declared
# nothing (NSFastEnumeration.h imported no header at all), one used a class it only forward-declared as a category
# host, one named `NSMutableArray` without declaring it, and one conformed to `NSObject` without the protocol.
# COCOA-10.11-SURFACE-PLAN.md's S5 tier is source compatibility, so this is where "a program written against the
# 10.11 headers builds" starts.
#
# THREE MODES, BECAUSE THREE KINDS OF CLIENT EXIST. Objective-C, Objective-C++ (a header that declares a struct with
# an Objective-C object in it compiles differently in C++), and ARC — the headers are the same either way and ARC
# rejects some spellings an MRC build accepts. The library itself is manual-retain-release; that is a fact about the
# implementation, not about the interface.
#
# THE UMBRELLA IS COMPILED TOO, once per mode, because "each header alone" does not catch two headers that collide
# when both are in scope (a duplicate typedef, two nullability regions opening and closing in the wrong order).

if(NOT CLANG OR NOT SOURCE_DIR OR NOT INCLUDE OR NOT WORK)
  message(FATAL_ERROR "header_compile.cmake needs -DCLANG, -DSOURCE_DIR, -DINCLUDE and -DWORK")
endif()

file(GLOB headers RELATIVE "${SOURCE_DIR}" "${SOURCE_DIR}/*.h")
list(SORT headers)
if(NOT headers)
  message(FATAL_ERROR "header_compile.cmake: no headers in ${SOURCE_DIR}")
endif()

set(include_args "")
foreach(directory IN LISTS INCLUDE)
  if(NOT IS_DIRECTORY "${directory}")
    # An include directory that does not exist is a silent false negative — every header would fail and the message
    # would blame the headers. Fail with the real reason instead.
    message(FATAL_ERROR "header_compile.cmake: include directory does not exist: ${directory}")
  endif()
  list(APPEND include_args "-I${directory}")
endforeach()

file(MAKE_DIRECTORY "${WORK}")
set(base_flags -fobjc-runtime=gnustep-2.0 -fblocks)

# mode -> (language, extra flags, source extension)
set(modes objc objcxx arc)
set(lang_objc objective-c)
set(lang_objcxx objective-c++)
set(lang_arc objective-c)
set(ext_objc m)
set(ext_objcxx mm)
set(ext_arc m)
set(flags_arc -fobjc-arc)

set(failures "")
set(compiled 0)

foreach(mode IN LISTS modes)
  foreach(header ${headers} Foundation.h)
    if(header STREQUAL "Foundation.h" AND NOT EXISTS "${SOURCE_DIR}/Foundation.h")
      continue()
    endif()
    set(probe "${WORK}/probe-${mode}.${ext_${mode}}")
    file(WRITE "${probe}" "#import <Foundation/${header}>\n")
    execute_process(
      COMMAND "${CLANG}" -x ${lang_${mode}} ${base_flags} ${flags_${mode}} -fsyntax-only
              ${include_args} "${probe}"
      RESULT_VARIABLE result OUTPUT_QUIET ERROR_VARIABLE error_text)
    if(result EQUAL 0)
      math(EXPR compiled "${compiled} + 1")
    else()
      # The first error line, not the whole diagnostic block: a header that fails usually fails once and then cascades.
      string(REGEX MATCH "[^\n]*error:[^\n]*" first_error "${error_text}")
      if(NOT first_error)
        string(REGEX MATCH "[^\n]*" first_error "${error_text}")
      endif()
      string(REPLACE "${WORK}/" "" first_error "${first_error}")
      list(APPEND failures "  ${mode}  ${header}  ${first_error}")
    endif()
  endforeach()
endforeach()

list(LENGTH headers header_count)
math(EXPR expected "${header_count} * 3 + 3")
if(failures)
  list(LENGTH failures failure_count)
  string(REPLACE ";" "\n" failure_text "${failures}")
  message(FATAL_ERROR
    "The header-compile gate failed, in ${failure_count} of ${expected} compilation(s).\n"
    "${failure_text}\n"
    "\n"
    "A public header must stand alone: it imports what it names, and it compiles as Objective-C, Objective-C++ and\n"
    "under ARC. The umbrella is compiled too, once per mode, because two headers that are individually fine can\n"
    "still collide when both are in scope.")
endif()

# The count is printed whole, not as a total: the number of headers is itself a surface, and a header that quietly
# stopped being globbed (a rename, a move) would otherwise lower the work without failing anything.
message(STATUS
  "header compile holds: ${header_count} headers alone in 3 modes, plus the umbrella in each (${compiled} compilations)")
