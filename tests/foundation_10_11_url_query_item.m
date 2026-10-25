/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_url_query_item.m — THE PAIR, AS A VALUE (10.10).
 *
 * `NSURLQueryItem` is four doors and three protocols, and every one of them is about the pair being a VALUE rather
 * than a pair of pointers: two items built from the same two strings are equal and hash alike, a copy is stable when
 * the caller edits the string it handed in, and an archive round-trips through an allow-list. Those are the three
 * things a `NSURLComponents -queryItems` array depends on, which is why they are measured before the components class
 * that consumes them.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) {
		g_pass++;
		return;
	}
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSURLQueryItem *item = [NSURLQueryItem queryItemWithName:@"q" value:@"a b"];
	NSURLQueryItem *same = [[[NSURLQueryItem alloc] initWithName:@"q" value:@"a b"] autorelease];
	NSURLQueryItem *other = [NSURLQueryItem queryItemWithName:@"q" value:@"a c"];
	NSURLQueryItem *flag = [NSURLQueryItem queryItemWithName:@"flag" value:nil];
	NSMutableString *mutable;
	NSURLQueryItem *copied;
	NSData *archive;
	NSURLQueryItem *restored;

	check([[item name] isEqualToString:@"q"], "the name is the name given");
	check([[item value] isEqualToString:@"a b"], "the value is the value given, NOT percent-encoded");
	check([item isEqual:same] && [same isEqual:item], "two items built from the same strings are equal");
	check([item hash] == [same hash], "and hash alike");
	check(![item isEqual:other], "a different value is a different item");
	check(![item isEqual:flag] && ![flag isEqual:item], "a nil value is not the empty string");
	check([flag value] == nil, "?flag has no value");
	check(![item isEqual:(id)@"q=a b"], "an item is not equal to a string that spells it");

	/* A COPY IS IMMUTABLE BY CONSTRUCTION. The caller may edit the string it handed in; the item keeps the old text. */
	mutable = [[NSMutableString alloc] initWithString:@"original"];
	copied = [[NSURLQueryItem alloc] initWithName:@"k" value:mutable];
	[mutable appendString:@"-edited"];
	check([[copied value] isEqualToString:@"original"], "the item copied the string it was given");
	check([copied copy] == copied, "and its copy is the same immutable object");
	[copied release];
	[mutable release];

	/* THE ARCHIVE ROUND-TRIPS THROUGH NSCoder, which is what NSSecureCoding promises. */
	archive = [NSKeyedArchiver archivedDataWithRootObject:item];
	check(archive != nil, "a query item archives");
	restored = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
	check([restored isKindOfClass:[NSURLQueryItem class]] && [restored isEqual:item], "and unarchives equal");
	check([NSURLQueryItem supportsSecureCoding], "the class states that it supports secure coding");

	printf("foundation_10_11_url_query_item: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
