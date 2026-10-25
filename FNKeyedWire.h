/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * FNKeyedWire.h — THE KEYS THE KEYED ARCHIVE IS WRITTEN WITH. INTERNAL (§63.10).
 *
 * WHY THIS FILE EXISTS RATHER THAN TWO SPELLINGS OF A STRING. The keyed archive's shape is documented
 * publicly in NSKeyedArchiver.h; what this header holds is the KEY NAMES, in one place, because TWO
 * independent code paths write and read them:
 *
 *   * NSKeyedArchiver's own STRUCTURAL branch, which knows an array, a dictionary, a set and an ordered set
 *     by KIND and writes their members under these keys without asking the class anything; and
 *   * the COLLECTIONS' own `-encodeWithCoder:`/`-initWithCoder:` (the NSCoding doors, §63.10), which a
 *     caller reaches by naming them directly.
 *
 * THE TWO MUST AGREE, and a literal typed twice is how they stop agreeing. A `static NSString *const` in a
 * header is one copy per translation unit and no link-time coupling, which is the same arrangement
 * `FNArchiverWire.h` uses for the classic wire's tags.
 *
 * THE NAMES ARE COCOA'S: `NS.objects` and `NS.keys` are what Apple's own keyed archives use for the same two
 * payloads, so an archive written here keeps the familiar spelling. The COUNTS key for a counted set is the
 * one exception and is OURS (NSKeyedArchiver.m says why at its definition) — it is here as well because the
 * keyed coder is not its only reader.
 */

#ifndef FOUNDATION_FNKEYEDWIRE_H
#define FOUNDATION_FNKEYEDWIRE_H

/* The constants below are `NSString *`, so the INTERFACE is needed and not a forward declaration: a forward-declared
 * class cannot be the type of an object literal in a file-scope initializer. The header-compile gate found this one. */
#import <Foundation/NSString.h>

/* The members of a collection, in order where the collection has one. */
static NSString *const FNKeyedObjectsKey = @"NS.objects";

/* A dictionary's keys, PAIRED POSITIONALLY with the objects above. */
static NSString *const FNKeyedKeysKey = @"NS.keys";

#endif /* FOUNDATION_FNKEYEDWIRE_H */
