# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later

# The toll-free bridge's test suite. It belongs here rather than in libagora-core because it needs
# BOTH sides: Core Foundation's doors and Foundation's classes, and only a consumer of Core
# Foundation can name the second.

add_executable(bridges bridges.m)
target_link_libraries(bridges PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME bridges COMMAND bridges)

# The "Calculating linguistic units" group of NSAttributedString. It is a separate suite from the bridge
# one because it is a separate concern: four doors over `FNTextBreaking` and, for the hyphenating break,
# over Core Foundation's hyphenation resource. Nothing else in the tree exercises any of them.
add_executable(linguistic_units linguistic_units.m)
target_link_libraries(linguistic_units PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME linguistic_units COMMAND linguistic_units)

# THE UNIT STYLE (10.10) AND THE ENUM VALUES IT READS. The three unit formatters shipped without `-unitStyle`, and
# `NSFormattingUnitStyle` counted from zero where Apple counts from one; this probe pins both and the singular/plural
# rule the long style states.
add_executable(foundation_10_11_formatting foundation_10_11_formatting.m)
target_link_libraries(foundation_10_11_formatting PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_formatting COMMAND foundation_10_11_formatting)

# THE QUERY ITEM (10.10): a value, not a pair of pointers. Equality, hashing, copy stability and an archive round-trip —
# the three properties `NSURLComponents -queryItems` depends on.
add_executable(foundation_10_11_url_query_item foundation_10_11_url_query_item.m)
target_link_libraries(foundation_10_11_url_query_item PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_url_query_item COMMAND foundation_10_11_url_query_item)

# THE PUBLIC PARSER (10.9) THROUGH ITS OWN NAME: the encoded/decoded split, queryItems both ways, and relative resolution.
add_executable(foundation_10_11_url_components foundation_10_11_url_components.m)
target_link_libraries(foundation_10_11_url_components PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_url_components COMMAND foundation_10_11_url_components)

# THE OBSERVATION CONTRACT (10.9): KVO on the derived keys, the per-thread current stack, a child's share, cancellation
# travelling down, and user info under a readonly property.
add_executable(foundation_10_11_progress foundation_10_11_progress.m)
target_link_libraries(foundation_10_11_progress PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_progress COMMAND foundation_10_11_progress)

# THE BYTE-COUNT FORMATTER (10.8): both bases, the unit a magnitude picks, and each of the seven switches.
add_executable(foundation_10_11_byte_count foundation_10_11_byte_count.m)
target_link_libraries(foundation_10_11_byte_count PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_byte_count COMMAND foundation_10_11_byte_count)

# THE PERSON-NAME FORMATTER (10.11) IS ITS POLICY, so the probe pins the policy: the four styles and the components each
# writes, the absence rule, the ORDER under five language codes and the documented default, the phonetic fallback, the
# annotated form's keyed runs, and the two refusals (an unimplemented style by name, a parsing door that says NO).
add_executable(foundation_10_11_person_name foundation_10_11_person_name.m)
target_link_libraries(foundation_10_11_person_name PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_person_name COMMAND foundation_10_11_person_name)

# THE OPTIONS OBJECT A SESSION IS MADE WITH (10.9, with 10.10/10.11 doors): the defaults table, the three factories'
# differences and the copy a session depends on — no transport, so the contract is entirely observable here.
# THE PSEUDO-TERMINAL: a child with a pty for a controlling terminal — isatty, `tty(1)`, its own session, the line
# discipline's echo and ^C, a size set before the launch and SIGWINCH after it, and the master read through a
# readability handler and a run-loop wait.
add_executable(nstask_pseudoterminal nstask_pseudoterminal.m)
target_link_libraries(nstask_pseudoterminal PRIVATE Foundation CoreFoundation::CoreFoundation objc)
add_test(NAME nstask-pseudoterminal COMMAND nstask_pseudoterminal)

# THE RUN LOOP IS CORE FOUNDATION'S: identity, a one-shot and a repeating timer, -limitDateForMode:, an fd source,
# a delayed perform, a performer sent from another thread, the mode rule, the one-pass door, the main dispatch
# queue and a caller's own CFRunLoopTimer landing in the same loop.
add_executable(runloop_cf runloop_cf.m)
target_link_libraries(runloop_cf PRIVATE Foundation CoreFoundation::CoreFoundation objc dispatch)
add_test(NAME runloop_cf COMMAND runloop_cf)

