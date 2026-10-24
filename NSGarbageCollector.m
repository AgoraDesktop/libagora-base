/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSGarbageCollector.m — the no-collector answers, each of which is documented behaviour rather than a stub.
 */
#import <Foundation/NSGarbageCollector.h>

@implementation NSGarbageCollector

+ (NSGarbageCollector *)defaultCollector
{
	static NSGarbageCollector *collector = nil;

	if (collector == nil) {
		collector = [[self alloc] init];
	}
	return collector;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_enabled = YES;		/* Apple's default: a collected program collects unless told not to */
	}
	return self;
}

- (void)disable { _enabled = NO; }
- (void)enable { _enabled = YES; }
- (BOOL)isEnabled { return _enabled; }

/* NO COLLECTION EVER HAPPENS HERE, so this is not a flag that can be stale: there is no collector whose work could be
 * in progress. */
- (BOOL)isCollecting { return NO; }

- (void)collectIfNeeded
{
}

- (void)collectExhaustively
{
}

- (void)disableCollectorForPointer:(const void *)ptr { (void)ptr; }
- (void)enableCollectorForPointer:(const void *)ptr { (void)ptr; }

- (NSZone *)zone
{
	return NSDefaultMallocZone();
}

@end
