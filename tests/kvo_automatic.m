/*
 * kvo_automatic — KVO's automatic half: a setter called DIRECTLY announces its change.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CASE THIS FILE EXISTS FOR IS THE ONE v1 COULD NOT SEE.** `-setValue:forKey:` announced its own writes, so a
 * model written through KVC was observable; `[model setName:x]` — what application code writes — was not. The first
 * observation moves the object to a dynamic subclass whose setter wrapper brackets the original IMP with
 * `-willChangeValueForKey:`/`-didChangeValueForKey:`. The probe therefore calls the SETTERS, not KVC, for every check
 * that is about the automatic path, and it asks `-class` and `object_getClass` separately because the wrapper is a lie
 * the object is supposed to tell.
 *
 * WHAT IS ASSERTED, and what each check would catch:
 *
 *   1. The class still answers the declared class, `object_getClass` shows the dynamic subclass, and
 *      `-isKindOfClass:` is true — a swizzle that leaks into `-class` is a visible bug.
 *   2. Direct setters for an object, an int, a double and a BOOL each produce ONE notification with the kind, the NEW
 *      and the OLD value, the object, and the caller's context.
 *   3. A nil old value is `NSNull` in the change dictionary, which is Cocoa's contract.
 *   4. `Prior` produces two notifications around one write, the first marked prior and carrying the old value.
 *   5. `Initial` arrives before the registration call returns.
 *   6. A KVC write after observation is announced exactly ONCE — the setter wrapper and KVC's own wrapper must not both
 *      speak.
 *   7. A key with no setter (the KVC ivar path) is still announced once by KVC's wrapper.
 *   8. A struct setter is NOT intercepted — the documented limit — and the manual pair is the answer for it.
 *   9. Two observers, both removal spellings, the context distinguishing two registrations, and the exception for
 *      removing what was never registered.
 *  10. An UNOBSERVED instance of the same class keeps the original class and notifies nobody; after every observer is
 *      removed, direct setters are silent rather than crashing.
 */
#import <Foundation/Foundation.h>

#include <objc/runtime.h>
#include <stdio.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * THE MODEL: ONE SETTER PER TYPE THAT MATTERS, A STRUCT SETTER AND AN IVAR-ONLY KEY             *
 * ============================================================================================ */
@interface AGKVOModel : NSObject
{
	id _name;
	int _count;
	double _ratio;
	BOOL _flag;
	NSRect _rect;
	int _plain;
}
- (id)name;
- (void)setName:(id)value;
- (int)count;
- (void)setCount:(int)value;
- (double)ratio;
- (void)setRatio:(double)value;
- (BOOL)flag;
- (void)setFlag:(BOOL)value;
- (NSRect)rect;
- (void)setRect:(NSRect)value;
- (int)plain;
@end

@implementation AGKVOModel

- (id)name { return _name; }
- (void)setName:(id)value { _name = value; }
- (int)count { return _count; }
- (void)setCount:(int)value { _count = value; }
- (double)ratio { return _ratio; }
- (void)setRatio:(double)value { _ratio = value; }
- (BOOL)flag { return _flag; }
- (void)setFlag:(BOOL)value { _flag = value; }
- (NSRect)rect { return _rect; }
- (void)setRect:(NSRect)value { _rect = value; }
- (int)plain { return _plain; }

@end

/* ============================================================================================ *
 * THE OBSERVER: EVERY CALL AND EVERY CHANGE DICTIONARY, IN ORDER                               *
 * ============================================================================================ */
@interface AGKVOObserver : NSObject
{
@public
	NSMutableArray *keys;
	NSMutableArray *changes;
	NSMutableArray *objects;
	NSMutableArray *contexts;
}
@end

@implementation AGKVOObserver

