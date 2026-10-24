/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSNull.m — the object that stands for "nothing" (F13.8c). MANUAL OWNERSHIP.
 *
 * THE SINGLETON IS ENFORCED AT ALLOCATION, which is the part worth writing down: +null alone would
 * leave `[[NSNull alloc] init]` free to build a second one, and then two "the null object"s would
 * not be equal to each other. Routing allocWithZone: through the shared instance makes every door
 * answer THE instance.
 */

#import <Foundation/NSNull.h>
#include "FNZone.h"
#import <Foundation/NSString.h>

static NSNull *fn_shared_null = nil;

@implementation NSNull

+ (NSNull *)null
{
	/* The one place a new instance is made, and it goes to the SUPERCLASS's allocator — `[super
	 * allocWithZone:]`, NOT `[NSObject allocWithZone:]`: the former keeps `self` (so the instance is
	 * an NSNull) and skips this class's override, while the latter INSTANTIATES NSObject and answers
	 * something that is not an NSNull at all. Measured the hard way: the wrong spelling made +null
	 * hand back a plain NSObject, which then aborted on -copy. */
	if (fn_shared_null == nil) {
		fn_shared_null = [super allocWithZone:NSDefaultMallocZone()];
	}
	return fn_shared_null;
}

/* THE SINGLETON DOOR IS +allocWithZone:, COCOA'S ALLOCATION POINT. It answers the shared instance and
 * records the requested zone on it, so a caller that asks for the singleton in a zone gets the singleton
 * that reports that zone. `isEqual:`'s signature still matches NSObject's own, because a re-declaration
 * may not disagree with what it overrides. */
+ (instancetype)allocWithZone:(NSZone *)zone
{
	/* THIS ANSWERS +1, AND THAT IS THE WHOLE CONTRACT OF AN `alloc`-FAMILY METHOD (fixed
	 * 2026-09-20, and the bug it fixes had been invisible since the class landed). Returning the
	 * shared instance BARE over-released the singleton under ANY ARC caller: `alloc`/`new`/`copy`
	 * are the "owned" families, so ARC owns this result and releases it at the end of the scope —
	 * and that release had no matching retain here. Measured, in three lines:
	 *
	 *     one = [NSNull null]; two = [NSNull null]; made = [[NSNull alloc] init];
	 *
	 * leaves the count at 3 (a base 1 from +null's own alloc, plus ONE retain per +null — the
	 * `made` line adds none), while ARC emits THREE releases at the end of that scope. So the
	 * count reached 0 and the singleton was FREED; the next `[NSNull null]` then returned a
	 * dangling pointer and `objc_retainAutoreleasedReturnValue` died reading its `isa`. What it
	 * read there was glibc's tcache safe-linking word in the freed chunk's own first slot, where
	 * musl leaves the chunk intact — which is exactly why the guest never showed this and the
	 * host run did.
	 *
	 * THE RETAIN BELOW IS WHAT BALANCES IT, and it is permanent by design: the object is a
	 * singleton, so its count is a formality and the instance is never meant to die. */
	NSNull *shared = [[self null] retain];

	if (zone != NULL) {
		fn_zone_assign_pointer(shared, zone);
	}
	return shared;
}

- (BOOL)isEqual:(id)other
{
	/* ⚠⚠ NOT POINTER IDENTITY, BECAUSE THERE ARE TWO NULLS (2026-10-21, issue 6). `+null` above makes
	 * Foundation's singleton, and Core Foundation has its own — `kCFNull`, an instance of `__NSCFNull`,
	 * which is the subclass `cf_bridged_subclass` builds OVER THIS CLASS. They are different pointers to
	 * the same object, which is the whole premise of toll-free bridging, so a null that refused every
	 * other representation of itself would break the agreement the bridge exists to keep.
	 *
	 * MEASURED, AND IT IS WHY THIS WENT UNNOTICED: `CFEqual([NSNull null], kCFNull)` answered TRUE on
	 * x86-64 and FALSE on aarch64. Neither answer came from here — x86-64 was reading the low byte of a
	 * POINTER, because Core Foundation's dispatch macro typed the send as `id` and assumed an object came
	 * back (CFRuntime.c, now cast to `id<__CFBridgedMethods>`). The bug was invisible on one platform
	 * only because that garbage happened to be odd. With the send typed properly, this method's answer is
	 * the answer on both — which is why the positive case has to be here and not left to luck. */
	return other == self || [other isKindOfClass:[NSNull class]];
}

/* A CONSTANT, because there is only ever one: any two "null objects" ARE the same object, so any
 * constant will do and this one spells the class. */
- (NSUInteger)hash
{
	return (NSUInteger)0x6e756c6c;
}

- (NSString *)description
{
	return @"<null>";
}

+ (NSString *)description
{
	return @"<null>";
}

/* +1, THE SAME REASON `+alloc` ABOVE ANSWERS +1 (fixed 2026-09-20): `-copy` belongs to the copy
 * family, so its result is OWNED by the caller and ARC releases it. `return self` therefore released
 * the singleton once more than it had been retained — the identical over-release, reached through
 * the other door a program uses. The class stays immutable (the copy IS the receiver); only the
 * ownership answer changes. */
- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return [self retain];
}

@end
