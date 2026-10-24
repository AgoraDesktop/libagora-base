/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSZone.m — zones as allocators, and the registry that makes them answerable.
 *
 * THE DESIGN IS DELIBERATELY SMALL. The process has one heap, so a zone cannot
 * own a separate address range without a second allocator; what a zone CAN own is
 * the identity of the memory allocated through it. Every non-default allocation
 * is recorded in a pointer-to-zone table, which is what lets NSZoneFromPointer,
 * NSZoneName and -zone answer truthfully. The default zone is not recorded at all:
 * unrecorded memory is in the default zone by definition, and that keeps the
 * common path (no custom zone) free of a lookup and a lock.
 *
 * The table is protected by one mutex. It is read-only in the common case and the
 * custom-zone case is explicitly not a hot path; correctness is worth more here
 * than a lock-free list whose failure mode would be a wrong zone after reuse.
 */

#import <Foundation/NSZone.h>
#import <Foundation/NSString.h>
#include "FNZone.h"

#include <pthread.h>
#include <stdlib.h>
#include <string.h>

struct _NSZone {
	char *name;
	BOOL nameOwned;
	NSUInteger startSize;
	NSUInteger granularity;
	BOOL canFree;
};

static struct _NSZone fn_default_zone = {
	.name = (char *)"DefaultMallocZone",
	.nameOwned = NO,
	.startSize = 0,
	.granularity = 0,
	.canFree = NO
};

typedef struct FNZoneEntry {
	void *pointer;
	NSZone *zone;
	struct FNZoneEntry *next;
} FNZoneEntry;

static pthread_mutex_t fn_zone_lock = PTHREAD_MUTEX_INITIALIZER;
static FNZoneEntry *fn_zone_entries = NULL;
static unsigned long fn_zone_entry_count = 0;

static NSZone *fn_zone_or_default(NSZone *zone)
{
	return (zone != NULL) ? zone : &fn_default_zone;
}

NSZone *NSDefaultMallocZone(void)
{
	return &fn_default_zone;
}

NSZone *NSCreateZone(NSUInteger startSize, NSUInteger granularity, BOOL canFree)
{
	NSZone *zone = (NSZone *)calloc(1, sizeof(struct _NSZone));

	if (zone == NULL) {
		return NULL;
	}
	zone->name = NULL;
	zone->nameOwned = NO;
	zone->startSize = startSize;
	zone->granularity = granularity;
	zone->canFree = canFree;
	return zone;
}

void NSRecycleZone(NSZone *zone)
{
	FNZoneEntry **link;
	NSZone *target;

	if (zone == NULL || zone == &fn_default_zone) {
		return;
	}
	target = zone;

	pthread_mutex_lock(&fn_zone_lock);
	link = &fn_zone_entries;
	while (*link != NULL) {
		FNZoneEntry *entry = *link;

		if (entry->zone == target) {
			*link = entry->next;
			free(entry);
			__atomic_sub_fetch(&fn_zone_entry_count, 1, __ATOMIC_RELAXED);
			continue;
		}
		link = &entry->next;
	}
	pthread_mutex_unlock(&fn_zone_lock);

	if (target->nameOwned) {
		free(target->name);
	}
	if (target->canFree) {
		free(target);
	}
}

void NSSetZoneName(NSZone *zone, NSString *name)
{
	NSZone *target = fn_zone_or_default(zone);
	const char *utf8 = (name != nil) ? [name UTF8String] : NULL;
	char *copy = (utf8 != NULL) ? strdup(utf8) : NULL;

	pthread_mutex_lock(&fn_zone_lock);
	if (target->nameOwned) {
		free(target->name);
	}
	target->name = copy;
	target->nameOwned = (copy != NULL);
	pthread_mutex_unlock(&fn_zone_lock);
}

NSString *NSZoneName(NSZone *zone)
{
	NSZone *target = fn_zone_or_default(zone);
	const char *name;

	pthread_mutex_lock(&fn_zone_lock);
	name = target->name;
	pthread_mutex_unlock(&fn_zone_lock);

	if (name == NULL) {
		return @"";
	}
	return [NSString stringWithUTF8String:name];
}

