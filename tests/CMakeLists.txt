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
