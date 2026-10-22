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
