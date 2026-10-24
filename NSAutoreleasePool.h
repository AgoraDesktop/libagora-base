/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAutoreleasePool.h — the boundary of an object-lifetime region (W2h, §14).
 *
 * THE POOL IS A STACK ENTRY, and the runtime already implements the stack: `-init` pushes and
 * `-drain` pops. This class is the boundary a program can SEE.
 *
 * THE PRIVATE MARKER BELOW IS NOT OPTIONAL, and that is a measured fact rather than a rumour.
 * libobjc2's arc.mm looks this class up BY NAME and then asks whether it implements
 * `-_ARCCompatibleAutoreleasePool`: if it DOES, the runtime keeps its fast ARC pool path and never
 * instantiates this class; if it does NOT, the runtime switches to its legacy GNUstep-style path and
 * binds `+new`, `-release` and `+addObject:` on this class instead — and the first autorelease under
 * that path reaches an unimplemented `+addObject:` and HALTS THE GUEST with a kernel dump. That was
 * measured, twice, before the cause was read out of the runtime. The selector's signature is
 * irrelevant here; its PRESENCE is the whole contract, and `+addObject:` staying out is safe
 * precisely because this marker keeps that path from being taken.
 */
#ifndef FOUNDATION_NSAUTORELEASEPOOL_H
#define FOUNDATION_NSAUTORELEASEPOOL_H

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSAutoreleasePool : NSObject
{
	void *_token;		/* the runtime's pool handle, from the push */
	BOOL _discarded;	/* a pool pops ONCE, however it is ended */
	BOOL _releasesOnDrain;	/* the 10.x diagnostic switch; remembered and reported */
	BOOL _checksFreedObjects;	/* ditto */
}

- (void)_ARCCompatibleAutoreleasePool;	/* THE RUNTIME ASKS FOR THIS BY NAME — see above */
- (void)drain;


/* §63.206: THE LEGACY TRIO, DEFINED ANYWAY. The note above is right that the marker keeps libobjc2 on its ARC
 * path, so nothing calls these today. They are defined regardless, because the legacy runtime path BINDS them
 * and the cost of being wrong is a halted guest: if that path is ever taken, the first autorelease lands on a
 * door whose meaning is unambiguous rather than on a missing one. */
+ (void)addObject:(id)object;
- (void)addObject:(id)object;
+ (void)showPools;

/*
 * THE 10.x DIAGNOSTIC FAMILY. These were the classic pool's instrumentation: how many objects it had released, how
 * deep the pool stack went, and the high-water marks a program tuned its pool placement with.
 *
 * WHAT THIS CLASS CAN AND CANNOT SEE, stated rather than faked: the RUNTIME owns the autorelease stack here (the
 * marker above keeps libobjc2 on its ARC path), so this class observes no per-object releases. The two counters
 * that name objects are therefore the ones this class was ASKED to add — which is zero on the ARC path and is the
 * truthful answer for a pool that does not see the releases. What IS real is the pool DEPTH (this class pushes and
 * pops it) and the two switches, which are remembered and reported because that is the whole of their contract.
 * `+resetTotalAutoreleasedObjects` resets the process-wide total; the high-water mark is what the depth has ever
 * reached and is not reset by it.
 */
- (NSUInteger)autoreleasedObjectCount;
+ (NSUInteger)totalAutoreleasedObjects;
+ (void)resetTotalAutoreleasedObjects;
- (NSUInteger)poolCountHighWaterMark;
- (void)setPoolCountHighWaterMark:(NSUInteger)count;
- (NSUInteger)poolCountHighWaterResolution;
- (void)setPoolCountHighWaterResolution:(NSUInteger)resolution;
- (NSUInteger)topAutoreleasePoolCount;
- (void)enableRelease:(BOOL)enable;
- (void)enableFreedObjectCheck:(BOOL)enable;
@end

NS_ASSUME_NONNULL_END
#endif /* FOUNDATION_NSAUTORELEASEPOOL_H */
