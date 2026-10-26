# The strict-10.11-surface gate: the AGORA_EXTENSION declarations are real, and hiding them keeps the umbrella whole.
#
# Copyright © 2026 Kyle J. Cardoza.
# SPDX-License-Identifier: LGPL-3.0-or-later
#
# usage: cmake -DCLANG=<clang> -DSOURCE_DIR=<libagora-base> -DINCLUDE=<dir>[;<dir>...] -DWORK=<dir> \
#              -P strict_surface.cmake
#
# **WHAT THIS CHECKS.** COCOA-10.11-SURFACE-PLAN.md §4.1 keeps the tree's post-10.11 API, marks it
# `AGORA_EXTENSION`, and says a build with `AG_TARGET_OS_X_10_11` hides it. This gate proves the three halves of
# that sentence, because each one can fail silently on its own:
#
#   1. THE UMBRELLA STILL COMPILES under the strict define. Hiding a class is not enough if a 10.11 class's header
#      mentions it — `NSDateIntervalFormatter -stringFromDateInterval:` did exactly that, and it is itself a
#      post-10.11 door, so it carries the marker too. One unmarked mention makes the whole strict surface fail, and
#      the umbrella compile is what catches it.
#   2. EACH EXTENSION IS ACTUALLY UNAVAILABLE under the define — a class that lost its marker would still compile,
#      and the build would offer a 10.12 class to a 10.11 client with nothing to notice.
#   3. THE SAME USE COMPILES WITHOUT THE DEFINE. A marker that hid a declaration from the normal build would be a
#      removal, which §4.1 forbids: the normal build keeps every door.
#
# The probe is a class reference, not an allocation: the point is the TYPE's availability, and a reference is the
# smallest use that trips it. Each extension is probed by name so a failure names which one moved.

if(NOT CLANG OR NOT SOURCE_DIR OR NOT INCLUDE OR NOT WORK)
  message(FATAL_ERROR "strict_surface.cmake needs -DCLANG, -DSOURCE_DIR, -DINCLUDE and -DWORK")
endif()

set(include_args "")
foreach(directory IN LISTS INCLUDE)
  if(NOT IS_DIRECTORY "${directory}")
    message(FATAL_ERROR "strict_surface.cmake: include directory does not exist: ${directory}")
  endif()
  list(APPEND include_args "-I${directory}")
endforeach()

file(MAKE_DIRECTORY "${WORK}")
set(base_flags -x objective-c -fobjc-runtime=gnustep-2.0 -fblocks -fsyntax-only)

# 1. The umbrella under the strict define.
set(probe "${WORK}/strict-umbrella.m")
file(WRITE "${probe}" "#import <Foundation/Foundation.h>\nint main(void) { return 0; }\n")
execute_process(
  COMMAND "${CLANG}" ${base_flags} -DAG_TARGET_OS_X_10_11 ${include_args} "${probe}"
  RESULT_VARIABLE result OUTPUT_QUIET ERROR_VARIABLE error_text)
if(NOT result EQUAL 0)
  string(REGEX MATCH "[^\n]*error:[^\n]*" first_error "${error_text}")
  message(FATAL_ERROR
    "The umbrella does not compile under -DAG_TARGET_OS_X_10_11.\n  ${first_error}\n"
    "\nA post-10.11 declaration is reachable from a 10.11 header without carrying AGORA_EXTENSION. Mark the "
    "declaration that names it (NSDateIntervalFormatter's interval door is the precedent), not the class it names.")
endif()

# 2/3. Each extension: unavailable under the define, available without it.
set(uses
    "NSDateInterval|[NSDateInterval class]"
    "NSISO8601DateFormatter|[NSISO8601DateFormatter class]"
    "NSRelativeDateTimeFormatter|[NSRelativeDateTimeFormatter class]"
    "NSSecureUnarchiveFromDataTransformer|[NSSecureUnarchiveFromDataTransformer class]"
    "NSFileProviderService|[NSFileProviderService class]"
    "NSDateIntervalFormatter -stringFromDateInterval:|[[NSDateIntervalFormatter new] stringFromDateInterval:nil]")
set(checked 0)
foreach(use IN LISTS uses)
  string(REPLACE "|" ";" pair "${use}")
  list(GET pair 0 name)
  list(GET pair 1 expression)
  set(probe "${WORK}/strict-use.m")
  file(WRITE "${probe}"
       "#import <Foundation/Foundation.h>\nvoid fn_probe(void) { (void)(${expression}); }\n")

  execute_process(
    COMMAND "${CLANG}" ${base_flags} -DAG_TARGET_OS_X_10_11 ${include_args} "${probe}"
    RESULT_VARIABLE strict_result OUTPUT_QUIET ERROR_VARIABLE strict_text)
  execute_process(
    COMMAND "${CLANG}" ${base_flags} ${include_args} "${probe}"
    RESULT_VARIABLE normal_result OUTPUT_QUIET ERROR_VARIABLE normal_text)

  if(strict_result EQUAL 0)
    message(FATAL_ERROR
      "`${name}` is NOT hidden under -DAG_TARGET_OS_X_10_11: a 10.11 client can still use it. Check that its "
      "declaration carries AGORA_EXTENSION.")
  endif()
  if(NOT strict_text MATCHES "unavailable")
    string(REGEX MATCH "[^\n]*error:[^\n]*" first_error "${strict_text}")
    message(FATAL_ERROR
      "`${name}` fails under -DAG_TARGET_OS_X_10_11 for the wrong reason — the expected 'unavailable' diagnostic is "
      "not in the output.\n  ${first_error}")
  endif()
  if(NOT normal_result EQUAL 0)
    string(REGEX MATCH "[^\n]*error:[^\n]*" first_error "${normal_text}")
    message(FATAL_ERROR
      "`${name}` does not compile WITHOUT the strict define, so the marker is hiding a door the normal build must "
      "keep (§4.1).\n  ${first_error}")
  endif()
  math(EXPR checked "${checked} + 1")
endforeach()

message(STATUS
  "strict surface holds: the umbrella compiles under -DAG_TARGET_OS_X_10_11, and ${checked} extension declaration(s) "
  "are unavailable there and available in the normal build")
