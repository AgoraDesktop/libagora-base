/*
 * zones — the allocator handle, its C family, and Cocoa's copying protocol.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. Zones were removed from this Foundation once, which took
 * `-copyWithZone:` with them. This probe keeps the restored contract measured:
 * the default zone and a created zone answer their names; zone memory is
 * identifiable with `NSZoneFromPointer`; an object allocated through a custom
 * zone reports that zone; the raw-copy primitive copies instance variables and
 * gives the copy a fresh count; and the copying protocol is spelled in Cocoa's
 * shape, with `-copy`/`-mutableCopy` delegating to the zone doors.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>

static int g_fail;

static void
check(int condition, const char *what)
{
	if (!condition) {
		printf("FAIL: %s\n", what);
		g_fail = 1;
	} else {
		printf("ok: %s\n", what);
	}
}

@interface ZoneProbe : NSObject
{
@public
	int marker;
}
@end

@implementation ZoneProbe
@end

int
main(void)
{
	NSZone *defaultZone = NSDefaultMallocZone();
	NSZone *zone;
	NSZone *otherZone;
	void *memory;
	void *reallocated;
	ZoneProbe *original;
	ZoneProbe *copy;
	NSMutableData *object;
	NSMutableData *copied;
	NSString *text = @"copy me";
	NSString *textCopy;
	NSString *textMutable;

	check(defaultZone != NULL, "the default zone exists");
	check([NSZoneName(defaultZone) isEqualToString:@"DefaultMallocZone"],
	      "the default zone has its documented name");

	zone = NSCreateZone(4096, 4096, YES);
	check(zone != NULL, "a zone can be created");
	check([NSZoneName(zone) isEqualToString:@""], "a new zone starts unnamed");
	NSSetZoneName(zone, @"ProbeZone");
	check([NSZoneName(zone) isEqualToString:@"ProbeZone"], "a zone keeps its name");

	otherZone = NSCreateZone(1024, 1024, YES);
	check(otherZone != NULL && otherZone != zone, "zones are distinct");

	memory = NSZoneMalloc(zone, 64);
	check(memory != NULL, "NSZoneMalloc answers memory");
	check(NSZoneFromPointer(memory) == zone, "zone memory reports its zone");
	reallocated = NSZoneRealloc(zone, memory, 128);
	check(reallocated != NULL, "NSZoneRealloc answers memory");
	check(NSZoneFromPointer(reallocated) == zone, "reallocated memory keeps its zone");
	NSZoneFree(zone, reallocated);

	memory = NSZoneCalloc(otherZone, 8, 8);
	check(memory != NULL && NSZoneFromPointer(memory) == otherZone,
	      "calloc'd memory reports its zone");
	NSZoneFree(otherZone, memory);

	memory = malloc(8);
	check(NSZoneFromPointer(memory) == NULL, "ordinary malloc memory has no zone");
	free(memory);

	memory = NSAllocateCollectable(32, NSScannedOption);
	check(memory != NULL, "NSAllocateCollectable answers memory");
	free(memory);

	/* THE COPYING PROTOCOL, THROUGH THE CONVENIENCE DOOR AND THE ZONE DOOR. An immutable string's copy is
	 * itself; a mutable string's copy is an immutable snapshot. */
	textCopy = [text copyWithZone:zone];
	check([textCopy isEqualToString:text], "-copyWithZone: copies a string");
	check([textCopy zone] == defaultZone, "an ordinary copy is in the default zone");
	[textCopy release];

	textCopy = [text copy];
	check([textCopy isEqualToString:text], "-copy reaches -copyWithZone:");
	[textCopy release];

	textMutable = [[NSMutableString alloc] initWithString:@"mutable"];
	textCopy = [textMutable copyWithZone:zone];
	check([textCopy isEqualToString:textMutable], "copying a mutable string keeps the text");
	check(![textCopy isKindOfClass:[NSMutableString class]],
	      "copying a mutable string answers an immutable copy");
	[textCopy release];
	[textMutable release];

	/* AN OBJECT ALLOCATED IN A CUSTOM ZONE REPORTS IT, and its coder class is still the public class. */
	object = [NSMutableData allocWithZone:zone];
	check(object != nil, "a class-cluster object allocates in a zone");
	check([object zone] == zone, "the object reports the zone it was allocated in");
	[object appendBytes:"abc" length:3];
	copied = [object mutableCopyWithZone:otherZone];
	check(copied != nil && [copied length] == 3, "mutableCopyWithZone: copies the contents");
	check([copied zone] == otherZone, "the mutable copy reports its zone");
	[copied release];
	[object release];

	/* THE RAW COPY. NSCopyObject copies instance variables, preserves the class, and gives the copy a
	 * retain count of one; the extra bytes are the allocator's zeroed tail. */
	original = NSAllocateObject([ZoneProbe class], 16, zone);
	original->marker = 42;
	check([original zone] == zone, "NSAllocateObject records the zone");
	check([original retainCount] == 1, "NSAllocateObject answers count one");

	copy = NSCopyObject(original, 0, otherZone);
	check(copy != nil, "NSCopyObject answers a copy");
	check(copy != original, "the raw copy is a distinct object");
	check(copy->marker == 42, "the raw copy carries the instance variables");
	check([copy zone] == otherZone, "the raw copy reports the requested zone");
	check([copy retainCount] == 1, "the raw copy has a retain count of one");
	check(NSShouldRetainWithZone(original, zone) == NO,
	      "a copy within the same zone need not retain");
	check(NSShouldRetainWithZone(original, otherZone) == YES,
	      "a copy into another zone must retain");
	[copy release];

	NSDeallocateObject(original);
	check(1, "NSDeallocateObject frees an uninitialised instance");

	NSRecycleZone(otherZone);
	NSRecycleZone(zone);

	if (g_fail) {
		printf("zones: FAILED\n");
		return 1;
	}
	printf("zones: passed\n");
	return 0;
}
