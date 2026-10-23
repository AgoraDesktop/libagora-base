/*
 * kvo_tomany — the mutable collection proxies and KVO's to-many change dictionaries.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE PROXY IS THE POINT: A MUTATION OF THE PROXY IS A MUTATION OF THE PROPERTY.** `-mutableArrayValueForKey:` and
 * `-mutableSetValueForKey:` answer live views over the receiver's collection. Where that collection is already mutable,
 * the proxy mutates it IN PLACE and announces the change with `-willChange:valuesAtIndexes:forKey:` /
 * `-didChange:…` — the kind, the indexes, and the objects that were inserted, removed or replaced. Where it is
 * immutable (a computed value, or one a getter copies), the proxy builds a mutable copy and writes it back through
 * KVC, so the observer gets the ordinary SETTING change instead. The probe checks both arms, because a proxy that
 * always copied would pass a value test while losing every index.
 *
 * WHAT IS ASSERTED:
 *
 *   1. The array proxy is an `NSMutableArray` over the property: count, indexing, enumeration and the four mutations.
 *   2. Each insertion, removal and replacement announces ONE change with the right kind, index set and affected
 *      objects — and the OLD side of an insertion is NSNull, the NEW side of a removal is NSNull.
 *   3. `Prior` produces the before-notification with the old side, then the ordinary one with the new side.
 *   4. An immutable property takes the COPY arm: one SETTING change with the whole new array.
 *   5. A nil property is created by the first insertion (a setting change), and the next insertion is in place.
 *   6. The set proxy announces union as an insertion and minus as a removal, with NSSet values for new/old.
 *   7. A dotted key path proxies the object at the head of the path, and the notification's object is THAT object.
 *   8. A proxy with no observers still mutates the property; silence is not a failure.
 */
#import <Foundation/Foundation.h>

#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

static NSUInteger change_kind(NSDictionary *change)
{
	return [[change objectForKey:NSKeyValueChangeKindKey] unsignedIntegerValue];
}

static id change_value(NSDictionary *change, NSString *key)
{
	id value = [change objectForKey:key];

	return (value != nil && value != [NSNull null]) ? value : nil;
}

/* ============================================================================================ *
 * THE MODEL: A MUTABLE ARRAY, A MUTABLE SET, A STORED IMMUTABLE ARRAY AND A NIL KEY             *
 * ============================================================================================ */
@interface AGChild : NSObject
{
	NSMutableArray *_items;
}
- (NSMutableArray *)items;
- (void)setItems:(NSMutableArray *)value;
@end

@implementation AGChild
- (NSMutableArray *)items { return _items; }
- (void)setItems:(NSMutableArray *)value { _items = value; }
@end

@interface AGListModel : NSObject
{
	NSMutableArray *_items;
	NSMutableSet *_names;
	NSArray *_tags;
	NSMutableArray *_untouched;
	AGChild *_child;
}
- (NSMutableArray *)items;
- (void)setItems:(NSMutableArray *)value;
- (NSMutableSet *)names;
- (void)setNames:(NSSet *)value;
- (NSArray *)tags;
- (void)setTags:(NSArray *)value;
- (NSMutableArray *)untouched;
- (AGChild *)child;
- (void)setChild:(AGChild *)value;
@end

@implementation AGListModel

- (id)init
{
	self = [super init];
	if (self != nil) {
		_items = [[NSMutableArray alloc] init];
		_names = [[NSMutableSet alloc] init];
		_tags = [[NSArray alloc] initWithObjects:@"t1", nil];
	}
	return self;
}

- (void)dealloc
{
	[_items release];
	[_names release];
	[_tags release];
	[_untouched release];
	[_child release];
	[super dealloc];
}

- (NSMutableArray *)items { return _items; }
- (void)setItems:(NSMutableArray *)value { [value retain]; [_items release]; _items = value; }
- (NSMutableSet *)names { return _names; }
- (void)setNames:(NSSet *)value { [value retain]; [_names release]; _names = (NSMutableSet *)value; }
- (NSArray *)tags { return _tags; }
- (void)setTags:(NSArray *)value { [value retain]; [_tags release]; _tags = value; }
- (NSMutableArray *)untouched { return _untouched; }
- (AGChild *)child { return _child; }
- (void)setChild:(AGChild *)value { [value retain]; [_child release]; _child = value; }

@end

/* ============================================================================================ *
 * THE OBSERVER                                                                                   *
 * ============================================================================================ */
@interface AGTObserver : NSObject
{
@public
	NSMutableArray *keys;
	NSMutableArray *changes;
	NSMutableArray *objects;
}
@end

@implementation AGTObserver

