/*
 * user_defaults_kvo — the settings store announces its keys, so a binding can follow one.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THE CASE THIS FILE EXISTS FOR IS A KEY THAT HAS NO SETTER.** KVO's automatic half wraps `-setFoo:`; the store's
 * write door is `-setObject:forKey:`, so there is nothing to wrap and the announcement has to be the store's own. The
 * probe therefore observes an ARBITRARY key string (`NSWindow Frame probe`, which is what AppKit actually stores) and
 * writes it through each door in turn, one check per door: `-setObject:forKey:`, the six typed setters, the KVC
 * spelling, and the removal.
 *
 * **AND IT PINS THE THREE RULES THE ANNOUNCEMENTS ARE BUILT ON.** One write is ONE notification (a KVC write must not
 * be announced by the store and by `NSObject`'s wrapper both); a removal of a key that was never there announces
 * NOTHING; and a registered default announces only when its EFFECTIVE value changed, so a key the app domain already
 * supplies is silent. The refusal case is here for the same reason the raise is: a write that is rejected before it
 * happens must not have announced anything.
 */
#import <Foundation/Foundation.h>

#include <stdio.h>
#include <stdlib.h>

static int s_failed;

static void check(int ok, const char *name)
{
	printf("  %s   %s\n", ok ? "ok  " : "FAIL", name);
	if (!ok) {
		s_failed++;
	}
}

/* ============================================================================================ *
 * AN OBSERVER THAT KEEPS THE LAST CHANGE, BY FIELD                                           *
 * ============================================================================================ */
@interface AGObserver : NSObject
{
@public
	int calls;
	int priorCalls;
	id newValue;
	id oldValue;
	id observedObject;
	NSString *path;
	void *context;
}
@end

@implementation AGObserver
- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)contextInfo
{
	id value = [change objectForKey:NSKeyValueChangeNotificationIsPriorKey];

	calls++;
	if (value != nil && [value boolValue]) {
		priorCalls++;
	}
	[path release];
	path = [keyPath copy];
	observedObject = object;	/* NOT retained: the defaults outlive the observer here */
	context = contextInfo;
	value = [change objectForKey:NSKeyValueChangeNewKey];
	[newValue release];
	newValue = [value retain];
	value = [change objectForKey:NSKeyValueChangeOldKey];
	[oldValue release];
	oldValue = [value retain];
}
- (void)reset
{
	calls = 0;
	priorCalls = 0;
	[newValue release];
	newValue = nil;
	[oldValue release];
	oldValue = nil;
	[path release];
	path = nil;
}
- (void)dealloc
{
	[newValue release];
	[oldValue release];
	[path release];
	[super dealloc];
}
@end

