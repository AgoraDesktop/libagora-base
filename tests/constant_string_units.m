/*
 * constant_string_units — a literal's `-length` is CHARACTERS, and a non-ASCII literal is where that shows.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **A TYPOGRAPHIC CHARACTER IN A STRING LITERAL ARRIVED ON THE GLASS AS ITS OWN UTF-8 BYTES.** A Forge window title built
 * as `@"%@ — %@ — %@"` drew as `Hello â( main.m â(`: `â` is 0xE2, the first byte of U+2014's encoding, and what followed
 * was a box per remaining byte. Reading it back, the title was three units long where the source wrote one character.
 *
 * CLANG DOES NOT PUT NON-ASCII LITERALS IN A C STRING. libobjc2's loader reads the low two bits of the constant's flags as
 * an ENCODING — ASCII, UTF-8, UTF-16 — and clang emits every non-ASCII literal as UTF-16, where the runtime's `len` field
 * is the number of 16-bit UNITS. A byte count and a unit count agree for ASCII and only for ASCII, so the ASCII path
 * cannot notice; this probe is that statement, made where the two layers meet.
 */
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

/* THE UNIT AT AN INDEX, or -1 when the string is shorter — the difference between "a character" and "past the end". */
static long fn_unit(NSString *string, NSUInteger index)
{
	if (index >= [string length]) {
		return -1;
	}
	return (long)[string characterAtIndex:index];
}

int main(void)
{
	@autoreleasepool {
		/* 1. AN EM DASH IS ONE CHARACTER. Its UTF-8 form is three bytes, and that is the whole defect. */
		{
			NSString *dash = @"—";		/* U+2014 */

			printf("       literal dash: length %lu, first unit U+%04lX, utf8 %s\n",
				(unsigned long)[dash length], fn_unit(dash, 0), [dash UTF8String]);
			check([dash length] == 1, "an em dash literal is ONE character long");
			check(fn_unit(dash, 0) == 0x2014, "and its unit is U+2014, the character the source wrote");
			check(strcmp([dash UTF8String], "\xE2\x80\x94") == 0,
			      "while its UTF-8 form is still the three bytes E2 80 94");
		}

		/* 2. AND A STRING WITH ONE INSIDE IT IS AS LONG AS ITS CHARACTERS. */
		{
			NSString *phrase = @"café — noir";

			check([phrase length] == 11, "a mixed literal's length counts characters, not bytes");
			check(fn_unit(phrase, 3) == 0xE9, "the accented letter is U+00E9");
			check(fn_unit(phrase, 5) == 0x2014, "and the dash after the space is U+2014");
		}

		/* 3. **THE PATH THAT BUILT THE TITLE**: a format string with a dash in it, rendered into a new string. */
		{
			NSString *built = [NSString stringWithFormat:@"%@ — %@", @"Hello", @"main.m"];

			check([built length] == 14, "a formatted title counts characters too");
			check(fn_unit(built, 6) == 0x2014, "and carries the dash the format asked for");
			check([built isEqualToString:@"Hello — main.m"], "and compares equal to the literal it should be");
		}

		/* 4. A SURROGATE PAIR IS TWO UNITS AND ONE CHARACTER, which is what a unit count means. */
		{
			NSString *emoji = @"\U0001F600";

			check([emoji length] == 2, "a character above U+FFFF is two UTF-16 units");
			check(fn_unit(emoji, 0) == 0xD83D, "the high surrogate is answered as itself");
		}

		/* 5. AND ASCII IS UNCHANGED, because that is the path every other assertion in this tree runs on. */
		{
			NSString *plain = @"Hello, main.m";

			check([plain length] == 13, "an ASCII literal is its byte count, which is its unit count");
		}
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
