/*
 * string_trimming — the trim's range is in CHARACTERS, and the case that proved it is the copyright line.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THIS DOOR WAS BROKEN FOR EVERY STRING WITH A LEADING SPACE AND A NON-ASCII CHARACTER IN IT, AND NOTHING CAUGHT
 * IT.** The walk counted UTF-8 bytes and handed the numbers to `-substringWithRange:`, whose range is in characters,
 * so " * Copyright © 2026 Kyle J. Cardoza." — the first line of every file in this tree — threw
 * `NSRangeException` with a range one element past the end. It was found by the AppKit's umbrella census, which
 * trims the lines of a header it is checking; the cases below are the ones that would have found it here.
 *
 * The claim is small and worth stating exactly: trimming removes members of the set from BOTH ENDS and neither
 * interior nor the characters after a two-byte one; and it answers a string rather than a view into one (the
 * caller's own copy is unchanged).
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

static void check_trim(const char *input, const char *expected, const char *what)
{
	NSString *trimmed = [[NSString stringWithUTF8String:input] stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceCharacterSet]];
	const char *answer = [trimmed UTF8String];
	int matches = (answer != NULL) && (strcmp(answer, expected) == 0);

	if (!matches) {
		printf("       [%s] trimmed to [%s], expected [%s]\n", input,
			answer != NULL ? answer : "(nil)", expected);
	}
	check(matches, what);
}

int main(void)
{
	@autoreleasepool {
		/* THE REGRESSION: a leading space, a two-byte character, no trailing space. */
		check_trim(" * Copyright \xc2\xa9 2026 Kyle J. Cardoza.",
			   "* Copyright \xc2\xa9 2026 Kyle J. Cardoza.",
			   "a multibyte character after a leading space does not over-run the range");
		check_trim("  \xc2\xa9  ", "\xc2\xa9", "multibyte on both sides of the trimmed run");

		/* THE ORDINARY CASES, which passed before and must keep passing. */
		check_trim("  hello  ", "hello", "leading and trailing spaces are both removed");
		check_trim("hello", "hello", "a string with nothing to trim is answered unchanged");
		check_trim("", "", "an empty string is empty");
		check_trim("   ", "", "a string of nothing but members trims to empty");
		check_trim("a  b", "a  b", "an interior run is NOT touched");
		/* APPLE'S TWO SETS ARE DIFFERENT SETS, and the door is the set's: `+whitespaceCharacterSet` is spaces and
		 * tabs (its own header says so, and this tree's does too), while newlines are in
		 * `+whitespaceAndNewlineCharacterSet`. The first version of this probe expected newlines to go and was
		 * measuring its own mistake. */
		check_trim("\t  value\t ", "value", "spaces and tabs are members of the whitespace set");
		{
			/* **THIS SET'S DEFINITION IS RECORDED IN NSCharacterSet.m AND THIS PROBE FOLLOWS IT RATHER THAN ITS OWN
			 * EXPECTATION.** That file's decision: `+whitespaceAndNewlineCharacterSet` is Z* plus LF, VT, FF, CR and
			 * NEL, and TAB is deliberately NOT in it — the tab lives in `+whitespaceCharacterSet` alone. So a
			 * newline is trimmed and a tab is not, and the assertion says exactly that. */
			NSString *newlines = [[NSString stringWithUTF8String:"\nvalue\r"]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			NSString *tabs = [[NSString stringWithUTF8String:"\tvalue\t"]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

			check([newlines isEqualToString:@"value"], "newlines are trimmed by the newline set");
			check([tabs isEqualToString:@"\tvalue\t"], "tabs are not, by that set's recorded definition");
		}
		{
			NSString *trimmed = [[NSString stringWithUTF8String:"\nvalue\n"]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

			check([trimmed isEqualToString:@"\nvalue\n"],
			      "a newline is NOT a member of the plain whitespace set");
		}

		/* AND THE RECEIVER IS UNCHANGED, because the answer is a new string. */
		{
			NSString *original = [NSString stringWithUTF8String:"  keep me  "];
			NSString *trimmed = [original stringByTrimmingCharactersInSet:
				[NSCharacterSet whitespaceCharacterSet]];

			check(strcmp([original UTF8String], "  keep me  ") == 0, "the receiver is not modified");
			check([trimmed isEqualToString:@"keep me"], "the answer is the trimmed copy");
		}

	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