- (id)init
{
	self = [super init];
	if (self != nil) {
		keys = [[NSMutableArray alloc] init];
		changes = [[NSMutableArray alloc] init];
		objects = [[NSMutableArray alloc] init];
		contexts = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[keys release];
	[changes release];
	[objects release];
	[contexts release];
	[super dealloc];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	[keys addObject:(keyPath != nil ? keyPath : @"")];
	[changes addObject:(change != nil ? change : (id)[NSDictionary dictionary])];
	[objects addObject:(object != nil ? object : (id)[NSNull null])];
	[contexts addObject:[NSNumber numberWithUnsignedLong:(unsigned long)context]];
}

- (void)reset
{
	[keys removeAllObjects];
	[changes removeAllObjects];
	[objects removeAllObjects];
	[contexts removeAllObjects];
}

@end

static id change_value(NSDictionary *change, NSString *key)
{
	id value = [change objectForKey:key];

	return (value != nil && value != [NSNull null]) ? value : nil;
}

int main(void)
{
	@autoreleasepool {
		AGKVOModel *model = [[AGKVOModel alloc] init];
		AGKVOObserver *observer = [[AGKVOObserver alloc] init];
		AGKVOObserver *second = [[AGKVOObserver alloc] init];
		BOOL caught;

		/* 1. THE OBJECT SETTER, AND THE CLASS LIE. */
		[model addObserver:observer forKeyPath:@"name"
			   options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
			   context:(void *)0x1234];
		check([model class] == [AGKVOModel class], "`-class` still answers the declared class");
		check(object_getClass(model) != [AGKVOModel class],
		      "while `object_getClass` shows the dynamic notifying subclass");
		check([model isKindOfClass:[AGKVOModel class]], "and `-isKindOfClass:` is still true");

		[model setName:@"alpha"];
		check([observer->keys count] == 1, "a setter called DIRECTLY produces one notification");
		check([[observer->keys objectAtIndex:0] isEqual:@"name"], "for the observed key");
		check([[observer->objects objectAtIndex:0] isEqual:model], "with the observed object");
		check([[observer->contexts objectAtIndex:0] unsignedLongValue] == 0x1234u,
		      "and the caller's context untouched");
		{
			NSDictionary *change = [observer->changes objectAtIndex:0];

			check([[change objectForKey:NSKeyValueChangeKindKey] unsignedIntegerValue]
			      == NSKeyValueChangeSetting,
			      "the change kind is Setting");
			check([change_value(change, NSKeyValueChangeNewKey) isEqual:@"alpha"],
			      "the new value is the one written");
			check([change objectForKey:NSKeyValueChangeOldKey] == [NSNull null],
			      "and a nil old value is NSNull, Cocoa's contract");
		}
		[model setName:@"beta"];
		check([[[observer->changes lastObject] objectForKey:NSKeyValueChangeOldKey] isEqual:@"alpha"],
		      "a second write carries the previous value as OLD");

		/* 2. THE SCALARS, EACH THROUGH ITS OWN WRAPPER. */
		[observer reset];
		[model addObserver:observer forKeyPath:@"count"
			   options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
			   context:NULL];
		[model setCount:7];
		check([[observer->keys lastObject] isEqual:@"count"] && [observer->keys count] == 1,
		      "an int setter notifies once");
		check([change_value([observer->changes lastObject], NSKeyValueChangeNewKey) intValue] == 7
		      && [change_value([observer->changes lastObject], NSKeyValueChangeOldKey) intValue] == 0,
		      "with the int boxed as new and old");

		[observer reset];
		[model addObserver:observer forKeyPath:@"ratio" options:NSKeyValueObservingOptionNew context:NULL];
		[model setRatio:2.5];
		check([change_value([observer->changes lastObject], NSKeyValueChangeNewKey) doubleValue] == 2.5,
		      "a double setter notifies");
		[observer reset];
		[model addObserver:observer forKeyPath:@"flag" options:NSKeyValueObservingOptionNew context:NULL];
		[model setFlag:YES];
		check([change_value([observer->changes lastObject], NSKeyValueChangeNewKey) boolValue] == YES,
		      "and a BOOL setter notifies");

		/* 3. PRIOR, WHICH IS TWO NOTIFICATIONS AROUND ONE WRITE. A FRESH OBSERVER, BECAUSE THE COUNT IS THE CHECK: the
		 * first observer also holds a New-only registration for this key from the scalar checks, and two registrations
		 * would make the count say three. */
		[model setRatio:1.0];
		[second reset];
		[model addObserver:second forKeyPath:@"ratio"
			   options:(NSKeyValueObservingOptionPrior | NSKeyValueObservingOptionOld)
			   context:NULL];
		[model setRatio:3.5];
		check([second->keys count] == 2, "Prior produces two notifications for one write");
		check([[[second->changes objectAtIndex:0]
			objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue],
		      "the first is marked prior");
		check([[[second->changes objectAtIndex:0]
			objectForKey:NSKeyValueChangeOldKey] doubleValue] == 1.0,
		      "and carries the old value");
		check([[[second->changes objectAtIndex:1]
			objectForKey:NSKeyValueChangeNotificationIsPriorKey] boolValue] == NO,
		      "the second is the ordinary change");
		[model removeObserver:second forKeyPath:@"ratio"];

		/* 4. INITIAL ARRIVES BEFORE THE REGISTRATION RETURNS. */
		{
			AGKVOModel *prepared = [[AGKVOModel alloc] init];
			AGKVOObserver *initial = [[AGKVOObserver alloc] init];

			[prepared setName:@"ready"];
			[prepared addObserver:initial forKeyPath:@"name"
				      options:(NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew)
				      context:NULL];
			check([initial->keys count] == 1
			      && [change_value([initial->changes objectAtIndex:0],
					       NSKeyValueChangeNewKey) isEqual:@"ready"],
			      "an Initial observation is delivered with the current value");
			[prepared removeObserver:initial forKeyPath:@"name"];
			[initial release];
			[prepared release];
		}

		/* 5. ONE ANNOUNCEMENT PER KVC WRITE, NOT TWO. */
		[observer reset];
		[model setValue:@"gamma" forKey:@"name"];
		check([observer->keys count] == 1, "a KVC write announces exactly once after observation");
		{
			AGKVOModel *unobserved = [[AGKVOModel alloc] init];

			[unobserved setValue:[NSNumber numberWithInt:4] forKey:@"count"];
			check([unobserved count] == 4, "a KVC write before any observation still writes");
			[observer reset];
			[unobserved addObserver:observer forKeyPath:@"count" options:NSKeyValueObservingOptionNew context:NULL];
			[unobserved setValue:[NSNumber numberWithInt:5] forKey:@"count"];
			check([observer->keys count] == 1, "and one after it announces once");
			[unobserved removeObserver:observer forKeyPath:@"count"];
			[unobserved release];
		}

		/* 6. AN IVAR-ONLY KEY IS ANNOUNCED BY KVC'S OWN WRAPPER. */
		[observer reset];
		[model addObserver:observer forKeyPath:@"plain" options:NSKeyValueObservingOptionNew context:NULL];
		[model setValue:[NSNumber numberWithInt:9] forKey:@"plain"];
		check([observer->keys count] == 1 && [change_value([observer->changes lastObject],
			NSKeyValueChangeNewKey) intValue] == 9,
		      "a key with no setter is still announced once, by KVC");
		[model removeObserver:observer forKeyPath:@"plain"];

		/* 7. A STRUCT SETTER IS NOT INTERCEPTED; THE MANUAL PAIR IS. */
		[observer reset];
		[model addObserver:observer forKeyPath:@"rect" options:NSKeyValueObservingOptionNew context:NULL];
		[model setRect:NSMakeRect(1.0, 2.0, 3.0, 4.0)];
		check([observer->keys count] == 0, "a struct setter is NOT intercepted (named limit)");
		[model willChangeValueForKey:@"rect"];
		[model setRect:NSMakeRect(5.0, 6.0, 7.0, 8.0)];
		[model didChangeValueForKey:@"rect"];
		check([observer->keys count] == 1, "and the manual pair is the answer for it");
		[model removeObserver:observer forKeyPath:@"rect"];

		/* 8. TWO OBSERVERS AND BOTH REMOVAL SPELLINGS. */
		[observer reset];
		[second reset];
		[model addObserver:second forKeyPath:@"name" options:NSKeyValueObservingOptionNew context:(void *)0x77];
		[model setName:@"delta"];
		check([observer->keys count] > 0 && [second->keys count] == 1,
		      "two observers are both told");
		[model removeObserver:second forKeyPath:@"name" context:(void *)0x77];
		[second reset];
		[model setName:@"epsilon"];
		check([second->keys count] == 0, "the 3-argument removal with the context removes exactly that one");
		caught = NO;
		@try {
			[model removeObserver:second forKeyPath:@"name"];
		} @catch (NSException *exception) {
			caught = [[exception name] isEqual:NSInvalidArgumentException];
		}
		check(caught, "removing an observer that was never registered raises");

		/* 9. AN UNOBSERVED INSTANCE OF THE SAME CLASS KEEPS THE ORIGINAL CLASS AND TELLS NOBODY. */
		{
			AGKVOModel *other = [[AGKVOModel alloc] init];
			NSUInteger before = [observer->keys count];

			check(object_getClass(other) == [AGKVOModel class],
			      "an unobserved instance is still of the declared class");
			[other setName:@"nobody is watching"];
			check([observer->keys count] == before, "and its setter notifies no one else's observer");
			[other release];
		}

		/* 10. AFTER EVERY OBSERVER IS GONE, THE WRAPPED SETTER IS SILENT RATHER THAN CRASHING. */
		[model removeObserver:observer forKeyPath:@"name"];
		[model removeObserver:observer forKeyPath:@"count"];
		[model removeObserver:observer forKeyPath:@"ratio"];
		[model removeObserver:observer forKeyPath:@"flag"];
		[observer reset];
		[model setName:@"after"];
		[model setCount:99];
		check([observer->keys count] == 0, "a setter with no observers left announces nothing");

		/* AND A NIL THROUGH AN OBJECT SETTER IS LEGAL KVC (the binding layer's null placeholder needs it). */
		[observer reset];
		[model setValue:nil forKey:@"name"];
		check([model name] == nil, "`-setValue:nil forKey:` reaches an id setter with nil");

		/* 11. THE OBSERVATION INFO IS THE CALLER'S OWN SLOT. */
		check([model observationInfo] == NULL, "no observation info by default");
		[model setObservationInfo:(void *)0xbeef];
		check([model observationInfo] == (void *)0xbeef, "and it round-trips");

		printf("kvo_automatic: %d case(s) failed\n", s_failed);
		[second release];
		[observer release];
		[model release];
	}
	return s_failed != 0;
}
