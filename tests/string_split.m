/*
 * string_split — `-componentsSeparatedByCharactersInSet:`: the runs, the ends, and the non-ASCII offsets.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THIS SUITE EXISTS BECAUSE THE METHOD HAD NO CALLER AND TWO BUGS.** Its first caller — AppKit's token field, which
 * tokenizes a typed string — HUNG on it, and reading the loop found the reason: the end-of-string case set the break
 * flag without advancing, so `offset == size` re-entered forever. The same loop also mixed a BYTE offset with a
 * CHARACTER index and then handed the byte offset to `-substringWithRange:`, which reads UTF-16 code units. Neither
 * could be seen while nothing in the tree called the door, which is the argument for this file rather than a note.
 *
 * THE CASES ARE THE ONES THE TWO BUGS NEED, plus the documented shape of the answer:
 *
 *   1. A plain split, so the ordinary path is not lost among the edge cases.
 *   2. A RUN of separators is ONE break and produces no empty component.
 *   3. A LEADING run and a TRAILING run produce no empty components either.
 *   4. An empty receiver answers one EMPTY component, not an empty array.
 *   5. A set the string does not contain answers the whole string.
 *   6. A non-ASCII string splits at the right places AND keeps its characters — the byte/UTF-16 case, where the old
 *      arithmetic would have sliced a range out of the middle of a multi-byte character.
 */
#import <Foundation/Foundation.h>

#include <stdio.h>

static int g_failed;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		g_failed++;
	}
}

int main(void)
{
	@autoreleasepool {
		NSCharacterSet *comma = [NSCharacterSet characterSetWithCharactersInString:@","];
		NSCharacterSet *space = [NSCharacterSet whitespaceCharacterSet];
		NSArray *parts;

		parts = [@"a,b,c" componentsSeparatedByCharactersInSet:comma];
		check([parts count] == 3 && [[parts objectAtIndex:1] isEqual:@"b"],
		      "a plain split keeps every piece in order");

		parts = [@"a,,b" componentsSeparatedByCharactersInSet:comma];
		check([parts count] == 2 && [[parts objectAtIndex:1] isEqual:@"b"],
		      "a run of separators is one break and makes no empty piece");

		parts = [@",a," componentsSeparatedByCharactersInSet:comma];
		check([parts count] == 1 && [[parts objectAtIndex:0] isEqual:@"a"],
		      "leading and trailing runs add no empty pieces");

		parts = [@"" componentsSeparatedByCharactersInSet:comma];
		check([parts count] == 1 && [[parts objectAtIndex:0] isEqual:@""],
		      "an empty receiver answers one empty component");

		parts = [@"one two" componentsSeparatedByCharactersInSet:comma];
		check([parts count] == 1 && [[parts objectAtIndex:0] isEqual:@"one two"],
		      "a set the string does not contain answers the whole string");

		parts = [@"John Smith" componentsSeparatedByCharactersInSet:space];
		check([parts count] == 2 && [[parts objectAtIndex:1] isEqual:@"Smith"],
		      "a space splits, for a caller that asks it to");

		parts = [@"héllo,wörld,ok" componentsSeparatedByCharactersInSet:comma];
		check([parts count] == 3, "a non-ASCII string splits into the right number of pieces");
		check([[parts objectAtIndex:0] isEqual:@"héllo"] && [[parts objectAtIndex:1] isEqual:@"wörld"],
		      "and each piece keeps its characters — the range is UTF-16, not bytes");

		printf("string_split: %d case(s) failed\n", g_failed);
	}
	return g_failed != 0;
}
