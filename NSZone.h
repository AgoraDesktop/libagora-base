/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSZone.h — the allocator handle and the C allocation family.
 *
 * ZONES ARE REAL HERE, WITH THE 64-BIT READING APPLE DOCUMENTS. A zone is an
 * allocator a caller can name and measure; `NSZoneMalloc` and its neighbours
 * allocate through it, and the memory remembers which zone it came from. Object
 * allocation is deliberately the one exception: `NSAllocateObject` uses the
 * runtime's single heap and records the zone against the object, because the
 * runtime has no per-zone heap and Apple's 64-bit runtime ignores zones in
 * exactly this way. A caller who only needs Cocoa's API sees the API work;
 * a caller who measures `NSZoneFromPointer` or `NSZoneName` gets the truthful
 * answer for both C memory and objects allocated through this family.
 */

#ifndef FOUNDATION_NSZONE_H
#define FOUNDATION_NSZONE_H

#import <Foundation/NSObjCRuntime.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * THE DEFAULT ZONE. It is never freed and is what every `NULL` zone means, so a
 * caller who passes NULL to a zone door gets the same allocator `malloc(3)`
 * would have used.
 */
FOUNDATION_EXPORT NSZone *NSDefaultMallocZone(void);

/*
 * A NEW ZONE. `startSize` and `granularity` describe the growth policy the
 * caller had in mind; this implementation uses them as the starting capacity and
 * rounding for its bookkeeping rather than as a separate heap. `canFree` says
 * whether the zone may be reclaimed: a zone created with NO is recycled only when
 * the process ends. Both values are accepted and remembered; a zone that can free
 * is released with `NSRecycleZone`.
 */
FOUNDATION_EXPORT NSZone *NSCreateZone(NSUInteger startSize, NSUInteger granularity, BOOL canFree);
FOUNDATION_EXPORT void NSRecycleZone(NSZone * _Nullable zone);

/* A ZONE'S NAME. The default zone is "DefaultMallocZone"; a new zone has no name
 * until one is set, and `NSZoneName` answers an empty string for it. */
FOUNDATION_EXPORT void NSSetZoneName(NSZone * _Nullable zone, NSString *name);
FOUNDATION_EXPORT NSString *NSZoneName(NSZone * _Nullable zone);

/*
 * WHICH ZONE A POINTER CAME FROM. Answers NULL for memory this family did not
 * allocate, which is the only honest answer: an arbitrary `malloc` pointer has no
 * zone, and guessing the default one would make every pointer look zoned.
 */
FOUNDATION_EXPORT NSZone * _Nullable NSZoneFromPointer(void * _Nullable pointer);

/* THE ALLOCATORS. A NULL zone means the default zone. */
FOUNDATION_EXPORT void *NSZoneMalloc(NSZone * _Nullable zone, NSUInteger size);
FOUNDATION_EXPORT void *NSZoneCalloc(NSZone * _Nullable zone, NSUInteger numElems, NSUInteger byteSize);
FOUNDATION_EXPORT void *NSZoneRealloc(NSZone * _Nullable zone, void * _Nullable pointer, NSUInteger size);
FOUNDATION_EXPORT void NSZoneFree(NSZone * _Nullable zone, void * _Nullable pointer);

/*
 * THE COLLECTOR'S ALLOCATOR, WITH THIS LIBRARY'S HONEST READING. There is no
 * collector, so an allocation is ordinary memory that lives until it is freed;
 * `NSScannedOption` and `NSCollectorDisabledOption` describe what a collector
 * would scan and are accepted for source compatibility.
 */
#define NSScannedOption			(1UL << 0)
#define NSCollectorDisabledOption	(1UL << 1)

FOUNDATION_EXPORT void *NSAllocateCollectable(NSUInteger size, NSUInteger options);

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSZONE_H */
