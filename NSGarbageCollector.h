/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSGarbageCollector.h — the collector's control surface, DECLARED AND HONESTLY INERT.
 *
 * This library has no garbage collector: the runtime is reference-counted and `-finalize` exists only so a class
 * written for a collected program compiles. The class is still part of the 10.6 surface, and every door has a
 * MEANING WITHOUT A COLLECTOR — `-collectIfNeeded` has nothing to collect, `-isCollecting` is NO because no
 * collection ever happens, and the enable/disable switches are stored and reported. That is the same treatment
 * `NSMakeCollectable` gets in NSObjStructRuntime: the documented behaviour of a program that is not collected.
 */
#ifndef FOUNDATION_NSGARBAGECOLLECTOR_H
#define FOUNDATION_NSGARBAGECOLLECTOR_H

#import <Foundation/NSObject.h>
#import <Foundation/NSZone.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSGarbageCollector : NSObject
{
@private
	BOOL _enabled;
}

+ (NSGarbageCollector *)defaultCollector;

- (void)disable;
- (void)enable;
- (BOOL)isEnabled;
- (BOOL)isCollecting;

- (void)collectIfNeeded;
- (void)collectExhaustively;

/* THESE TWO ARE ABOUT A POINTER THE COLLECTOR WOULD TRACK; with no collector they are no-ops, and the names are
 * still answerable so a class's `-finalize`-era code compiles. */
- (void)disableCollectorForPointer:(const void *)ptr;
- (void)enableCollectorForPointer:(const void *)ptr;

- (NSZone *)zone;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSGARBAGECOLLECTOR_H */
