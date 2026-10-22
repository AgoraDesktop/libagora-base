/*
 * linguistic_units — the "Calculating linguistic units" group of NSAttributedString, and the group is why
 * this file exists.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * FOUR DOORS, ONE CONCERN. `-doubleClickAtIndex:`, `-nextWordFromIndex:forward:`,
 * `-lineBreakBeforeIndex:withinRange:` and `-lineBreakByHyphenatingBeforeIndex:withinRange:` are the group
 * AppKit files under "Calculating linguistic units", and until this file NOT ONE OF THEM WAS EXERCISED
 * ANYWHERE in the tree: a grep for any of the four names across every `.m` and `.c` in the repository found
 * `NSAttributedString.m` and `NSAttributedString.h` and nothing else. They were built, they were commented at
 * length, and nothing asked them a question. That gap is what this file closes, and it is why the four are
 * together rather than one file per door: they are one API surface with one dependency (`FNTextBreaking`, and
 * for the fourth `libagora-core/CFHyphenation.c`), and a door added to the group belongs here.
 *
 * EACH CASE STATES THE READING THIS LIBRARY TOOK, because Apple's phrases leave room and a probe has to
 * assert SOMETHING. Where the room is `-nextWordFromIndex:forward:` answering "the index unchanged when the
 * walk would pass either end", the case asserts the unchanged index; where it is `-lineBreakBeforeIndex:` and
 * whether its answer is a WRAP opportunity or a hard line, the case asserts the hard line and says so, because
 * that is the only line this tree has.
 *
 * THE HYPHENATION DOOR IS THE ONE THAT DEPENDS ON THE MACHINE. It asks Core Foundation, and Core Foundation
 * reads whatever dictionary the system installs, so a machine with no `hyph_en_US.dic` cannot make these
 * assertions and must not fail for it: the case asks `CFStringIsHyphenationAvailableForLocale` first, prints
 * what it found, and asserts the resource's ABSENT contract instead of its answers. What it never does is
 * pretend — a skipped measurement says so on stdout.
 */
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

static int g_pass, g_fail;

static void check(int ok, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	if (ok) {
		g_pass++;
	} else {
		g_fail++;
		fprintf(stderr, "FAIL: ");
		vfprintf(stderr, fmt, ap);
		fprintf(stderr, "\n");
	}
	va_end(ap);
}

/* ONE CASE PER FORKED CHILD, so a door that segfaults is a failing case rather than a dead suite — the same
 * arrangement `bridges.m` uses, for the same reason: these doors walk strings through ICU and through a
 * pattern trie, and a bug in either is exactly the kind that takes the process with it. */
static int run_in_child(const char *name, int (*fn)(void))
{
	pid_t pid;
	int status;

	fflush(NULL);
	pid = fork();
	if (pid == 0) {
		_exit(fn() == 0 ? 0 : 1);
	}
	if (pid < 0) {
		fprintf(stderr, "FAIL: %s: fork failed\n", name);
		return 1;
	}
	if (waitpid(pid, &status, 0) < 0) {
		fprintf(stderr, "FAIL: %s: waitpid failed\n", name);
		return 1;
	}
	if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
		printf("ok   %s\n", name);
		return 0;
	}
	if (WIFSIGNALED(status)) {
		fprintf(stderr, "FAIL: %s: killed by signal %d\n", name, WTERMSIG(status));
	} else {
		fprintf(stderr, "FAIL: %s: checks failed\n", name);
	}
	return 1;
}

/* =================================================================================================
 * THE FOUR DOORS.
 * =============================================================================================== */
/* **THE WORD QUESTIONS ARE ONE WALK OVER `FNTextBreaking`, SEEN TWO WAYS**, and the readings worth pinning are
 * the two the header names: `-doubleClickAtIndex:` answers the WHOLE TOKEN including a space (which is what a
 * double-click on a space selects), and `-nextWordFromIndex:forward:` answers a word START on the asked-for
 * side WITHOUT requiring the index to be inside a word, and answers the index UNCHANGED when the walk would
 * pass either end. */
static int case_word_units(void)
{
	NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"the quick brown fox"];
	NSRange word;

	word = [text doubleClickAtIndex:5];
	printf("  (double-click at 5 is (%lu,%lu); at 3, the space, is ", (unsigned long)word.location,
	       (unsigned long)word.length);
	{
		NSRange space = [text doubleClickAtIndex:3];

		printf("(%lu,%lu))\n", (unsigned long)space.location, (unsigned long)space.length);
	}
	check(word.location == 4 && word.length == 5,
	      "the word at index 5 is `quick` at (4,5), not (%lu,%lu)", (unsigned long)word.location,
	      (unsigned long)word.length);
	/* A SPACE IS A TOKEN TOO, and that is the reading the header records rather than a guess: the substrate's
	 * word unit reports the separator run as a unit of its own. */
	{
		NSRange space = [text doubleClickAtIndex:3];

		check(space.location == 3 && space.length == 1,
		      "a double-click on the space at 3 selects the space itself, not (%lu,%lu)",
		      (unsigned long)space.location, (unsigned long)space.length);
	}
	check([text nextWordFromIndex:5 forward:YES] == 10, "the next word after 5 starts at 10 (`brown`)");
	check([text nextWordFromIndex:15 forward:YES] == 16, "the next word after 15 starts at 16 (`fox`)");
	check([text nextWordFromIndex:10 forward:NO] == 4, "the previous word before 10 starts at 4 (`quick`)");
	/* AN INDEX INSIDE A WORD IS THE CASE THE DOOR IS DOCUMENTED FOR, and it is the one where "the next word" and
	 * "the previous word" both have answers that are NOT the word the index sits in. */
	check([text nextWordFromIndex:6 forward:YES] == 10 && [text nextWordFromIndex:6 forward:NO] == 4,
	      "from inside `quick` the walk forward reaches 10 and the walk back reaches 4");
	/* AND THE TWO ENDS, WHERE APPLE'S SENTENCE IS THE WHOLE CONTRACT: "returned unchanged when the walk would
	 * pass either end" is the reading this library took, and both directions are asserted because a walk that
	 * only guarded one end would pass one of them. */
	check([text nextWordFromIndex:0 forward:NO] == 0, "there is no word before 0, so the index is unchanged");
	check([text nextWordFromIndex:19 forward:YES] == 19, "there is no word after the end, so the index is unchanged");
	return g_fail;
}

/* **THE LINE DOOR ANSWERS THE HARD LINE, AND THAT IS A CHOICE WORTH ASSERTING.** Apple calls the result "the
 * closest character before index that can be placed on a new line" and does not pin whether that is a WRAP
 * opportunity or a hard line break. This tree has only the hard line — `FNTextBreaking`'s line unit ends at LF,
 * CR, NEL, LS or PS — so the answer is a line START, and an index that stands at one answers ITSELF. */
static int case_line_break(void)
{
	NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"one\ntwo\nthree"];

	check([text lineBreakBeforeIndex:6 withinRange:NSMakeRange(0, 13)] == 4,
	      "the line containing index 6 begins at 4");
	check([text lineBreakBeforeIndex:4 withinRange:NSMakeRange(0, 13)] == 4,
	      "an index standing at a line start answers ITSELF");
	check([text lineBreakBeforeIndex:0 withinRange:NSMakeRange(0, 13)] == 0, "the first line begins at 0");
	check([text lineBreakBeforeIndex:13 withinRange:NSMakeRange(0, 13)] == 8,
	      "the last line begins at 8, so index 13 answers 8");
	/* THE RANGE FILTERS THE ANSWER rather than the walk: a range that starts inside the line RETURNS NOTHING
	 * for it, because the line's own start lies outside the range and reporting the clamped start would report
	 * a break that is not there. That is the reading the body records, and this is the check that holds it. */
	check([text lineBreakBeforeIndex:6 withinRange:NSMakeRange(5, 8)] == NSNotFound,
	      "a range that begins inside the line holds no line start, so the answer is NSNotFound");
	check([text lineBreakBeforeIndex:6 withinRange:NSMakeRange(0, 0)] == NSNotFound,
	      "an empty range holds no line start either");
	return g_fail;
}

