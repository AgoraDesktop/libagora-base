/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSByteCountFormatter.m — one table, seven switches, and one rule about where the digit goes.
 *
 * The table is the surface: scale (1000 or 1024), the unit's bit, and its printed name. Everything else is a
 * combination of the caller's knobs applied to a magnitude — which is why this file has no locale in it: the tree has
 * no locale database, and Apple's formatter is locale-sensitive only in the *decimal separator*, which the number
 * formatting below inherits from the same root locale the rest of this library renders in.
 */

#import <Foundation/NSByteCountFormatter.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

#include <math.h>
#include <stdio.h>

typedef struct {
	long double factor;			/* how many bytes one unit holds, once the style chose the base */
	const char *binaryName;			/* the printed name under the 1024 base */
	const char *decimalName;		/* and under the 1000 base */
	NSByteCountFormatterUnits bit;
} FNByteUnit;

/* ORDER MATTERS: the search walks from the largest DOWN, so the first unit a value reaches is the one printed. */
static const FNByteUnit fn_bc_units[] = {
	{ 1.0L, "bytes", "bytes", NSByteCountFormatterUseBytes },
	{ 1024.0L, "KB", "kB", NSByteCountFormatterUseKB },
	{ 1024.0L * 1024.0L, "MB", "MB", NSByteCountFormatterUseMB },
	{ 1024.0L * 1024.0L * 1024.0L, "GB", "GB", NSByteCountFormatterUseGB },
	{ 1024.0L * 1024.0L * 1024.0L * 1024.0L, "TB", "TB", NSByteCountFormatterUseTB },
	{ 1024.0L * 1024.0L * 1024.0L * 1024.0L * 1024.0L, "PB", "PB", NSByteCountFormatterUsePB },
	{ 1024.0L * 1024.0L * 1024.0L * 1024.0L * 1024.0L * 1024.0L, "EB", "EB", NSByteCountFormatterUseEB }
};

#define FN_BC_UNIT_COUNT	(sizeof(fn_bc_units) / sizeof(fn_bc_units[0]))

@implementation NSByteCountFormatter

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_allowedUnits = NSByteCountFormatterUseAll;
		_countStyle = NSByteCountFormatterCountStyleFile;
		_allowsNonnumericFormatting = YES;
		_includesUnit = YES;
		_includesCount = YES;
		_includesActualByteCount = NO;
		_adaptive = YES;
		_zeroPadsFractionDigits = 0;
	}
	return self;
}

- (NSByteCountFormatterCountStyle)countStyle { return _countStyle; }
- (void)setCountStyle:(NSByteCountFormatterCountStyle)style { _countStyle = style; }
- (NSByteCountFormatterUnits)allowedUnits { return _allowedUnits; }
- (void)setAllowedUnits:(NSByteCountFormatterUnits)units { _allowedUnits = units; }
- (BOOL)isAdaptive { return _adaptive; }
- (void)setAdaptive:(BOOL)flag { _adaptive = flag; }
- (BOOL)allowsNonnumericFormatting { return _allowsNonnumericFormatting; }
- (void)setAllowsNonnumericFormatting:(BOOL)flag { _allowsNonnumericFormatting = flag; }
- (BOOL)includesUnit { return _includesUnit; }
- (void)setIncludesUnit:(BOOL)flag { _includesUnit = flag; }
- (BOOL)includesCount { return _includesCount; }
- (void)setIncludesCount:(BOOL)flag { _includesCount = flag; }
- (BOOL)includesActualByteCount { return _includesActualByteCount; }
- (void)setIncludesActualByteCount:(BOOL)flag { _includesActualByteCount = flag; }
- (NSUInteger)zeroPadsFractionDigits { return _zeroPadsFractionDigits; }
- (void)setZeroPadsFractionDigits:(NSUInteger)digits { _zeroPadsFractionDigits = digits; }
- (NSFormattingContext)formattingContext { return _formattingContext; }
- (void)setFormattingContext:(NSFormattingContext)context { _formattingContext = context; }

+ (NSString *)stringFromByteCount:(long long)byteCount countStyle:(NSByteCountFormatterCountStyle)style
{
	NSByteCountFormatter *formatter = [[[self alloc] init] autorelease];

	[formatter setCountStyle:style];
	return [formatter stringFromByteCount:byteCount];
}