add_executable(foundation_10_11_session_configuration foundation_10_11_session_configuration.m)
target_link_libraries(foundation_10_11_session_configuration PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_session_configuration COMMAND foundation_10_11_session_configuration)

# THE TASK STATE MACHINE AND THE DATA PATH (10.9/10.10): a task born suspended, a delegate queue, byte counts, the
# completion-handler forms, a redirect the delegate follows and one it refuses, cancellation, and the task lists.
add_executable(foundation_10_11_url_session foundation_10_11_url_session.m)
target_link_libraries(foundation_10_11_url_session PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_url_session COMMAND foundation_10_11_url_session)

# THE EXTENSION VALUE, ITS HOST, ITEMS BY TYPE, AND AN ACCESS INTENT (10.8-10.10): secure coding, refusal by name,
# registered load handlers, and a value with a URL and a kind.
add_executable(foundation_10_11_extension foundation_10_11_extension.m)
target_link_libraries(foundation_10_11_extension PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_extension COMMAND foundation_10_11_extension)

# THE NOTIFICATION VALUE, ITS ACTION, AND AN IN-PROCESS CENTRE (10.8-10.10): copied doors, a copy, scheduling state, the
# delegate consultation, and delivery refusing by name.
add_executable(foundation_10_11_user_notification foundation_10_11_user_notification.m)
target_link_libraries(foundation_10_11_user_notification PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME foundation_10_11_user_notification COMMAND foundation_10_11_user_notification)

# Core Foundation's Unicode normalization, against Unicode's own test suite. A separate suite from the
# bridge because it is a separate concern, and because it is a CONFORMANCE run first: `NormalizationTest.txt`
# is 19,129 cases with six invariants each, and nothing else in the tree asks `CFStringNormalize` anything.
add_executable(normalization normalization.c)
# Foundation is linked for its RPATH rather than its doors: this suite is pure C over Core Foundation, but Core
# Foundation's own build carries a dispatch library that Foundation's link interface brings along, and the other
# suites here get it that way. Linking only CoreFoundation leaves the test unable to load under ctest.
target_link_libraries(normalization PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME normalization COMMAND normalization)

# CFNull and NSNull are one object across the bridge, and `CFEqual` on the pair was TRUE on x86-64 and
# FALSE on aarch64 until issue 6. The `bridges` suite asks the same question inside `door_null`, but it
# reports the type and not the reason — this suite reports the reason. See the file header.
add_executable(null_identity null_identity.m)
target_link_libraries(null_identity PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME null_identity COMMAND null_identity)

# THE ONLY PER-ARCHITECTURE CODE IN THIS LIBRARY, EXERCISED. `fn_forward_entry` captures the register
# file of a call being forwarded and `fn_call_image` makes a call from a stored one; nothing else in the
# tree calls either, so without this suite the aarch64 trampoline can be assembled, linked, loaded and
# still be wrong. See the file header.
add_executable(forwarding forwarding.m)
target_link_libraries(forwarding PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME forwarding COMMAND forwarding)

# **THE SPLIT THAT HAD NO CALLER AND TWO BUGS.** `-componentsSeparatedByCharactersInSet:` hung on its first caller
# (AppKit's token field) because its end case re-entered the loop without advancing, and it mixed byte offsets with
# UTF-16 ranges. A door nothing calls is a door nobody measures, so this suite is the caller it did not have: the runs,
# the ends, the empty receiver and a non-ASCII string whose pieces would be sliced wrongly by byte arithmetic.
add_executable(string_split string_split.m)
target_link_libraries(string_split PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME string_split COMMAND string_split)

# **THE SETTINGS STORE ANNOUNCES ITS KEYS.** A defaults key has no setter for KVO's automatic wrapper to bracket, so
# the store sends the manual pair itself. The probe observes an arbitrary key string (`NSWindow Frame probe`, which is
# what AppKit stores), writes it through every door, and checks the three rules the announcements rest on: one write is
# one notification (a KVC write is not announced twice), a removal of an absent key announces nothing, and a registered
# default announces only when its EFFECTIVE value moved. It points the store at a scratch root with FNX_CONFIG_ROOT.
add_executable(user_defaults_kvo user_defaults_kvo.m)
target_link_libraries(user_defaults_kvo PRIVATE Foundation CoreFoundation::CoreFoundation objc)
add_test(NAME user_defaults_kvo COMMAND user_defaults_kvo)

# **KVO'S AUTOMATIC HALF: A SETTER CALLED DIRECTLY ANNOUNCES ITS CHANGE.** The v1 registry announced KVC's own writes;
# this probe calls the setters, which is what application code does, and measures the change dictionary the wrapper
# produces. It also pins the class lie (`-class` vs `object_getClass`), the one-announcement rule for a KVC write (the
# setter wrapper and KVC's wrapper must not both speak), the named unwrapped types (a struct falls back to the manual
# pair) and the two removal spellings. It imports <objc/runtime.h> for `object_getClass`, which is the only way to see
# the dynamic subclass.
add_executable(kvo_automatic kvo_automatic.m)
target_link_libraries(kvo_automatic PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME kvo_automatic COMMAND kvo_automatic)

# **THE TO-MANY HALF: LIVE COLLECTION PROXIES AND THE CHANGE DICTIONARIES THEY PRODUCE.** The probe mutates through
# `-mutableArrayValueForKey:`/`-mutableSetValueForKey:` and measures the announcement: kind, index set, and the OLD/NEW
# objects (retained past the mutation that freed them). It checks both arms — an already-mutable property is changed in
# place and reports a to-many change; an immutable one is replaced and reports a setting change — plus Prior, the
# nil-property creation, the dotted path (whose notification belongs to the head object) and the unobserved proxy.
add_executable(kvo_tomany kvo_tomany.m)
target_link_libraries(kvo_tomany PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME kvo_tomany COMMAND kvo_tomany)

# **THE INSTALLATION'S DIRECTORY SET, ASKED THE WAY AN APPLICATION ASKS FOR IT.** The search-path function used to be
# a named refusal, so AppKit built `~/Library` by hand and the autosave probe found `NSTemporaryDirectory()` naming a
# directory nothing created. A complete installation now carries the Mac OS X directory set, and the answer is a table;
# this suite pins the table's per-domain answers, the two spellings of a user path, the refusals (a domain that does not
# carry the directory, the network, NSItemReplacementDirectory), the two unions, the URL doors and `create:`.
add_executable(search_paths search_paths.m)
target_link_libraries(search_paths PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME search_paths COMMAND search_paths)

# The predicate family COREDATA-PLAN.md §4.1 restores. Every door has a caller: evaluation over real objects,
# the collection filters, substitution variables, and the `-predicateFormat` round trip — because Core Data
# loads predicates from strings and a predicate that cannot render itself cannot be saved.
add_executable(predicate predicate.m)
target_link_libraries(predicate PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME predicate COMMAND predicate)

# **THE EXPRESSION DOOR (10.6), WHICH IS THE PREDICATE GRAMMAR PLUS ARITHMETIC.** `+expressionWithFormat:` reads the
# same substitutions and refuses with the same offsets, then evaluates what it built: Apple's function names, two
# precedences, grouping, a sign in operand position, and the `-fn_expressionFormat` round trip — because the reason
# the predicate family exists is that saved text means the same thing when it is read again.
add_executable(expression_format expression_format.m)
target_link_libraries(expression_format PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME expression_format COMMAND expression_format)

# **ZONES AND THE COPYING PROTOCOL, MEASURED TOGETHER.** The zone API was removed once and
# `-copyWithZone:` went with it; this suite pins the restored contract: zone names and identity,
# zone memory from every allocator, an object reporting the zone it was allocated in, the raw-copy
# primitive, and Cocoa's `-copy` -> `-copyWithZone:` delegation.
add_executable(zones zones.m)
target_link_libraries(zones PRIVATE Foundation CoreFoundation::CoreFoundation objc)

add_test(NAME zones COMMAND zones)

# ---------------------------------------------------------------------------
# THE MEASUREMENT — how much of the Mac OS X 10.6 Foundation this library answers, as a gate.
# ---------------------------------------------------------------------------
# `claims_census` in the AppKit tier counts what a tree SAYS it cannot do. This counts what a caller would actually
# GET, against the committed facts of Apple's 10.6 Foundation (`api/10.6/foundation-manifest.txt` — names and
# relationships only, because the SDK is not redistributable). Whether a selector is answered needs a superclass
# chain rather than a regex, so the parser is `api-ledger`; the pin is `api-10.6-census.txt`; and moving a number is
# a deliberate act in the same commit that says which wave moved it.
#
# **THE LEDGER IS A SIBLING COMPONENT'S, AND THAT IS THE TREE'S PRECEDENT.** libagora-data points at the same tool
# through a CACHE PATH, and libagora-base already points at `../libagora-drawing` for Core Graphics' headers the same
# way. A path variable means a checkout where the sibling lives elsewhere can still run the suite.
set(AGORA_LEDGER "${CMAKE_CURRENT_SOURCE_DIR}/../../libagora-app/tools/api-ledger"
    CACHE FILEPATH "api-ledger, from the libagora-app component")

