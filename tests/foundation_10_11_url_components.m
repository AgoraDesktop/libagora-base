/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_url_components.m — THE PUBLIC PARSER (10.9), MEASURED THROUGH ITS NAME.
 *
 * `NSURLComponents` is a declaration over `FNURLComponents`, so the parsing is already covered by the URL suite; what
 * THIS probe pins is the part the public class adds, plus the one rule the parser's contract rests on: components are
 * held ENCODED and rendered DECODED, so the six `percentEncoded…` setters must store exactly what they are given while
 * the plain setters encode, and `queryItems` must split on `&`/`=` and decode both halves without turning `+` into a
 * space (that is form encoding, not this class).
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

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
	NSURLComponents *c = [[NSURLComponents alloc] init];
	NSURLComponents *parsed;
	NSArray *items;
	NSURL *relative;

	/* ALL COMPONENTS UNDEFINED: -string is nil and -URL is nil. */
	if ([c string] != nil) {
		g_fail++;
		fprintf(stderr, "FAIL: a fresh components object renders a string\n");
	} else {
		g_pass++;
	}
	if ([c URL] != nil || [c queryItems] != nil) {
		g_fail++;
		fprintf(stderr, "FAIL: a fresh components object reports a URL or a query\n");
	} else {
		g_pass++;
	}

	/* THE PLAIN SETTER ENCODES; THE ENCODED SETTER DOES NOT. */
	[c setScheme:@"http"];
	[c setHost:@"example.com"];
	[c setPath:@"/a b"];	/* the space becomes %20 in the rendered string */
	expect([c string], "http://example.com/a%20b", "plain setters encode");
	expect([c percentEncodedPath], "/a%20b", "and the encoded getter shows the octets");
	[c setPercentEncodedPath:@"/a%20b"];	/* stored as given */
	expect([c path], "/a b", "the decoded getter decodes what was stored");
	expect([c string], "http://example.com/a%20b", "and the rendered string is unchanged");

	/* PARSING, THE OTHER DIRECTION. */
	parsed = [NSURLComponents componentsWithString:@"https://user:secret@example.com:8443/x/y?q=a%20b&flag#frag"];
	expect([parsed scheme], "https", "parse: scheme");
	expect([parsed user], "user", "parse: user");
	expect([parsed password], "secret", "parse: password");
	expect([parsed host], "example.com", "parse: host");
	if ([[parsed port] intValue] != 8443) {
		g_fail++;
		fprintf(stderr, "FAIL: parse: port\n");
	} else {
		g_pass++;
	}
	expect([parsed path], "/x/y", "parse: path");
	expect([parsed fragment], "frag", "parse: fragment");

	/* THE QUERY AS PAIRS: `?q=a%20b&flag` is two items, the second with a nil value. */
	items = [parsed queryItems];
	if ([items count] != 2) {
		g_fail++;
		fprintf(stderr, "FAIL: queryItems count %lu, want 2\n", (unsigned long)[items count]);
	} else {
		g_pass++;
	}
	expect([[items objectAtIndex:0] name], "q", "first item name");
	expect([[items objectAtIndex:0] value], "a b", "first item value is DECODED");
	expect([[items objectAtIndex:1] name], "flag", "second item name");
	if ([[items objectAtIndex:1] value] != nil) {
		g_fail++;
		fprintf(stderr, "FAIL: ?flag has a value\n");
	} else {
		g_pass++;
	}

	/* WRITING: BOTH HALVES ARE ENCODED, SO `&` AND `=` SURVIVE A ROUND TRIP, AND `+` IS NOT A SPACE. */
	[c setQueryItems:[NSArray arrayWithObjects:
			[NSURLQueryItem queryItemWithName:@"a" value:@"1&2"],
			[NSURLQueryItem queryItemWithName:@"b" value:@"x=y"],
			[NSURLQueryItem queryItemWithName:@"plus" value:@"1+1"],
			[NSURLQueryItem queryItemWithName:@"bare" value:nil], nil]];
	expect([c percentEncodedQuery], "a=1%262&b=x%3Dy&plus=1%2B1&bare", "queryItems encodes both halves");

	/* RELATIVE RESOLUTION KEEPS THE PATH RELATIVE. */
	[c setScheme:nil];
	[c setHost:nil];
	[c setPath:@"child"];
	[c setQueryItems:nil];
	relative = [c URLRelativeToURL:[NSURL URLWithString:@"http://example.com/dir/"]];
	expect([relative absoluteString], "http://example.com/dir/child", "URLRelativeToURL resolves the path");

	printf("foundation_10_11_url_components: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[c release];
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