/* **THE HYPHENATION DOOR, WHICH IS THE ONE THAT ASKS CORE FOUNDATION.** It owns no algorithm and no data:
 * `CFStringGetHyphenationLocationBeforeIndex` does, and this door is its caller. What is asserted here is the
 * DOOR's part of that arrangement — the answer is the last resource break before `index` inside the range, the
 * range is respected, there is NO FALLBACK to a line break, and a string with nothing to hyphenate answers
 * NSNotFound rather than a wrong index. */
static int case_hyphenating_break(void)
{
	NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"hyphenation"];
	NSAttributedString *spaced = [[NSAttributedString alloc] initWithString:@"hyphenation "];
	NSAttributedString *ox = [[NSAttributedString alloc] initWithString:@"ox"];
	CFLocaleRef current = CFLocaleCopyCurrent();
	Boolean available = (current != NULL) && CFStringIsHyphenationAvailableForLocale(current);

	printf("  (the current locale %s hyphenation data)\n", available ? "has" : "does NOT have");
	if (current != NULL) {
		CFRelease(current);
	}
	if (!available) {
		/* THE ABSENT CASE IS STILL A CASE: Apple documents the availability door as the way to find out
		 * whether there is data at all, so a machine without a dictionary asserts what this door promises
		 * instead — NSNotFound, not a wrong index and not a crash. */
		check([text lineBreakByHyphenatingBeforeIndex:11 withinRange:NSMakeRange(0, 11)] == NSNotFound,
		      "with no dictionary the door answers NSNotFound");
		check([ox lineBreakByHyphenatingBeforeIndex:2 withinRange:NSMakeRange(0, 2)] == NSNotFound,
		      "and does so for a short word too");
		return g_fail;
	}
	check([text lineBreakByHyphenatingBeforeIndex:11 withinRange:NSMakeRange(0, 11)] == 6,
	      "the last break before the end of `hyphenation` is 6 (hy-phen-ation)");
	check([text lineBreakByHyphenatingBeforeIndex:6 withinRange:NSMakeRange(0, 11)] == 2,
	      "and the one before that is 2, so the walk backwards works");
	check([text lineBreakByHyphenatingBeforeIndex:2 withinRange:NSMakeRange(0, 11)] == NSNotFound,
	      "nothing hyphenates before index 2");
	/* THE RANGE IS THE RESOURCE'S OWN LIMIT, passed straight through: an answer outside it is not an answer. */
	check([text lineBreakByHyphenatingBeforeIndex:11 withinRange:NSMakeRange(0, 6)] == 2,
	      "a range that excludes 6 leaves 2 as the answer");
	check([text lineBreakByHyphenatingBeforeIndex:11 withinRange:NSMakeRange(7, 4)] == NSNotFound,
	      "a range that begins past every break point holds none");
	check([text lineBreakByHyphenatingBeforeIndex:11 withinRange:NSMakeRange(0, 0)] == NSNotFound,
	      "an empty range holds none either, which is the resource's own printed contract");
	/* **AND IT DOES NOT FALL BACK TO A LINE BREAK.** `ox` is one line and `lineBreakBeforeIndex:` would
	 * happily answer 0 for it; this door must not, or the two doors of the group would be the same door under
	 * two names and a caller could not choose between hyphenating and not. */
	check([ox lineBreakBeforeIndex:2 withinRange:NSMakeRange(0, 2)] == 0,
	      "the LINE door answers 0 for `ox`, which is the line it is on");
	check([ox lineBreakByHyphenatingBeforeIndex:2 withinRange:NSMakeRange(0, 2)] == NSNotFound,
	      "and the HYPHENATING door answers NSNotFound for it rather than borrowing that 0");
	/* THE SAME PROOF WITH A WORD THAT HAS BREAKS: past the end of `hyphenation` the line door would answer the
	 * line start and this one has nothing, because there is no hyphenation point between 6 and 11. */
	check([text lineBreakByHyphenatingBeforeIndex:11 withinRange:NSMakeRange(7, 4)] == NSNotFound
	      && [text lineBreakBeforeIndex:11 withinRange:NSMakeRange(7, 4)] == NSNotFound,
	      "and where neither has an answer the two agree on NSNotFound");
	/* A LOCATION WHOSE PREDECESSOR IS NOT A LETTER HAS NO HYPHENATION POINT BEFORE IT, which is the resource's
	 * rule and therefore this door's: a hyphen goes INSIDE a word. */
	check([spaced lineBreakByHyphenatingBeforeIndex:12 withinRange:NSMakeRange(0, 12)] == NSNotFound,
	      "a location after a space has no hyphenation point before it");
	return g_fail;
}

/* **AND THE FOUR PRECONDITIONS, WHICH ARE APPLE'S AND ARE ONE RULE.** Each door declares an index into the
 * string and a range within it as REQUIREMENTS rather than as questions, so an out-of-bounds one raises
 * NSRangeException — measured per door, because a group whose doors disagreed about their own preconditions
 * would be four doors with four contracts rather than one. */
static int case_range_preconditions(void)
{
	NSAttributedString *text = [[NSAttributedString alloc] initWithString:@"hyphenation"];
	NSArray *calls = @[
		^{ (void)[text doubleClickAtIndex:11]; },
		^{ (void)[text nextWordFromIndex:12 forward:YES]; },
		^{ (void)[text lineBreakBeforeIndex:12 withinRange:NSMakeRange(0, 11)]; },
		^{ (void)[text lineBreakBeforeIndex:11 withinRange:NSMakeRange(6, 11)]; },
		^{ (void)[text lineBreakByHyphenatingBeforeIndex:12 withinRange:NSMakeRange(0, 11)]; },
		^{ (void)[text lineBreakByHyphenatingBeforeIndex:11 withinRange:NSMakeRange(6, 11)]; },
	];
	NSUInteger i;

	check([text length] == 11, "the case's own string is eleven characters, not %lu", (unsigned long)[text length]);
	for (i = 0; i < [calls count]; i++) {
		@try {
			void (^call)(void) = [calls objectAtIndex:i];

			call();
			check(0, "call %lu did not raise for an out-of-bounds argument", (unsigned long)i);
		} @catch (NSException *e) {
			check([[e name] isEqualToString:NSRangeException],
			      "call %lu raised %s rather than NSRangeException", (unsigned long)i, [[e name] UTF8String]);
		}
	}
	return g_fail;
}

/* =================================================================================================
 * THE SUITE.
 * =============================================================================================== */
static const struct { const char *name; int (*fn)(void); } g_cases[] = {
	{ "The word at an index, and the next word's start either way", case_word_units },
	{ "The line an index sits on, and the range that may hold its start", case_line_break },
	{ "The hyphenating break, which asks Core Foundation rather than guessing", case_hyphenating_break },
	{ "The group's four preconditions raise NSRangeException", case_range_preconditions },
};

int main(void)
{
	size_t i, total = sizeof g_cases / sizeof g_cases[0];
	int passed = 0, failed = 0;

	setvbuf(stdout, NULL, _IONBF, 0);
	for (i = 0; i < total; i++) {
		if (run_in_child(g_cases[i].name, g_cases[i].fn) == 0) {
			passed++;
		} else {
			failed++;
		}
	}
	printf("linguistic_units: %d of %d cases passed, %d failed\n", passed, passed + failed, failed);
	return failed == 0 ? 0 : 1;
}