# **AND ONE INCLUDE DIRECTORY IS PART OF THE SURFACE.** NSMakeRange and NSMaxRange are inline doors declared in
# libagora-core and reached through NSObjCRuntime.h, so a census that reads only this directory's headers reports
# them as functions with no symbol. The ledger is given the directory rather than the two names, so a future
# Foundation-shaped inline door in Core Foundation is measured the same way.
set(AGORA_CORE_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../libagora-core/include"
    CACHE PATH "libagora-core's headers, for Foundation's inline NSRange doors")

# **THE BUILT LIBRARY IS AN INPUT, BECAUSE A DECLARATION IS NOT A DOOR.** `-DLIBRARY=$<TARGET_FILE:Foundation>` lets
# `nm -D --defined-only` answer which functions a caller can link against, and the gate fails outright if the headers
# and the symbols disagree in either direction rather than moving a number.
#
# A PYTHON INTERPRETER IS A RUN-TIME REQUIREMENT, NOT A BUILD ONE. Every other test in this suite is a compiled
# executable, so the tree needs no interpreter to build; only this gate needs one to run. It is registered whenever
# the interpreter exists and fails loudly at run time if the ledger is missing, instead of disappearing from the
# suite — a gate that quietly unregisters itself is the drift these censuses exist to stop.
find_package(Python3 COMPONENTS Interpreter QUIET)
if(Python3_Interpreter_FOUND)
  add_test(NAME foundation-api-census
    COMMAND "${CMAKE_COMMAND}"
            "-DPYTHON=${Python3_EXECUTABLE}"
            "-DLEDGER=${AGORA_LEDGER}"
            "-DMANIFEST=${CMAKE_CURRENT_SOURCE_DIR}/../api/10.6/foundation-manifest.txt"
            "-DLIBRARY=$<TARGET_FILE:Foundation>"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/api-10.6-census.txt"
            "-DINCLUDES=${AGORA_CORE_INCLUDE_DIR}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/api_census.cmake")

  # **THE SECOND DENOMINATOR — THE ONE COCOA-10.11-SURFACE-PLAN.md COMMITS TO.** The gate script is the same file:
  # it takes a manifest, a pin and the built library, so the 10.11 surface needs a registration rather than a second
  # implementation. The two pins measure different questions (a 10.6 door disappearing; a 10.11 door never arriving)
  # and both run on every build, because a plan that cannot be recomputed is a claim.
  add_test(NAME foundation-api-10.11-census
    COMMAND "${CMAKE_COMMAND}"
            "-DPYTHON=${Python3_EXECUTABLE}"
            "-DLEDGER=${AGORA_LEDGER}"
            "-DMANIFEST=${CMAKE_CURRENT_SOURCE_DIR}/../api/10.11/foundation-manifest.txt"
            "-DLIBRARY=$<TARGET_FILE:Foundation>"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/api-10.11-census.txt"
            "-DINCLUDES=${AGORA_CORE_INCLUDE_DIR}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/api_census.cmake")

  # **THE INSTRUMENT'S OWN REGRESSION CASES.** Three extractor faults were found by pointing the ledger at the 10.11
  # headers, and each one produced a plausible wrong number: a property's trailing annotation read as its name (or
  # making the property vanish), a deprecation message's sentence read as a selector, and availability not being a
  # fact at all. They are fixed in a sibling component's tool, which no test here compiled; this registers the cases
  # so a future edit to that parser fails in the build rather than in a census six waves later.
  add_test(NAME api-ledger-selftest
    COMMAND "${Python3_EXECUTABLE}" "${AGORA_LEDGER}" selftest)

  # **S2: THE ANNOTATION GATE.** COCOA-10.11-SURFACE-PLAN.md's second tier is not declared names but the availability
  # facts on them, and this is where they are measured: the reference's versions are committed in the manifest as
  # `class-era`/`selector-era` facts, so the check needs no SDK checkout. It fails on a declaration that states a
  # WRONG version (which looks finished and is not) and on drift in `api-10.11-annotations.txt`, whose
  # `annotations-missing` line is the sweep's work list.
  add_test(NAME foundation-api-availability
    COMMAND "${Python3_EXECUTABLE}" "${AGORA_LEDGER}" availability
            "${CMAKE_CURRENT_SOURCE_DIR}/../api/10.11/foundation-manifest.txt"
            "${CMAKE_CURRENT_SOURCE_DIR}/.."
            --pin "${CMAKE_CURRENT_SOURCE_DIR}/api-10.11-annotations.txt")

  # **W5: THE REFUSALS ARE A CENSUS, NOT PROSE.** Every `FOUNDATION-REFUSE` site is counted per file and compared in
  # both directions against tests/refusal_census.txt, so adding or removing a refusal is a deliberate diff. The
  # instrument is libagora-app's `claims_census.cmake`, SHARED by path rather than copied: it is GPL and this
  # component is LGPL, and the plan's own word for this gate was "copied or shared".
  add_test(NAME foundation-refusal-census
    COMMAND "${CMAKE_COMMAND}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DCENSUS=${CMAKE_CURRENT_SOURCE_DIR}/refusal_census.txt"
            "-DEXTENSION=.m"
            "-DNEEDLE=(FOUNDATION-REFUSE|fn_refuse_[a-z]+)"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/../../libagora-app/tests/claims_census.cmake")

  # **S5: EVERY PUBLIC HEADER STANDS ALONE.** The library build proves the umbrella works for its own sources; this
  # asks the client's question instead — import ONE header — in the three client modes, and compiles the umbrella
  # once per mode as well. It found five headers that had never been asked: two that imported nothing, a category
  # whose class was only forward-declared, an ivar type nobody declared, and a protocol conformance with no protocol.
  add_test(NAME foundation-header-compile
    COMMAND "${CMAKE_COMMAND}"
            "-DCLANG=${CMAKE_OBJC_COMPILER}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DINCLUDE=${_agora_include_dir};${CMAKE_INSTALL_PREFIX}/include"
            "-DWORK=${CMAKE_CURRENT_BINARY_DIR}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/header_compile.cmake")

  # **S2'S LAST RESIDUE: THE HEADERS STATE THEIR NULLABILITY.** The sweep's nine sites are recorded in
  # api-10.11-nullability.txt and closed; this gate keeps them closed. It is a SEPARATE test from header-compile
  # because the two ask different questions of the same 600 compilations — "does it compile" and "does it say which
  # pointers may be nil" — and a header can pass one and fail the other. The pinned unit is a distinct declaration
  # site, deduped across every probe and mode: a warning-line count repeats an included header once per probe.
  add_test(NAME foundation-header-nullability
    COMMAND "${CMAKE_COMMAND}"
            "-DCLANG=${CMAKE_OBJC_COMPILER}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DINCLUDE=${_agora_include_dir};${CMAKE_INSTALL_PREFIX}/include"
            "-DWORK=${CMAKE_CURRENT_BINARY_DIR}"
            "-DPIN=${CMAKE_CURRENT_SOURCE_DIR}/api-10.11-nullability.txt"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/header_nullability.cmake")

  # **S2'S OTHER RESIDUE: THE POST-10.11 SURFACE IS MARKED, AND MARKED FOR REAL.** COCOA-10.11-SURFACE-PLAN.md §4.1
  # keeps the tree's later-than-10.11 API behind AGORA_EXTENSION: the normal build keeps every door, and
  # `-DAG_TARGET_OS_X_10_11` makes those declarations unavailable. This proves the umbrella still compiles under the
  # strict define (one unmarked mention of an extension type breaks it), that each extension is actually unavailable
  # there, and that the same use compiles in the normal build — a marker that HID a door rather than stating its
  # version would be a removal, which §4.1 forbids.
  add_test(NAME foundation-strict-surface
    COMMAND "${CMAKE_COMMAND}"
            "-DCLANG=${CMAKE_OBJC_COMPILER}"
            "-DSOURCE_DIR=${CMAKE_CURRENT_SOURCE_DIR}/.."
            "-DINCLUDE=${_agora_include_dir};${CMAKE_INSTALL_PREFIX}/include"
            "-DWORK=${CMAKE_CURRENT_BINARY_DIR}"
            -P "${CMAKE_CURRENT_SOURCE_DIR}/strict_surface.cmake")
else()
  message(STATUS
    "libagora-base: no Python3 interpreter, so the API census gates (10.6 and 10.11) and the ledger selftest are not "
    "registered — install python3, or the Foundation surface goes unmeasured.")
endif()

# THE 10.6 ROOT-CLASS DOORS, MEASURED BY A CALLER RATHER THAN BY THE CENSUS. The census finds a body; this probe is
# what says the body means what the door means: the runtime hooks, the delayed and threaded perform family, the
# OpenStep KVC spellings and the stored accessor, KVO's dependency rule in both spellings, the comparison protocol,
# the stack doors, and the small formatter/collection/expression/strings-file additions.
add_executable(object_surface object_surface.m)
target_link_libraries(object_surface PRIVATE Foundation CoreFoundation::CoreFoundation objc)
add_test(NAME object_surface COMMAND object_surface)

# THE F3/F5/F6/F10/F11 SUBSYSTEMS, MEASURED BY A CALLER: the specifier walk, a whose-test, the standard commands, a
# suite declaration, the AppleEvent descriptor, the AppleScript refusal, a metadata query over a temporary directory,
# and the TXT-record codec plus the net-service refusal.
add_executable(scripting_surface scripting_surface.m)
target_link_libraries(scripting_surface PRIVATE Foundation CoreFoundation::CoreFoundation objc)
add_test(NAME scripting_surface COMMAND scripting_surface)

# THE BEHAVIOURAL PASS OVER THE VALUE TYPES: strings (UTF-16 indices, comparison options, hashing), the collections
# (copy/mutability, equality and hashing, enumeration mutation), numbers (cross-kind equality, 64-bit comparison,
# decimals), data, index sets, dates, JSON, property lists, both archivers, and NSURL.
add_executable(core_values core_values.m)
target_link_libraries(core_values PRIVATE Foundation CoreFoundation::CoreFoundation objc)
add_test(NAME core_values COMMAND core_values)


# THE BEHAVIOURAL PASS, SECOND WAVE: predicates and KVC operators, sort descriptors, notifications (selector, block,
# queue, removal during a post), operations and dependencies, the file manager including atomic replacement, file
# streams, undo, regular expressions, the scanner, date formatting, timers, character sets and the geometry values.
add_executable(foundation_behaviour foundation_behaviour.m)
target_link_libraries(foundation_behaviour PRIVATE Foundation CoreFoundation::CoreFoundation objc)
add_test(NAME foundation_behaviour COMMAND foundation_behaviour)


# THE BEHAVIOURAL PASS, THIRD WAVE: calendar arithmetic (leap day, DST), formatters, the defaults store's domains,
# XML parsing and serialisation, value transformers, HTTP cookies, locales and time-zone transitions.
add_executable(foundation_behaviour_2 foundation_behaviour_2.m)
target_link_libraries(foundation_behaviour_2 PRIVATE Foundation CoreFoundation::CoreFoundation objc)
add_test(NAME foundation_behaviour_2 COMMAND foundation_behaviour_2)

# THE BEHAVIOURAL PASS, FOURTH WAVE: secure coding and allow-lists, defaults written by another process, an HTTP
# request against a loopback server, socket streams, an NSConnection round-trip, file handles, and a coarse
# performance smoke test (generous bounds, aimed at accidental quadratics rather than micro-benchmarks).
add_executable(foundation_behaviour_3 foundation_behaviour_3.m)
target_link_libraries(foundation_behaviour_3 PRIVATE Foundation CoreFoundation::CoreFoundation objc pthread)
add_test(NAME foundation_behaviour_3 COMMAND foundation_behaviour_3)

# THE BEHAVIOURAL PASS, FIFTH WAVE: a redirect followed with its Set-Cookie kept and sent, a POST body and a caller's
# header, NSTask's pipes and environment, an NSConnection between two PROCESSES over a TCP socket port, and a
# repeated observe/notify/archive soak.
add_executable(foundation_behaviour_4 foundation_behaviour_4.m)
target_link_libraries(foundation_behaviour_4 PRIVATE Foundation CoreFoundation::CoreFoundation objc pthread)
add_test(NAME foundation_behaviour_4 COMMAND foundation_behaviour_4)
