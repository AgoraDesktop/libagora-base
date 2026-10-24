/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAutoreleasePool.m — the implementation (W2h).
 */
#include <unistd.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>
#import <Foundation/NSString.h>
#import <objc/objc-arc.h>
#include <pthread.h>

/* THE PROCESS-WIDE DIAGNOSTIC STATE. One mutex, because a pool is made on any thread and the totals are shared. */
static pthread_mutex_t fn_pool_stats_lock = PTHREAD_MUTEX_INITIALIZER;
static NSUInteger fn_total_autoreleased = 0;
static NSUInteger fn_pool_depth = 0;
static NSUInteger fn_pool_high_water = 0;
static NSUInteger fn_pool_high_water_resolution = 0;

@implementation NSAutoreleasePool

/* THE MARKER: implemented, never called by us, and what keeps the runtime on its fast ARC pool path
 * (see the header). An empty body is correct — the runtime only asks whether the method EXISTS. */
- (void)_ARCCompatibleAutoreleasePool
{
}

- (instancetype)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_token = objc_autoreleasePoolPush();
	_discarded = NO;
	_releasesOnDrain = YES;
	_checksFreedObjects = NO;
	pthread_mutex_lock(&fn_pool_stats_lock);
	fn_pool_depth++;
	if (fn_pool_depth > fn_pool_high_water) {
		fn_pool_high_water = fn_pool_depth;
	}
	pthread_mutex_unlock(&fn_pool_stats_lock);
	return self;
}

/* ENDING THE REGION: -drain and -release are the same operation, which is Cocoa's own statement
 * about a reference-counted pool, and the flag is what makes a second call harmless. */
- (void)drain
{
	if (!_discarded) {
		_discarded = YES;
		pthread_mutex_lock(&fn_pool_stats_lock);
		if (fn_pool_depth > 0) {
			fn_pool_depth--;
		}
		pthread_mutex_unlock(&fn_pool_stats_lock);
		objc_autoreleasePoolPop(_token);
	}
}

- (oneway void)release
{
	[self drain];
}

- (void)dealloc
{
	[self drain];
	[super dealloc];
}

- (instancetype)retain
{
	[NSException raise:NSInternalInconsistencyException
		    format:@"Cannot retain an autorelease pool: it bounds a region, and a pool that "
			   "outlived that region would hold objects with no boundary to release them at"];
	return self;
}

- (NSUInteger)retainCount
{
	return 1;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@: %p>", [self class], (void *)self];
}


+ (void)addObject:(id)object
{
	/* THE LEGACY RUNTIME'S OWN MEANING: add the object to the current pool — which, for a class whose pool IS
	 * a runtime stack entry, is exactly -autorelease. Nothing calls this while the marker keeps libobjc2 on
	 * its ARC path; if that ever changes, an autorelease lands HERE instead of halting the guest. */
	pthread_mutex_lock(&fn_pool_stats_lock);
	fn_total_autoreleased++;
	pthread_mutex_unlock(&fn_pool_stats_lock);
	[object autorelease];
}

- (void)addObject:(id)object
{
	/* THE INSTANCE FORM, reading stated: this class is a STACK ENTRY and keeps no object list, so it cannot
	 * target a particular pool. Adding an object to a pool means autoreleasing it into the current region —
	 * the same thing the class-side door does, and what the legacy path asks for. */
	[object autorelease];
}

- (NSUInteger)autoreleasedObjectCount
{
	return 0;	/* this pool observes no releases: the runtime owns the stack (see the header) */
}

+ (NSUInteger)totalAutoreleasedObjects
{
	NSUInteger total;

	pthread_mutex_lock(&fn_pool_stats_lock);
	total = fn_total_autoreleased;
	pthread_mutex_unlock(&fn_pool_stats_lock);
	return total;
}

+ (void)resetTotalAutoreleasedObjects
{
	pthread_mutex_lock(&fn_pool_stats_lock);
	fn_total_autoreleased = 0;
	pthread_mutex_unlock(&fn_pool_stats_lock);
}

- (NSUInteger)poolCountHighWaterMark
{
	NSUInteger mark;

	pthread_mutex_lock(&fn_pool_stats_lock);
	mark = fn_pool_high_water;
	pthread_mutex_unlock(&fn_pool_stats_lock);
	return mark;
}

- (void)setPoolCountHighWaterMark:(NSUInteger)count
{
	pthread_mutex_lock(&fn_pool_stats_lock);
	fn_pool_high_water = count;
	pthread_mutex_unlock(&fn_pool_stats_lock);
}

- (NSUInteger)poolCountHighWaterResolution
{
	NSUInteger resolution;

	pthread_mutex_lock(&fn_pool_stats_lock);
	resolution = fn_pool_high_water_resolution;
	pthread_mutex_unlock(&fn_pool_stats_lock);
	return resolution;
}

- (void)setPoolCountHighWaterResolution:(NSUInteger)resolution
{
	pthread_mutex_lock(&fn_pool_stats_lock);
	fn_pool_high_water_resolution = resolution;
	pthread_mutex_unlock(&fn_pool_stats_lock);
}

- (NSUInteger)topAutoreleasePoolCount
{
	NSUInteger depth;

	pthread_mutex_lock(&fn_pool_stats_lock);
	depth = fn_pool_depth;
	pthread_mutex_unlock(&fn_pool_stats_lock);
	return depth;
}

- (void)enableRelease:(BOOL)enable
{
	_releasesOnDrain = enable;
}

- (void)enableFreedObjectCheck:(BOOL)enable
{
	_checksFreedObjects = enable;
}

+ (void)showPools
{
	/* A TRUTHFUL DIAGNOSTIC RATHER THAN A PRETENDED LISTING: pools here ARE the runtime's stack entries and
	 * this class keeps no registry to print. Raw write(2), because a library diagnostic must not depend on
	 * printf. */
	static const char line[] =
		"NSAutoreleasePool: pools are runtime stack entries; this class keeps no registry\n";

	(void)write(2, line, sizeof(line) - 1);
}
@end
