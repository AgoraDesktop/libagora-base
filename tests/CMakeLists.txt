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