int main(void)
{
	@autoreleasepool {
		char scratch[] = "/tmp/agora-defaults-kvo-XXXXXX";
		NSUserDefaults *defaults;
		AGObserver *first = [[AGObserver alloc] init];
		AGObserver *second = [[AGObserver alloc] init];
		NSDictionary *registered;

		/* **THE STORE IS POINTED AT A SCRATCH ROOT BEFORE ANY DEFAULTS OBJECT EXISTS**, which is what
		 * `FNX_CONFIG_ROOT` is for: the probe touches nothing in the image. */
		if (mkdtemp(scratch) == NULL) {
			printf("user_defaults_kvo: cannot make a scratch directory\n");
			return 1;
		}
		setenv("FNX_CONFIG_ROOT", scratch, 1);
		defaults = [[NSUserDefaults alloc] initWithSuiteName:@"AgoraDefaultsKVOProbe"];

		/* --------------------------------------------------------------------------------- *
		 * 1. THE KVC SPELLINGS, WHICH ARE WHAT KVO READS                                      *
		 * --------------------------------------------------------------------------------- */
		check([defaults valueForKey:@"probeMissing"] == nil,
		      "-valueForKey: answers nil for a key the store has not got");
		[defaults setObject:@"value" forKey:@"probeKey"];
		check([[defaults valueForKey:@"probeKey"] isEqual:@"value"],
		      "and the store's value for a key it has");

		/* --------------------------------------------------------------------------------- *
		 * 2. EACH PER-KEY WRITE ANNOUNCES EXACTLY ONCE                                        *
		 * --------------------------------------------------------------------------------- */
		[defaults addObserver:first
			   forKeyPath:@"NSWindow Frame probe"
			      options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
			      context:(void *)0x11];
		check(first->calls == 0, "an observation of an unwritten key announces nothing");

		[defaults setObject:@"frame" forKey:@"NSWindow Frame probe"];
		check(first->calls == 1, "setObject:forKey: announces once");
		check([first->newValue isEqual:@"frame"] && first->oldValue == [NSNull null],
		      "with the new value, and NSNull for the absent old one");
		check(first->observedObject == defaults && [first->path isEqual:@"NSWindow Frame probe"]
		      && first->context == (void *)0x11,
		      "the object, the key path and the caller's context are the registration's");

		[first reset];
		[defaults setObject:@"frame2" forKey:@"NSWindow Frame probe"];
		check(first->calls == 1 && [first->oldValue isEqual:@"frame"] && [first->newValue isEqual:@"frame2"],
		      "a second write carries the previous value as Old");

		[first reset];
		[defaults setValue:@"via kvc" forKey:@"NSWindow Frame probe"];
		check(first->calls == 1, "a KVC write is announced ONCE, by the store and not by KVC's wrapper");
		check([first->newValue isEqual:@"via kvc"] && [[defaults valueForKey:@"NSWindow Frame probe"]
							       isEqual:@"via kvc"],
		      "and the write landed");

		[first reset];
		[defaults setBool:YES forKey:@"probeBool"];
		[defaults setInteger:42 forKey:@"probeInteger"];
		[defaults setFloat:1.5f forKey:@"probeFloat"];
		[defaults setDouble:2.5 forKey:@"probeDouble"];
		[defaults setURL:[NSURL URLWithString:@"https://agora.example/"] forKey:@"probeURL"];
		check(first->calls == 0, "the typed setters announce the keys they were given, not this one");
		check([defaults boolForKey:@"probeBool"] && [defaults integerForKey:@"probeInteger"] == 42
		      && [defaults doubleForKey:@"probeDouble"] == 2.5,
		      "and they all wrote");

		/* --------------------------------------------------------------------------------- *
		 * 3. REMOVAL: A CHANGE WHEN THERE WAS A VALUE, SILENCE WHEN THERE WAS NOT              *
		 * --------------------------------------------------------------------------------- */
		[first reset];
		[defaults removeObjectForKey:@"NSWindow Frame probe"];
		check(first->calls == 1 && first->newValue == [NSNull null]
		      && [first->oldValue isEqual:@"via kvc"],
		      "removing a key that had a value announces it, with NSNull as the new one");
		[first reset];
		[defaults removeObjectForKey:@"NSWindow Frame probe"];
		check(first->calls == 0, "removing a key that was never there announces nothing");
		[defaults setValue:nil forKey:@"NSWindow Frame probe"];
		check(first->calls == 0, "and a KVC write of nil is that same removal");

		/* --------------------------------------------------------------------------------- *
		 * 4. REGISTERED DEFAULTS: ONLY AN EFFECTIVE VALUE THAT MOVED                          *
		 * --------------------------------------------------------------------------------- */
		[defaults addObserver:first
			   forKeyPath:@"probeRegistered"
			      options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld)
			      context:NULL];
		registered = [NSDictionary dictionaryWithObject:@"registered" forKey:@"probeRegistered"];
		[defaults registerDefaults:registered];
		check(first->calls == 1 && [first->newValue isEqual:@"registered"],
		      "a registration for a key nothing else supplies announces once");
		[first reset];
		[defaults registerDefaults:registered];
		check(first->calls == 0, "registering the same value again announces nothing");
		[first reset];
		[defaults registerDefaults:[NSDictionary dictionaryWithObject:@"replaced" forKey:@"probeRegistered"]];
		check(first->calls == 1 && [first->oldValue isEqual:@"registered"]
		      && [first->newValue isEqual:@"replaced"],
		      "and a different registered value is a change, with the old one in the dictionary");

		[first reset];
		[defaults setObject:@"app" forKey:@"probeShadowed"];
		[defaults addObserver:first forKeyPath:@"probeShadowed" options:NSKeyValueObservingOptionNew context:NULL];
		[defaults registerDefaults:[NSDictionary dictionaryWithObject:@"registered" forKey:@"probeShadowed"]];
		check(first->calls == 0, "a registration for a key the app domain already supplies announces nothing");
		check([[defaults objectForKey:@"probeShadowed"] isEqual:@"app"],
		      "because the effective value did not move");
		[defaults removeObserver:first forKeyPath:@"probeShadowed"];

		/* --------------------------------------------------------------------------------- *
		 * 5. A REJECTED WRITE ANNOUNCES NOTHING                                               *
		 * --------------------------------------------------------------------------------- */
		[first reset];
		{
			BOOL raised = NO;

			@try {
				[defaults setObject:[[NSObject new] autorelease] forKey:@"probeNonPlist"];
			} @catch (NSException *exception) {
				raised = [[exception name] isEqual:NSInvalidArgumentException];
			}
			check(raised, "a value that is not a property list is refused");
			check(first->calls == 0, "and the refusal happened BEFORE the announcement, so nothing was announced");
		}

		/* --------------------------------------------------------------------------------- *
		 * 6. TWO OBSERVERS, BOTH REMOVAL SPELLINGS, AND PRIOR                                 *
		 * --------------------------------------------------------------------------------- */
		[defaults addObserver:first forKeyPath:@"probeTwo" options:NSKeyValueObservingOptionNew context:NULL];
		[defaults addObserver:second forKeyPath:@"probeTwo" options:NSKeyValueObservingOptionNew context:NULL];
		[defaults setObject:@"one" forKey:@"probeTwo"];
		check(first->calls == 1 && second->calls == 1, "two observers of one key are both told");
		[defaults removeObserver:first forKeyPath:@"probeTwo"];
		[defaults setObject:@"two" forKey:@"probeTwo"];
		check(first->calls == 1 && second->calls == 2, "removing one leaves the other");
		[defaults removeObserver:second forKeyPath:@"probeTwo"];

		[first reset];
		[defaults addObserver:first
			   forKeyPath:@"probePrior"
			      options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld |
				       NSKeyValueObservingOptionPrior)
			      context:NULL];
		[defaults setObject:@"x" forKey:@"probePrior"];
		check(first->calls == 2 && first->priorCalls == 1,
		      "Prior brackets one write with two notifications, the first marked prior");
		check([first->oldValue isEqual:[NSNull null]], "and the prior one carries the old value");
		[defaults removeObserver:first forKeyPath:@"probePrior"];

		[defaults removeObserver:first forKeyPath:@"NSWindow Frame probe"];
		[defaults removeObserver:first forKeyPath:@"probeRegistered"];

		printf("user_defaults_kvo: %d case(s) failed\n", s_failed);
		[first release];
		[second release];
		[defaults release];

		/* THE SCRATCH ROOT IS REMOVED AFTER THE STORE IS GONE, so nothing is left in /tmp. */
		[[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithUTF8String:scratch] error:NULL];
	}
	return s_failed != 0;
}