/* THE BASE IS THE STYLE'S, AND THE STYLE IS THE ONLY THING THAT CHOOSES IT. Decimal and file count in 1000s; memory
 * and binary count in 1024s. The table above is written in powers of 1024, so the decimal base divides the factor back
 * down — one table, two bases. */
- (long double)fn_baseForStyle
{
	if (_countStyle == NSByteCountFormatterCountStyleDecimal || _countStyle == NSByteCountFormatterCountStyleFile) {
		return 1000.0L;
	}
	return 1024.0L;
}

static long double fn_pow(long double base, int power)
{
	long double result = 1.0L;
	int i;

	for (i = 0; i < power; i++) {
		result *= base;
	}
	return result;
}

- (NSString *)stringFromByteCount:(long long)byteCount
{
	long double base = [self fn_baseForStyle];
	long double value = (long double)(byteCount < 0 ? -byteCount : byteCount);
	const FNByteUnit *chosen = NULL;
	int chosenPower = 0;
	int power;
	NSString *count;
	NSMutableString *text;
	char buffer[64];
	long double scaled;

	/* THE LARGEST ALLOWED UNIT THE VALUE REACHES, searched downwards from the top of the table. */
	for (power = (int)FN_BC_UNIT_COUNT - 1; power >= 0; power--) {
		long double factor = fn_pow(base, power);

		if ((_allowedUnits & fn_bc_units[power].bit) == 0) {
			continue;
		}
		if (value >= factor || power == 0) {
			chosen = &fn_bc_units[power];
			chosenPower = power;
			break;
		}
	}
	if (chosen == NULL) {
		chosen = &fn_bc_units[0];
	}
	scaled = value / fn_pow(base, chosenPower);

	/* NON-ADAPTIVE KEEPS ONE DECIMAL PLACE, ADAPTIVE DROPS IT WHEN THE VALUE IS WHOLE — the rule the `%.1Lf` and
	 * `%.0Lf` switch below encodes. `zeroPadsFractionDigits` forces that many digits instead. */
	if (_zeroPadsFractionDigits > 0) {
		snprintf(buffer, sizeof(buffer), "%.*Lf", (int)_zeroPadsFractionDigits, scaled);
	} else if (scaled == floorl(scaled)) {
		snprintf(buffer, sizeof(buffer), "%.0Lf", scaled);
	} else {
		snprintf(buffer, sizeof(buffer), "%.1Lf", scaled);
	}
	count = [NSString stringWithUTF8String:buffer];
	/* **A TRAILING `.0` IS TRIMMED.** The value is rendered with at most one fraction digit, and `1.024 kB` rounded to
	 * one digit is `1.0 kB` — which Apple prints as `1 kB`. Trimming here rather than choosing a different precision is
	 * what keeps `1.5 kB` intact in the same pass. `zeroPadsFractionDigits` opts out: a caller who asked for two
	 * digits asked for `1.50`, trailing zero and all. */
	if (_zeroPadsFractionDigits == 0 && [count hasSuffix:@".0"]) {
		count = [count substringToIndex:[count length] - 2];
	}

	/* **NON-NUMERIC FORMATTING IS A WHOLE STRING, NOT A FLAG.** Apache-style "Zero bytes" is what Apple prints when
	 * the flag is on and the count is zero; turning it off is what makes "0 bytes" reachable, so it is a branch and not
	 * a suffix decision. */
	if (byteCount == 0 && _allowsNonnumericFormatting) {
		return @"Zero bytes";
	}

	text = [NSMutableString string];
	if (_includesCount) {
		[text appendString:count];
	}
	if (_includesUnit) {
		const char *name = (base == 1000.0L) ? chosen->decimalName : chosen->binaryName;

		if ([text length] > 0) {
			[text appendString:@" "];
		}
		[text appendString:[NSString stringWithUTF8String:name]];
	}
	if (_includesActualByteCount) {
		if ([text length] > 0) {
			[text appendString:@" "];
		}
		[text appendFormat:@"(%lld bytes)", byteCount];
	}
	if ([text length] == 0) {
		return @"";
	}
	return [NSString stringWithString:text];
}

- (NSString *)stringForObjectValue:(nullable id)object
{
	if (object == nil || ![object isKindOfClass:[NSNumber class]]) {
		return nil;
	}
	return [self stringFromByteCount:[object longLongValue]];
}

@end
