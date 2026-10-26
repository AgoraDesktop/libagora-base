# The header-nullability gate: every public header's pointers state their nullability, in three client modes.
#
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-License-Identifier: LGPL-3.0-or-later
#
# usage: cmake -DCLANG=<clang> -DSOURCE_DIR=<libagora-base> -DINCLUDE=<dir>[;<dir>...] -DWORK=<dir> \
#              -DPIN=<file> -P header_nullability.cmake
#
# **WHY THIS GATE EXISTS.** COCOA-10.11-SURFACE-PLAN.md's S2 tier says an annotation is part of the surface, and
# `-Wnullability-completeness` is the compiler's own measurement of the ones a header still omits. The sweep that
# closed it is recorded in tests/api-10.11-nullability.txt: it began at 9 distinct declaration sites in 6 headers and
# is now 0. This gate is what keeps it at 0 — without it the next sweep is only as good as the session that ran it.
#
# **THE UNIT IS A DISTINCT DECLARATION SITE, NOT A WARNING LINE.** A raw line count is misleading twice over: clang
# REPEATS an included header's warnings in every probe that reaches it, and the three modes repeat each other. Nine
# distinct sites produced 423 lines that way. The gate therefore dedupes by `file:line:column` across every probe and
# every mode, and pins THAT number. The comparison is a deliberate act, the same rule the other censuses follow: a
# header that gains a pointer without a specifier moves the number and the gate says which declaration it was.
#
# **ONLY THIS TREE'S HEADERS COUNT.** The include directories hold sibling components' headers too (Core Foundation,
# Core Graphics), and a pointer without a specifier in one of those is that component's fact to state, not this one's.
# A warning is counted only when its file basename is a header in SOURCE_DIR; the rest are reported in the count of
# compilations, not as sites.
#
# THE THREE MODES ARE THE header-compile GATE'S, for the same reason: `-fobjc-arc` rejects some spellings a manual
# build accepts, and Objective-C++ reads a pointer in a struct differently. `-Wnullability` is enabled beside
# `-Wnullability-completeness` because contradictory annotations (a nullable pointer assigned a nonnull value in a
# declaration) are the same class of fact and cost nothing extra to check.

if(NOT CLANG OR NOT SOURCE_DIR OR NOT INCLUDE OR NOT WORK OR NOT PIN)
  message(FATAL_ERROR "header_nullability.cmake needs -DCLANG, -DSOURCE_DIR, -DINCLUDE, -DWORK and -DPIN")
endif()

file(GLOB headers RELATIVE "${SOURCE_DIR}" "${SOURCE_DIR}/*.h")
list(SORT headers)
if(NOT headers)
  message(FATAL_ERROR "header_nullability.cmake: no headers in ${SOURCE_DIR}")
endif()

# The pin: one `nullability-sites <n>` line, the same kind of deliberate number the ledger's pins carry.
set(pinned "")
file(STRINGS "${PIN}" pin_lines)
foreach(line IN LISTS pin_lines)
  if(line MATCHES "^nullability-sites[ \t]+([0-9]+)$")
    set(pinned "${CMAKE_MATCH_1}")
  endif()
endforeach()
if(pinned STREQUAL "")
  message(FATAL_ERROR "header_nullability.cmake: ${PIN} has no `nullability-sites <n>` line")
endif()

set(include_args "")
foreach(directory IN LISTS INCLUDE)
  if(NOT IS_DIRECTORY "${directory}")
    # The same silent-false-negative trap the header-compile gate names: a missing include directory makes every
    # header fail, and the message would blame the headers.
    message(FATAL_ERROR "header_nullability.cmake: include directory does not exist: ${directory}")
  endif()
  list(APPEND include_args "-I${directory}")
endforeach()

file(MAKE_DIRECTORY "${WORK}")
set(base_flags -fobjc-runtime=gnustep-2.0 -fblocks -Wnullability -Wnullability-completeness)

set(modes objc objcxx arc)
set(lang_objc objective-c)
set(lang_objcxx objective-c++)
set(lang_arc objective-c)
set(ext_objc m)
set(ext_objcxx mm)
set(ext_arc m)
set(flags_arc -fobjc-arc)

set(sites "")
set(compiled 0)

foreach(mode IN LISTS modes)
  foreach(header ${headers})
    set(probe "${WORK}/nullability-${mode}.${ext_${mode}}")
    file(WRITE "${probe}" "#import <Foundation/${header}>\n")
    execute_process(
      COMMAND "${CLANG}" -x ${lang_${mode}} ${base_flags} ${flags_${mode}} -fsyntax-only
              ${include_args} "${probe}"
      RESULT_VARIABLE result OUTPUT_QUIET ERROR_VARIABLE error_text)
    math(EXPR compiled "${compiled} + 1")
    if(NOT result EQUAL 0)
      string(REGEX MATCH "[^\n]*error:[^\n]*" first_error "${error_text}")
      message(FATAL_ERROR "header_nullability.cmake: ${mode} ${header} does not compile: ${first_error}")
    endif()
    # Every diagnostic in this file or an included one, then filtered to this tree's headers below.
    string(REGEX MATCHALL "[^\n]*warning:[^\n]*\\[-Wnullability[^\n]*\\]" warnings "${error_text}")
    foreach(warning IN LISTS warnings)
      if(warning MATCHES "/?([^/:]+):([0-9]+):([0-9]+): warning:")
        set(header_name "${CMAKE_MATCH_1}")
        set(site "${header_name}:${CMAKE_MATCH_2}:${CMAKE_MATCH_3}")
        list(FIND headers "${header_name}" header_index)
        if(header_index GREATER -1)
          list(FIND sites "${site}" seen)
          if(seen EQUAL -1)
            list(APPEND sites "${site}")
          endif()
        endif()
      endif()
    endforeach()
  endforeach()
endforeach()

list(LENGTH headers header_count)
list(LENGTH sites site_count)
if(NOT site_count EQUAL pinned)
  list(SORT sites)
  string(REPLACE ";" "\n  " site_text "${sites}")
  message(FATAL_ERROR
    "The header-nullability gate drifted: the pin says ${pinned} declaration site(s), the tree measures ${site_count}.\n"
    "  ${site_text}\n"
    "\n"
    "Annotate each declaration with _Nonnull, _Nullable or _Null_unspecified (the sweep's recipes are in\n"
    "tests/api-10.11-nullability.txt), or move the pin in the same commit and say why the number changed.")
endif()

message(STATUS
  "header nullability holds: ${header_count} headers in 3 modes (${compiled} compilations), "
  "${site_count} declaration site(s) missing a specifier (pin ${pinned})")
