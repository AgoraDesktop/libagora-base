/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSByteCountFormatter.h — a byte count as a person reads it (10.8).
 *
 * **THE OPTIONS ARE THE CONTRACT, AND EACH ONE CHANGES THE STRING.** A formatter that "formatting a byte count" only
 * implemented decimal-or-binary and rounded would pass a header diff and fail every caller who asked for the unit
 * without the count, the count without the unit, the actual bytes instead of the scaled value, or a fixed number of
 * fraction digits. So all seven knobs are here and the probe exercises them together — the combinations are the
 * surface, not the individual doors.
 *
 * **ADAPTIVE IS THE DEFAULT AND IT IS NOT ROUNDING.** Adaptive chooses the largest unit in which the value is at least
 * 1 (or the smallest allowed unit when the value is below all of them), then renders with at most one fraction digit;
 * non-adaptive keeps the value in the unit it was given by the style's base (bytes for binary, bytes for decimal, with
 * the unit chosen by magnitude of the LOG — the difference is that adaptive re-scales per value while the fixed styles
 * scale by the 1000/1024 boundary only once).
 *
 * The scale factors are 1000 and 1024, and the unit names are the short forms Apple prints on macOS (`KB`, `MB`,
 * `KiB`, `MiB`) — the long spellings are the iOS ones and are not used here.
 */

#ifndef FOUNDATION_NSBYTECOUNTFORMATTER_H
#define FOUNDATION_NSBYTECOUNTFORMATTER_H

#import <Foundation/NSFormatter.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NSByteCountFormatterUnits) {
	NSByteCountFormatterUseDefault = 0,
	NSByteCountFormatterUseBytes = 1UL << 0,
	NSByteCountFormatterUseKB = 1UL << 1,
	NSByteCountFormatterUseMB = 1UL << 2,
	NSByteCountFormatterUseGB = 1UL << 3,
	NSByteCountFormatterUseTB = 1UL << 4,
	NSByteCountFormatterUsePB = 1UL << 5,
	NSByteCountFormatterUseEB = 1UL << 6,
	NSByteCountFormatterUseZB = 1UL << 7,
	NSByteCountFormatterUseYBOrMore = 1UL << 8,
	NSByteCountFormatterUseAll = 0x00FF
};

typedef NS_ENUM(NSInteger, NSByteCountFormatterCountStyle) {
	NSByteCountFormatterCountStyleFile = 0,
	NSByteCountFormatterCountStyleMemory = 1,
	NSByteCountFormatterCountStyleDecimal = 2,
	NSByteCountFormatterCountStyleBinary = 3
};

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSByteCountFormatter : NSFormatter
{
	NSByteCountFormatterUnits _allowedUnits;
	NSByteCountFormatterCountStyle _countStyle;
	NSFormattingContext _formattingContext;
	BOOL _allowsNonnumericFormatting;
	BOOL _includesUnit;
	BOOL _includesCount;
	BOOL _includesActualByteCount;
	BOOL _adaptive;
	NSUInteger _zeroPadsFractionDigits;
}

+ (NSString *)stringFromByteCount:(long long)byteCount
                       countStyle:(NSByteCountFormatterCountStyle)countStyle;
- (NSString *)stringFromByteCount:(long long)byteCount;

@property NSByteCountFormatterCountStyle countStyle;	/* default NSByteCountFormatterCountStyleFile */
@property NSByteCountFormatterUnits allowedUnits;		/* default NSByteCountFormatterUseAll */
@property (getter=isAdaptive) BOOL adaptive;		/* default YES */
@property BOOL allowsNonnumericFormatting;			/* default YES: "Zero KB" rather than "0 bytes" */
@property BOOL includesUnit;				/* default YES */
@property BOOL includesCount;				/* default YES */
@property BOOL includesActualByteCount;			/* default NO: the exact bytes in parentheses */
@property NSUInteger zeroPadsFractionDigits;		/* default 0 */
@property NSFormattingContext formattingContext NS_AVAILABLE_MAC(10_10);

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSBYTECOUNTFORMATTER_H */
