/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_ordered_set.m — THE ORDERED SET'S PREDICATE AND ENUMERATION HALF (10.7).
 *
 * W6's tail added the doors NSArray had and NSOrderedSet did not: the four options forms of the test searches, the two
 * locale descriptions, `-filteredOrderedSetUsingPredicate:` and the mutable `-filterUsingPredicate:`. What an ordered
 * set adds to a set is the ORDER, so that is what every check below is about: a filter that keeps the members must keep
 * them in the receiver's order, a reverse walk must answer the same index the forward one would, and a description must
 * render the members in position order with the array family's indentation rule.
 */
#import <Foundation/Foundation.h>
#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSMutableOrderedSet.h>
#import <Foundation/NSPredicate.h>

#include <stdio.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) { g_pass++; return; }
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* ---- the predicate doors: order kept, dedup kept, membership decided by the predicate ---- */
	{
		NSOrderedSet *source = [NSOrderedSet orderedSetWithArray:
			[NSArray arrayWithObjects:@"one", @"two", @"three", @"four", nil]];
		NSPredicate *longer = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
			(void)bindings;
			return [(NSString *)object length] > 3;
		}];
		NSOrderedSet *filtered = [source filteredOrderedSetUsingPredicate:longer];
		NSMutableOrderedSet *mutable = [NSMutableOrderedSet orderedSetWithArray:
			[NSArray arrayWithObjects:@"a", @"bb", @"ccc", @"dddd", nil]];

		check([filtered count] == 2 && [[filtered objectAtIndex:0] isEqualToString:@"three"] &&
		      [[filtered objectAtIndex:1] isEqualToString:@"four"],
		      "a filtered ordered set keeps only the members that pass, in the receiver's order");
		check([filtered isKindOfClass:[NSOrderedSet class]] && [filtered isKindOfClass:[NSMutableOrderedSet class]] == NO,
		      "the filtered answer is an immutable ordered set");
		[mutable filterUsingPredicate:longer];
		check([mutable count] == 1 && [[mutable objectAtIndex:0] isEqualToString:@"dddd"],
		      "the mutable filter removes in place and preserves the order of what it keeps");
		[mutable filterUsingPredicate:[NSPredicate predicateWithValue:NO]];
		check([mutable count] == 0, "a false predicate empties the set");
	}

	/* ---- the options forms of the test searches ---- */
	{
		NSOrderedSet *set = [NSOrderedSet orderedSetWithArray:
			[NSArray arrayWithObjects:@"zero", @"one", @"two", @"three", @"four", nil]];
		NSIndexSet *positions = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, 3)];
		__block NSUInteger visits = 0;
		NSUInteger forward;
		NSUInteger reverse;
		NSUInteger restricted;
		NSIndexSet *matches;

		forward = [set indexOfObjectWithOptions:0 passingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			(void)object; (void)index; (void)stop;
			return YES;
		}];
		reverse = [set indexOfObjectWithOptions:NSEnumerationReverse
					    passingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			(void)object; (void)index; (void)stop;
			return YES;
		}];
		check(forward == 0 && reverse == 4,
		      "the options walk changes DIRECTION: the first match is index 0 forward and 4 in reverse");
		restricted = [set indexOfObjectAtIndexes:positions
						  options:0
					      passingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			(void)index; (void)stop;
			return [(NSString *)object length] == 3;
		}];
		check(restricted == 1, "an index-set walk answers the index in the set, not in the walk");
		check([set indexOfObjectAtIndexes:positions
					   options:0
				       passingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			(void)object; (void)index; (void)stop;
			return NO;
		}] == NSNotFound, "no match answers NSNotFound");
		[set enumerateObjectsWithOptions:0 usingBlock:^(id object, NSUInteger index, BOOL *stop) {
			(void)object; (void)index;
			visits++;
			if (visits == 2) { *stop = YES; }
		}];
		check(visits == 2, "a block that stops the walk stops it at once");
		matches = [set indexesOfObjectsWithOptions:NSEnumerationReverse
					       passingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			(void)stop;
			return index % 2 == 0 && [object length] > 0;
		}];
		check([matches count] == 3 && [matches firstIndex] == 0 && [matches lastIndex] == 4,
		      "the exhaustive form answers every matching index, in the set's own numbering");
		matches = [set indexesOfObjectsAtIndexes:positions
						 options:NSEnumerationReverse
					     passingTest:^BOOL(id object, NSUInteger index, BOOL *stop) {
			(void)object; (void)index; (void)stop;
			return YES;
		}];
		check([matches count] == 3 && [matches firstIndex] == 1 && [matches lastIndex] == 3,
		      "the index-set exhaustive form stops at the set's bounds, in either direction");
		check([[set indexesOfObjectsWithOptions:0
					    passingTest:nil] count] == 0 &&
		      [set indexOfObjectWithOptions:0 passingTest:nil] == NSNotFound,
		      "a nil predicate answers the empty answer rather than raising");
	}

	/* ---- the locale descriptions ---- */
	{
		NSOrderedSet *set = [NSOrderedSet orderedSetWithArray:
			[NSArray arrayWithObjects:@"one", @"two", nil]];
		NSString *flat = [set descriptionWithLocale:nil];
		NSString *indented = [set descriptionWithLocale:nil indent:1];

		check([flat hasPrefix:@"{(\n"] && [flat hasSuffix:@")}"], "the locale description uses the set's own braces");
		check([flat rangeOfString:@"    one"].location != NSNotFound &&
		      [flat rangeOfString:@"\n    two"].location != NSNotFound,
		      "each member is one level in, one per line");
		check([indented rangeOfString:@"        one"].location != NSNotFound &&
		      [indented hasSuffix:@"    )}"],
		      "the indent: form moves the members and the closing brace by that many levels");
	}

	printf("foundation_10_11_ordered_set: %d of %d cases passed, %d failed\n",
	       g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