- (id)init
{
	self = [super init];
	if (self != nil) {
		keys = [[NSMutableArray alloc] init];
		changes = [[NSMutableArray alloc] init];
		objects = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[keys release];
	[changes release];
	[objects release];
	[super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	(void)context;
	[keys addObject:(keyPath != nil ? keyPath : @"")];
	[changes addObject:(change != nil ? change : (id)[NSDictionary dictionary])];
	[objects addObject:(object != nil ? object : (id)[NSNull null])];
}

- (void)reset
{
	[keys removeAllObjects];
	[changes removeAllObjects];
	[objects removeAllObjects];
}

@end

int main(void)
{
	@autoreleasepool {
		AGListModel *model = [[AGListModel alloc] init];
		AGTObserver *observer = [[AGTObserver alloc] init];
		NSMutableArray *array;
		NSMutableSet *set;

		/* 1. THE ARRAY PROXY AND ONE INSERTION. */
		[model addObserver:observer forKeyPath:@"items"
			   options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
			   context:NULL];
		array = [model mutableArrayValueForKey:@"items"];
		check([array isKindOfClass:[NSMutableArray class]], "the proxy IS an NSMutableArray");
		check([array count] == 0, "and starts empty");
		[array addObject:@"a"];
		check([array count] == 1 && [[array objectAtIndex:0] isEqual:@"a"], "an insertion is visible through it");
		check([[model items] count] == 1 && [[[model items] objectAtIndex:0] isEqual:@"a"],
		      "and in the property it views");
		check([observer->keys count] == 1, "with one announcement");
		{
			NSDictionary *change = [observer->changes objectAtIndex:0];

			check(change_kind(change) == NSKeyValueChangeInsertion, "of an insertion");
			check([[change objectForKey:NSKeyValueChangeIndexesKey] containsIndex:0],
			      "at index 0");
			check([[change_value(change, NSKeyValueChangeNewKey) objectAtIndex:0] isEqual:@"a"],
			      "with the inserted object as NEW");
			check([change objectForKey:NSKeyValueChangeOldKey] == [NSNull null],
			      "and NSNull as OLD");
		}

		/* 2. INSERT AT THE FRONT, THEN ENUMERATE. */
		[observer reset];
		[array insertObject:@"z" atIndex:0];
		check([[[observer->changes lastObject] objectForKey:NSKeyValueChangeIndexesKey] containsIndex:0],
		      "an insert-at-front names index 0");
		{
			NSMutableArray *walked = [NSMutableArray array];

			for (id object in array) {
				[walked addObject:object];
			}
			check([walked count] == 2 && [[walked objectAtIndex:0] isEqual:@"z"]
			      && [[walked objectAtIndex:1] isEqual:@"a"],
			      "fast enumeration walks the backing property in order");
		}

		/* 3. REMOVAL KEEPS THE OLD SIDE ALIVE. */
		[observer reset];
		[array removeObjectAtIndex:1];
		{
			NSDictionary *change = [observer->changes lastObject];

			check(change_kind(change) == NSKeyValueChangeRemoval, "a removal is announced as one");
			check([[change objectForKey:NSKeyValueChangeIndexesKey] containsIndex:1],
			      "at the removed index");
			check([[change_value(change, NSKeyValueChangeOldKey) objectAtIndex:0] isEqual:@"a"],
			      "with the removed object as OLD, retained past the mutation");
			check([change objectForKey:NSKeyValueChangeNewKey] == [NSNull null],
			      "and NSNull as NEW");
		}

		/* 4. REPLACEMENT CARRIES BOTH SIDES. */
		[observer reset];
		[array replaceObjectAtIndex:0 withObject:@"q"];
		{
			NSDictionary *change = [observer->changes lastObject];

			check(change_kind(change) == NSKeyValueChangeReplacement, "a replacement is announced as one");
			check([[change_value(change, NSKeyValueChangeOldKey) objectAtIndex:0] isEqual:@"z"]
			      && [[change_value(change, NSKeyValueChangeNewKey) objectAtIndex:0] isEqual:@"q"],
			      "with the old and the new object");
		}

		/* 5. REMOVE-ALL IS ONE REMOVAL WITH ALL THE INDEXES. */
		[model setItems:[NSMutableArray arrayWithObjects:@"a", @"b", @"c", nil]];
		[observer reset];
		[[model mutableArrayValueForKey:@"items"] removeAllObjects];
		{
			NSDictionary *change = [observer->changes lastObject];
			NSIndexSet *indexes = [change objectForKey:NSKeyValueChangeIndexesKey];

			check(change_kind(change) == NSKeyValueChangeRemoval && [indexes count] == 3,
			      "removing everything names every index it took");
			check([change_value(change, NSKeyValueChangeOldKey) count] == 3,
			      "and all three objects");
		}

		/* 6. PRIOR IS THE BEFORE-NOTIFICATION. */
		[model setItems:[NSMutableArray array]];
		[observer reset];
		[model removeObserver:observer forKeyPath:@"items"];
		[model addObserver:observer forKeyPath:@"items"
			   options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
				    | NSKeyValueObservingOptionPrior)
			   context:NULL];
		[[model mutableArrayValueForKey:@"items"] addObject:@"p"];
		check([observer->changes count] == 2, "Prior produces two notifications");
		check([[[observer->changes objectAtIndex:0]
			objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue],
		      "the first is prior");
		check([[[observer->changes objectAtIndex:0]
			objectForKey:NSKeyValueChangeOldKey] isEqual:[NSNull null]],
		      "an insertion has no old objects to report");
		check([[[observer->changes objectAtIndex:1]
			objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue] == NO,
		      "and the second is the ordinary change");

		/* 7. THE IMMUTABLE ARM: A SETTING CHANGE WITH THE WHOLE NEW ARRAY. */
		[observer reset];
		[model addObserver:observer forKeyPath:@"tags"
			   options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
			   context:NULL];
		[[model mutableArrayValueForKey:@"tags"] addObject:@"t2"];
		{
			NSDictionary *change = [observer->changes lastObject];

			check(change_kind(change) == NSKeyValueChangeSetting,
			      "an immutable property takes the COPY arm and reports a setting change");
			check([[change_value(change, NSKeyValueChangeNewKey) lastObject] isEqual:@"t2"],
			      "with the whole new array");
			check([[[model tags] lastObject] isEqual:@"t2"], "and the property was written back");
		}

		/* 8. A NIL PROPERTY IS CREATED BY THE FIRST INSERTION. */
		[observer reset];
		[model addObserver:observer forKeyPath:@"untouched" options:NSKeyValueObservingOptionNew context:NULL];
		[[model mutableArrayValueForKey:@"untouched"] addObject:@"first"];
		check(change_kind([observer->changes lastObject]) == NSKeyValueChangeSetting,
		      "the first insertion into a nil property is a setting change");
		[observer reset];
		[[model mutableArrayValueForKey:@"untouched"] addObject:@"second"];
		check(change_kind([observer->changes lastObject]) == NSKeyValueChangeInsertion,
		      "and the next one is an in-place insertion");

		/* 9. THE SET PROXY: UNION IS INSERTION, MINUS IS REMOVAL, AND THE VALUES ARE SETS. */
		[observer reset];
		[model addObserver:observer forKeyPath:@"names"
			   options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
			   context:NULL];
		set = [model mutableSetValueForKey:@"names"];
		check([set isKindOfClass:[NSMutableSet class]], "the set proxy IS an NSMutableSet");
		[set addObject:@"n1"];
		{
			NSDictionary *change = [observer->changes lastObject];
			id newValue = change_value(change, NSKeyValueChangeNewKey);

			check(change_kind(change) == NSKeyValueChangeInsertion && [newValue isKindOfClass:[NSSet class]]
			      && [newValue containsObject:@"n1"],
			      "adding is an insertion whose NEW is an NSSet holding the member");
			check([change objectForKey:NSKeyValueChangeOldKey] == [NSNull null], "with NSNull as OLD");
		}
		[observer reset];
		[set removeObject:@"n1"];
		{
			NSDictionary *change = [observer->changes lastObject];
			id oldValue = change_value(change, NSKeyValueChangeOldKey);

			check(change_kind(change) == NSKeyValueChangeRemoval && [oldValue isKindOfClass:[NSSet class]]
			      && [oldValue containsObject:@"n1"],
			      "removing is a removal whose OLD is an NSSet holding the member");
		}
		[set addObject:@"n2"];
		check([set count] == 1 && [set member:@"n2"] != nil, "the proxy reads the membership back");
		check([[[model names] allObjects] count] == 1, "and the property holds it");

		/* 10. A DOTTED KEY PATH PROXIES THE OBJECT AT THE HEAD. */
		{
			AGChild *child = [[AGChild alloc] init];
			AGTObserver *childObserver = [[AGTObserver alloc] init];

			[child setItems:[NSMutableArray array]];
			[model setChild:child];
			[child addObserver:childObserver forKeyPath:@"items" options:NSKeyValueObservingOptionNew context:NULL];
			[[model mutableArrayValueForKeyPath:@"child.items"] addObject:@"deep"];
			check([childObserver->objects count] == 1
			      && [[childObserver->objects objectAtIndex:0] isEqual:child],
			      "the notification's OBJECT is the object at the head of the path");
			check([[[child items] lastObject] isEqual:@"deep"], "and the child's property was mutated");
			[child removeObserver:childObserver forKeyPath:@"items"];
			[childObserver release];
			[child release];
		}

		/* 11. A PROXY WITH NO OBSERVERS STILL MUTATES. */
		{
			AGListModel *quiet = [[AGListModel alloc] init];
			NSMutableArray *quietArray = [quiet mutableArrayValueForKey:@"items"];

			[quietArray addObject:@"q"];
			[quietArray removeObjectAtIndex:0];
			check([[quiet items] count] == 0, "an unobserved proxy mutates the property and stays silent");
			[quiet release];
		}

		printf("kvo_tomany: %d case(s) failed\n", s_failed);
		[observer release];
		[model release];
	}
	return s_failed != 0;
}
