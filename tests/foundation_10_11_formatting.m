/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_formatting.m — THE UNIT STYLE (10.10) AND THE ENUM VALUES IT READS.
 *
 * `NSEnergyFormatter`, `NSLengthFormatter` and `NSMassFormatter` shipped here without the `unitStyle` property Apple
 * added in 10.10, and `NSFormattingUnitStyle` counted from zero where Apple's counts from one — so a client comparing
 * `NSFormattingUnitStyleShort` saw 0 here and 1 there. Both are fixed in the same slice, and this probe is the caller
 * that says so: the three constants, the medium default, and the one rule the style actually states — short and medium
 * render the SI symbol, long renders the unit's NAME, pluralised unless the value is exactly one.
 *
 * **THE ONE-VALUE CASE IS THE WHOLE POINT OF A LONG STYLE**, which is why it is tested on each of the three families
 * rather than once: "1 meter" and "2 meters" are the same row of the same table, and a pluraliser that cannot tell
 * them apart is a pluraliser that only ever needed a symbol.
 */

#import <Foundation/Foundation.h>

#include <stdarg.h>
#include <stdio.h>

static int g_pass, g_fail;

static void expect(NSString *got, const char *want, const char *what)
{
	const char *text = [got UTF8String];

	if (text != NULL && strcmp(text, want) == 0) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stderr, "FAIL: %s: got \"%s\", want \"%s\"\n", what, text == NULL ? "(nil)" : text, want);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSLengthFormatter *length = [[NSLengthFormatter alloc] init];
	NSEnergyFormatter *energy = [[NSEnergyFormatter alloc] init];
	NSMassFormatter *mass = [[NSMassFormatter alloc] init];

	/* THE CONSTANTS ARE APPLE'S. A client comparing against 1/2/3 must find the same numbers here. */
	if (NSFormattingUnitStyleShort == 1 && NSFormattingUnitStyleMedium == 2 && NSFormattingUnitStyleLong == 3) {
		g_pass++;
	} else {
		g_fail++;
		fprintf(stderr, "FAIL: NSFormattingUnitStyle values are not 1/2/3\n");
	}

	/* THE DEFAULT IS MEDIUM, and it is set in -init rather than left to a zeroed ivar (0 is not a style). */
	if ([length unitStyle] == NSFormattingUnitStyleMedium && [energy unitStyle] == NSFormattingUnitStyleMedium
		&& [mass unitStyle] == NSFormattingUnitStyleMedium) {
		g_pass++;
	} else {
		g_fail++;
		fprintf(stderr, "FAIL: default unitStyle is not NSFormattingUnitStyleMedium\n");
	}

	/* SHORT AND MEDIUM ARE THE SYMBOL. */
	expect([length stringFromValue:2.0 unit:NSLengthFormatterUnitMeter], "2 m", "length short");
	[length setUnitStyle:NSFormattingUnitStyleMedium];
	expect([length stringFromValue:2.0 unit:NSLengthFormatterUnitMeter], "2 m", "length medium is the symbol");
	expect([length unitStringFromValue:2.0 unit:NSLengthFormatterUnitMeter], "m", "medium unit name");

	/* LONG IS THE NAME, AND THE SINGULAR IS A DIFFERENT STRING FROM THE PLURAL. */
	[length setUnitStyle:NSFormattingUnitStyleLong];
	expect([length stringFromValue:1.0 unit:NSLengthFormatterUnitMeter], "1 meter", "one metre");
	expect([length stringFromValue:2.0 unit:NSLengthFormatterUnitMeter], "2 meters", "two metres");
	expect([length stringFromValue:1.0 unit:NSLengthFormatterUnitFoot], "1 foot", "one foot (irregular plural)");
	expect([length stringFromValue:2.0 unit:NSLengthFormatterUnitFoot], "2 feet", "two feet");
	expect([length unitStringFromValue:2.0 unit:NSLengthFormatterUnitMeter], "meters", "long unit name");
	expect([length unitStringFromValue:1.0 unit:NSLengthFormatterUnitMeter], "meter", "long unit name, singular");

	/* THE SAME TWO RULES ON THE ENERGY FAMILY. */
	[energy setUnitStyle:NSFormattingUnitStyleLong];
	expect([energy stringFromValue:1.0 unit:NSEnergyFormatterUnitJoule], "1 joule", "one joule");
	expect([energy stringFromValue:4.0 unit:NSEnergyFormatterUnitJoule], "4 joules", "four joules");
	expect([energy stringFromValue:1.0 unit:NSEnergyFormatterUnitKilocalorie], "1 kilocalorie", "one kilocalorie");

	/* AND ON MASS, INCLUDING A UNIT WHOSE PLURAL IS ITS SINGULAR. */
	[mass setUnitStyle:NSFormattingUnitStyleLong];
	expect([mass stringFromValue:1.0 unit:NSMassFormatterUnitKilogram], "1 kilogram", "one kilogram");
	expect([mass stringFromValue:2.5 unit:NSMassFormatterUnitKilogram], "2.5 kilograms", "two and a half kilograms");
	expect([mass stringFromValue:1.0 unit:NSMassFormatterUnitStone], "1 stone", "one stone");
	expect([mass stringFromValue:3.0 unit:NSMassFormatterUnitStone], "3 stone", "three stone");

	/* THE STYLE SURVIVES A CHANGE BACK: it is a property, not a one-way latch. */
	[mass setUnitStyle:NSFormattingUnitStyleShort];
	expect([mass stringFromValue:3.0 unit:NSMassFormatterUnitStone], "3 st", "back to the symbol");

	printf("foundation_10_11_formatting: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[length release];
	[energy release];
	[mass release];
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
