/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSRange.h — a range, its inline makers, and the NSValue that boxes it (W7), in Apple's own file.
 *
 * THE STRUCT AND ITS MAKERS ARE CORE FOUNDATION'S, not a second copy: `NSRange` is `CFBridgingTypes.h`'s (Core
 * Foundation needs the type for `CFRange`'s bridging), and `NSMakeRange`/`NSMaxRange` are that header's inline
 * functions. `NSRangePointer`, `NSLocationInRange` and `NSRangeFromString` are NSObjCRuntime.h's. This header is
 * therefore the NAME Apple gives the facts rather than a second declaration of them — and it is where the range side of
 * `NSValue` lives, which is the part Apple puts here and NSValue.h does not carry.
 */
#ifndef FOUNDATION_NSRANGE_H
#define FOUNDATION_NSRANGE_H

#import <CoreFoundation/CFBridgingTypes.h>	/* NSRange, NSMakeRange, NSMaxRange */
#import <Foundation/NSObjCRuntime.h>	/* NSRangePointer, NSLocationInRange, NSRangeFromString */
#import <Foundation/NSValue.h>

NS_ASSUME_NONNULL_BEGIN

/* "Extensions to NSValue for ranges" — Apple's category name, and the doors moved out of NSValue.h in W7. */
@interface NSValue (NSValueRangeExtensions)
+ (NSValue *)valueWithRange:(NSRange)range;
- (NSRange)rangeValue;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSRANGE_H */
