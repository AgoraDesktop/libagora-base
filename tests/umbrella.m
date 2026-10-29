/*
 * umbrella — the Foundation umbrella header, measured: it compiles, and it names every header this library installs.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE SAME CENSUS THE APPKIT'S `tests/umbrella.m` MAKES, ONE LAYER DOWN.** `CMakeLists.txt` installs `*.h` with a
 * glob, so a header joins the installed surface the moment its file exists; the umbrella is the only thing that says
 * which of them a consumer should import, and it can drift without anything failing to build. This probe fails on
 * the header nobody classified.
 *
 * It found three real ones on its first run — `NSFastEnumeration.h`, `NSValueCGGeometry.h` and `NSCoderCGGeometry.h`
 * were installed and unnamed, so `for (id x in collection)` and the geometry bridges were missing from the umbrella
 * a consumer is told to use.
 *
 * **THE INTERNAL ONES ARE NAMED HERE, WHICH IS THE CLASSIFICATION.** The `FN*` headers are this library's own
 * machinery (`fn_` is the prefix the implementation uses), `NSTinyString` is how a short literal is represented,
 * `plist.h` is the C reader the property-list class is written on, and `*_internal.h` carries a class's workings.
 * `FNURLComponents.h` is NOT internal: `NSURLComponents.h` is written on it, so a consumer that asks for the class
 * needs the helper it stands on, and the umbrella names it.
 */
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>

static const char *s_internal[] = {
	/* This library's own machinery: the run loop's queue and modes, the wire formats, the tables under the
	 * collections, the websocket frames and handshake, the zone and the condition. */
	"FNArchiverWire", "FNAuthenticationChallengeSender", "FNCallStack", "FNCondition", "FNDistantObjectRequest",
	"FNKeyedWire", "FNLegacyMapTable", "FNObjectDeath", "FNPointerTable", "FNPredicatePrivate", "FNRunLoopModes",
	"FNRunLoopQueue", "FNSUbiquitousStore", "FNSpellServerDispatch", "FNStringFormat", "FNTextBreaking",
	"FNUserActivity", "FNWebSocketAssembler", "FNWebSocketFraming", "FNWebSocketHandshake", "FNZone",
	/* A representation and a parser rather than a class a consumer imports. */
	"NSTinyString", "plist",
	/* A class's workings. */
	"NSKeyValueObserving_internal",
	NULL,
};

static int s_failed;

static void check(int ok, const char *what)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		s_failed++;
	}
}

static int is_internal(const char *name)
{
	int i;

	for (i = 0; s_internal[i] != NULL; i++) {
		if (strcmp(s_internal[i], name) == 0) {
			return 1;
		}
	}
	return 0;
}

/* THE UMBRELLA'S OWN LIST, read as text: the includes ARE the specification, and a test that parsed them into
 * anything else would be testing the parser rather than the file a consumer compiles. */
static NSArray *umbrella_names(void)
{
	NSString *text = [NSString stringWithContentsOfFile:@FOUNDATION_UMBRELLA
						   encoding:NSUTF8StringEncoding
						      error:NULL];
	NSMutableArray *names = [NSMutableArray array];
	NSArray *lines;
	NSUInteger i;

	if (text == nil) {
		return names;
	}
	lines = [text componentsSeparatedByString:@"\n"];
	for (i = 0; i < [lines count]; i++) {
		NSString *line = lines[i];

		if (![line hasPrefix:@"#import <Foundation/"] || ![line hasSuffix:@".h>"]) {
			continue;
		}
		{
			NSString *rest = [line substringFromIndex:[@"#import <Foundation/" length]];

			[names addObject:[rest substringToIndex:[rest length] - [@".h>" length]]];
		}
	}
	return names;
}

static NSArray *installed_names(void)
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@FOUNDATION_SOURCE_DIR error:NULL];
	NSUInteger i;

	for (i = 0; i < [entries count]; i++) {
		NSString *entry = entries[i];

		/* THE UMBRELLA IS NOT ONE OF THE HEADERS IT HAS TO NAME. */
		if ([entry hasSuffix:@".h"] && ![entry isEqualToString:@"Foundation.h"]) {
			[names addObject:[entry substringToIndex:[entry length] - 2]];
		}
	}
	return names;
}

int main(void)
{
	@autoreleasepool {
		NSArray *umbrella = umbrella_names();
		NSArray *installed = installed_names();
		NSMutableArray *unclassified = [NSMutableArray array];
		NSUInteger i;

		printf("umbrella names %lu header(s); the source directory holds %lu\n",
			(unsigned long)[umbrella count], (unsigned long)[installed count]);

		check([umbrella count] > 100, "the umbrella names the surface rather than a sample of it");

		for (i = 0; i < [installed count]; i++) {
			if (![umbrella containsObject:installed[i]] && !is_internal([installed[i] UTF8String])) {
				[unclassified addObject:installed[i]];
			}
		}
		if ([unclassified count] > 0) {
			printf("       unclassified: %s\n", [[unclassified componentsJoinedByString:@", "] UTF8String]);
		}
		check([unclassified count] == 0, "every installed header is in the umbrella or named as internal");

		{
			NSMutableArray *dangling = [NSMutableArray array];

			for (i = 0; i < [umbrella count]; i++) {
				if (![installed containsObject:umbrella[i]]) {
					[dangling addObject:umbrella[i]];
				}
			}
			if ([dangling count] > 0) {
				printf("       dangling: %s\n", [[dangling componentsJoinedByString:@", "] UTF8String]);
			}
			check([dangling count] == 0, "every header the umbrella names exists");
		}

		{
			int both = 0;

			for (i = 0; i < [umbrella count]; i++) {
				if (is_internal([umbrella[i] UTF8String])) {
					printf("       both: %s\n", [umbrella[i] UTF8String]);
					both++;
				}
			}
			check(both == 0, "no header is both public and internal");
		}

		/* AND THE UMBRELLA PULLS THE CLASSES IN, so a passing include is not an empty file: one class from each band
		 * of the layer answers its own name. */
		check(NSClassFromString(@"NSString") != Nil, "the string class is reachable through the umbrella");
		check(NSClassFromString(@"NSArray") != Nil, "the collections are reachable");
		check(NSClassFromString(@"NSURL") != Nil, "the URL family is reachable");
		check(NSClassFromString(@"NSTask") != Nil, "the process family is reachable");
		check(NSClassFromString(@"NSJSONSerialization") != Nil, "serialisation is reachable");
		check(NSClassFromString(@"NSUndoManager") != Nil, "the undo manager is reachable");
		check(NSClassFromString(@"NSUserDefaults") != Nil, "the defaults store is reachable");
	}
	printf("%s\n", s_failed == 0 ? "all checks passed" : "FAILURES");
	return s_failed == 0 ? 0 : 1;
}
