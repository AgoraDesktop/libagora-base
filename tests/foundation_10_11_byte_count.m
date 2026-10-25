/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_byte_count.m — THE SEVEN SWITCHES, MEASURED TOGETHER (10.8).
 *
 * A byte-count formatter's surface is not "format a number": it is the combinations. The probe pins the base each style
 * chooses (1000 for file/decimal, 1024 for memory/binary), the unit the magnitude picks, and then each flag on its own
 * against the same value, because a formatter that ignored one of them would still print something plausible.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int g_pass, g_fail;

static void expect(NSByteCountFormatter *f, long long bytes, const char *want, const char *what)
{
	const char *got = [[f stringFromByteCount:bytes] UTF8String];

	if (got != NULL && strcmp(got, want) == 0) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stderr, "FAIL: %s: got \"%s\", want \"%s\"\n", what, got == NULL ? "(nil)" : got, want);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSByteCountFormatter *f = [[NSByteCountFormatter alloc] init];

	/* THE CLASS METHOD IS THE DEFAULT STYLE, AND THE DEFAULT STYLE IS FILE (decimal). */
	expect(f, 0, "Zero bytes", "zero, non-numeric by default");
	expect(f, 999, "999 bytes", "below the first unit");
	expect(f, 1000, "1 kB", "decimal base at 1000");
	expect(f, 1024, "1 kB", "1024 is still 1 kB in the decimal style");
	expect(f, 1500, "1.5 kB", "a fractional value keeps one digit");
	expect(f, 1000000, "1 MB", "a million bytes");

	/* THE MEMORY STYLE COUNTS IN 1024s AND NAMES WITH THE BINARY SPELLING. */
	[f setCountStyle:NSByteCountFormatterCountStyleMemory];
	expect(f, 1024, "1 KB", "binary base at 1024");
	expect(f, 1536, "1.5 KB", "and a fractional value");
	expect(f, 1048576, "1 MB", "and the next power");

	/* THE FLAGS, ONE AT A TIME, ON THE SAME VALUE. */
	[f setCountStyle:NSByteCountFormatterCountStyleFile];
	[f setIncludesUnit:NO];
	expect(f, 1500, "1.5", "count without the unit");
	[f setIncludesUnit:YES];
	[f setIncludesCount:NO];
	expect(f, 1500, "kB", "unit without the count");
	[f setIncludesCount:YES];
	[f setIncludesActualByteCount:YES];
	expect(f, 1500, "1.5 kB (1500 bytes)", "the actual byte count in parentheses");
	[f setIncludesActualByteCount:NO];

	/* THE UNIT MASK BOUNDS THE CHOICE. */
	[f setAllowedUnits:NSByteCountFormatterUseBytes];
	expect(f, 1500, "1500 bytes", "bytes only");
	[f setAllowedUnits:NSByteCountFormatterUseKB];
	expect(f, 1500, "1.5 kB", "kilobytes only");
	[f setAllowedUnits:NSByteCountFormatterUseAll];

	/* NON-NUMERIC OFF IS "0 bytes"; ADAPTIVE OFF KEEPS THE LOW UNIT. */
	[f setAllowsNonnumericFormatting:NO];
	expect(f, 0, "0 bytes", "zero with non-numeric formatting off");
	[f setAllowsNonnumericFormatting:YES];

	/* ZERO PADDING FIXES THE DIGITS. */
	[f setZeroPadsFractionDigits:2];
	expect(f, 1500, "1.50 kB", "two padded fraction digits");
	[f setZeroPadsFractionDigits:0];

	/* THE CLASS METHOD AND THE CONTEXT PROPERTY ROUND-TRIP. */
	expect(f, 2000, "2 kB", "class default after the flags are back");
	[f setFormattingContext:NSFormattingContextStandalone];
	if ([f formattingContext] != NSFormattingContextStandalone) {
		g_fail++;
		fprintf(stderr, "FAIL: formattingContext does not round-trip\n");
	} else {
		g_pass++;
	}
	if (![[NSByteCountFormatter stringFromByteCount:2048 countStyle:NSByteCountFormatterCountStyleBinary]
			isEqualToString:@"2 KB"]) {
		g_fail++;
		fprintf(stderr, "FAIL: the class method does not take the style\n");
	} else {
		g_pass++;
	}

	printf("foundation_10_11_byte_count: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[f release];
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