static NSZone *fn_zone_lookup(void *pointer)
{
	FNZoneEntry *entry;
	NSZone *zone = NULL;

	if (pointer == NULL || __atomic_load_n(&fn_zone_entry_count, __ATOMIC_RELAXED) == 0) {
		return NULL;
	}
	pthread_mutex_lock(&fn_zone_lock);
	for (entry = fn_zone_entries; entry != NULL; entry = entry->next) {
		if (entry->pointer == pointer) {
			zone = entry->zone;
			break;
		}
	}
	pthread_mutex_unlock(&fn_zone_lock);
	return zone;
}

NSZone *NSZoneFromPointer(void *pointer)
{
	return fn_zone_lookup(pointer);
}

void fn_zone_assign_pointer(void *pointer, NSZone *zone)
{
	NSZone *target = fn_zone_or_default(zone);
	FNZoneEntry *entry;

	if (pointer == NULL) {
		return;
	}
	if (target == &fn_default_zone) {
		fn_zone_forget_pointer(pointer);
		return;
	}

	pthread_mutex_lock(&fn_zone_lock);
	for (entry = fn_zone_entries; entry != NULL; entry = entry->next) {
		if (entry->pointer == pointer) {
			entry->zone = target;
			pthread_mutex_unlock(&fn_zone_lock);
			return;
		}
	}
	entry = (FNZoneEntry *)malloc(sizeof(FNZoneEntry));
	if (entry != NULL) {
		entry->pointer = pointer;
		entry->zone = target;
		entry->next = fn_zone_entries;
		fn_zone_entries = entry;
		__atomic_add_fetch(&fn_zone_entry_count, 1, __ATOMIC_RELAXED);
	}
	pthread_mutex_unlock(&fn_zone_lock);
}

void fn_zone_forget_pointer(void *pointer)
{
	FNZoneEntry **link;

	if (pointer == NULL || __atomic_load_n(&fn_zone_entry_count, __ATOMIC_RELAXED) == 0) {
		return;
	}
	pthread_mutex_lock(&fn_zone_lock);
	link = &fn_zone_entries;
	while (*link != NULL) {
		FNZoneEntry *entry = *link;

		if (entry->pointer == pointer) {
			*link = entry->next;
			free(entry);
			__atomic_sub_fetch(&fn_zone_entry_count, 1, __ATOMIC_RELAXED);
			break;
		}
		link = &entry->next;
	}
	pthread_mutex_unlock(&fn_zone_lock);
}

void *NSZoneMalloc(NSZone *zone, NSUInteger size)
{
	NSZone *target = fn_zone_or_default(zone);
	void *pointer = malloc(size > 0 ? (size_t)size : 1);

	if (pointer != NULL && target != &fn_default_zone) {
		fn_zone_assign_pointer(pointer, target);
	}
	return pointer;
}

void *NSZoneCalloc(NSZone *zone, NSUInteger numElems, NSUInteger byteSize)
{
	NSZone *target = fn_zone_or_default(zone);
	void *pointer;

	if (numElems == 0 || byteSize == 0) {
		pointer = calloc(1, 1);
	} else {
		pointer = calloc((size_t)numElems, (size_t)byteSize);
	}
	if (pointer != NULL && target != &fn_default_zone) {
		fn_zone_assign_pointer(pointer, target);
	}
	return pointer;
}

void *NSZoneRealloc(NSZone *zone, void *pointer, NSUInteger size)
{
	NSZone *target = fn_zone_or_default(zone);
	void *answer;

	answer = realloc(pointer, (size_t)size);
	if (answer != NULL) {
		if (answer != pointer) {
			fn_zone_forget_pointer(pointer);
		}
		if (target != &fn_default_zone) {
			fn_zone_assign_pointer(answer, target);
		} else {
			fn_zone_forget_pointer(answer);
		}
	} else if (size == 0) {
		/* realloc(ptr, 0) may free the old block and answer NULL; forget it either way. */
		fn_zone_forget_pointer(pointer);
	}
	return answer;
}

void NSZoneFree(NSZone *zone, void *pointer)
{
	(void)zone;
	fn_zone_forget_pointer(pointer);
	free(pointer);
}

void *NSAllocateCollectable(NSUInteger size, NSUInteger options)
{
	(void)options;	/* the options describe what a collector would scan; there is no collector */
	return calloc(1, size > 0 ? (size_t)size : 1);
}
