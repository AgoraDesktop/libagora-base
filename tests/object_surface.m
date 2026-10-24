/*
 * object_surface — the 10.6 root-class doors, measured.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. The 10.6 census counts a door by finding a body; this probe is the caller that says the
 * body DOES WHAT THE DOOR MEANS. It covers the F1 slice: the resolve/instance-method hooks and class version, the
 * delayed and threaded perform family, the OpenStep KVC spellings and the stored accessor, KVO's dependency rule in
 * both spellings, the comparison protocol, the stack doors, and the small formatter/collection/XML additions.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

static int g_fail;

static void
check(int condition, const char *what)
{
	if (!condition) {
		printf("FAIL: %s\n", what);
		g_fail = 1;
	} else {
		printf("ok: %s\n", what);
	}
}

/* --- a class that answers a selector it does not implement statically --- */
static int g_resolved_calls;

@interface DynamicProbe : NSObject
@end

static id dynamic_echo(id self, SEL _cmd, id argument)
{
	(void)self; (void)_cmd;
	g_resolved_calls++;
	return argument;
}

@implementation DynamicProbe

+ (BOOL)resolveInstanceMethod:(SEL)selector
{
	if (sel_isEqual(selector, @selector(echo:))) {
		class_addMethod(self, selector, (IMP)dynamic_echo, "@@:@");
		return YES;
	}
	return NO;
}

@end

/* --- a KVC/KVO model with a dependent key and a legacy registration --- */
@interface Person : NSObject
{
@public
	NSString *firstName;
	NSString *lastName;
	NSString *storedNote;
}
- (NSString *)fullName;
@end

@implementation Person

- (NSString *)firstName { return firstName; }
- (void)setFirstName:(NSString *)value { [firstName release]; firstName = [value copy]; }
- (NSString *)lastName { return lastName; }
- (void)setLastName:(NSString *)value { [lastName release]; lastName = [value copy]; }
- (NSString *)fullName { return [NSString stringWithFormat:@"%@ %@", firstName, lastName]; }

+ (NSSet *)keyPathsForValuesAffectingFullName
{
	return [NSSet setWithObject:@"firstName"];
}

@end

@interface Observer : NSObject
{
@public
	int fullNameChanges;
	int noteChanges;
}
@end

@implementation Observer
- (void)observeValueForKeyPath:(NSString *)keyPath
		      ofObject:(id)object
			change:(NSDictionary *)change
		       context:(void *)context
{
	(void)object; (void)change; (void)context;
	if ([keyPath isEqualToString:@"fullName"]) {
		fullNameChanges++;
	}
	if ([keyPath isEqualToString:@"storedNote"]) {
		noteChanges++;
	}
}
@end

/* --- the threaded perform target --- */
@interface ThreadTarget : NSObject
{
@public
	volatile int ran;
	volatile int loopReady;
	id workerThread;
}
@end

@implementation ThreadTarget
- (void)mark { ran = 1; }
- (void)worker:(id)ignored
{
	NSRunLoop *loop;

	(void)ignored;
	/* THE LOOP IS MADE AND REGISTERED BEFORE THE FLAG IS SET, because the main thread's queue lookup needs it to
	 * exist; setting the flag first is a race this probe found on its first run. */
	loop = [NSRunLoop currentRunLoop];
	workerThread = [[NSThread currentThread] retain];
	loopReady = 1;
	[loop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
}
@end

int
main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	Person *person;
	Observer *observer;
	NSString *stored;

	/* THE RUNTIME HOOKS. */
	check(![NSObject resolveInstanceMethod:@selector(description)], "+resolveInstanceMethod: defaults to NO");
	check(![NSObject resolveClassMethod:@selector(description)], "+resolveClassMethod: defaults to NO");
	check([DynamicProbe instanceMethodForSelector:@selector(description)] != NULL,
	      "+instanceMethodForSelector: finds an instance method");
	check([DynamicProbe instanceMethodSignatureForSelector:@selector(description)] != nil,
	      "+instanceMethodSignatureForSelector: finds the types");
	check([DynamicProbe instanceMethodSignatureForSelector:@selector(noSuchDoor)] == nil,
	      "+instanceMethodSignatureForSelector: answers nil for an unknown selector");
	[NSObject setVersion:7];
	check([NSObject version] == 7, "+version/+setVersion: round-trip through the runtime");

	/* THE DELAYED PERFORM, AND THE CANCEL THAT MATCHES BY TARGET. */
	person = [[Person alloc] init];
	person->firstName = [@"Ada" copy];
	[person performSelector:@selector(setLastName:) withObject:@"Lovelace" afterDelay:0.02];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
	check([person->lastName isEqualToString:@"Lovelace"], "afterDelay: runs when the loop turns");

	[person performSelector:@selector(setLastName:) withObject:@"Cancelled" afterDelay:0.01];
	[NSObject cancelPreviousPerformRequestsWithTarget:person selector:@selector(setLastName:) object:@"Cancelled"];
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	check([person->lastName isEqualToString:@"Lovelace"], "cancelPreviousPerformRequestsWithTarget:... cancels");

	/* THE THREADED PERFORM, WITH waitUntilDone:YES AGAINST A REAL LOOP. */
	{
		ThreadTarget *target = [[ThreadTarget alloc] init];
		int spins = 0;

		[NSThread detachNewThreadSelector:@selector(worker:) toTarget:target withObject:nil];
		while (!target->loopReady && spins++ < 1000) {
			usleep(1000);
		}
		[target performSelector:@selector(mark) onThread:[NSThread currentThread] withObject:nil waitUntilDone:YES];
		check(target->ran == 1, "performSelector:onThread:... on the CURRENT thread is immediate");

		target->ran = 0;
		[target performSelector:@selector(mark) onThread:target->workerThread withObject:nil waitUntilDone:YES];
		check(target->ran == 1, "performSelector:onThread:... queues on ANOTHER thread's loop and waits");

		target->ran = 0;
		[target performSelectorInBackground:@selector(mark) withObject:nil];
		spins = 0;
		while (!target->ran && spins++ < 1000) {
			usleep(1000);
		}
		check(target->ran == 1, "performSelectorInBackground: starts a thread that runs the selector");
		[target->workerThread release];
		[target release];
	}

	/* THE OPENSTEP KVC SPELLINGS AND THE STORED ACCESSOR. */
	[person takeValue:@"Grace" forKey:@"firstName"];
	check([person->firstName isEqualToString:@"Grace"], "-takeValue:forKey: writes through the setter");
	stored = @"note";
	[person takeStoredValue:stored forKey:@"storedNote"];
	check([person->storedNote isEqualToString:@"note"], "-takeStoredValue:forKey: writes the ivar");
	check([[person storedValueForKey:@"storedNote"] isEqualToString:@"note"], "-storedValueForKey: reads it back");
	check([Person accessInstanceVariablesDirectly], "+accessInstanceVariablesDirectly defaults to YES");
	check([[person dictionaryWithValuesForKeys:[NSArray arrayWithObjects:@"firstName", @"lastName", nil]]
	       count] == 2, "-dictionaryWithValuesForKeys: answers one entry per key");

	/* KVO'S DECLARATIVE DEPENDENCY: OBSERVING fullName MAKES firstName's SETTER ANNOUNCE IT. */
	observer = [[Observer alloc] init];
	[person addObserver:observer forKeyPath:@"fullName" options:0 context:NULL];
	[person setFirstName:@"Hedy"];
	[person removeObserver:observer forKeyPath:@"fullName"];
	check(observer->fullNameChanges == 1, "a dependent key is announced when its dependency changes");

	/* AND THE LEGACY REGISTRATION, `-setKeys:triggerChangeNotificationsForDependentKey:`. */
	[person setKeys:[NSArray arrayWithObject:@"storedNote"]
	    triggerChangeNotificationsForDependentKey:@"fullName"];
	[person addObserver:observer forKeyPath:@"fullName" options:0 context:NULL];
	{
		int before = observer->fullNameChanges;

		[person takeStoredValue:@"second" forKey:@"storedNote"];
		[person removeObserver:observer forKeyPath:@"fullName"];
		check(observer->fullNameChanges == before,
		      "a STORED write announces nothing (it bypasses the accessor by design)");
	}

	/* THE COMPARISON PROTOCOL. */
	{
		NSNumber *one = [NSNumber numberWithInt:1];
		NSNumber *two = [NSNumber numberWithInt:2];

		check([one isLessThan:two], "-isLessThan: routes through -compare:");
		check([two isGreaterThanOrEqualTo:two], "-isGreaterThanOrEqualTo: agrees at equality");
		check([@"Hello" isLike:@"H*o"], "-isLike: matches with * and ?");
		check(![@"Hello" isLike:@"h*o"], "-isLike: is case sensitive");
		check([@"Hello" isCaseInsensitiveLike:@"h*o"], "-isCaseInsensitiveLike: folds case");
		check([@"Hello" doesContain:@"ell"], "-doesContain: searches a string");
		check([@"Hello" scriptingBeginsWith:@"He"], "-scriptingBeginsWith:");
	}

	/* THE STACK DOORS. */
	check(NSCountFrames() > 0, "NSCountFrames() counts the current stack");
	check([[NSThread callStackReturnAddresses] count] > 0, "+[NSThread callStackReturnAddresses]");
	check([[NSThread callStackSymbols] count] > 0, "+[NSThread callStackSymbols]");
	check([[NSException exceptionWithName:@"probe" reason:nil userInfo:nil] callStackSymbols] != nil,
	      "-[NSException callStackSymbols]");

	/* THE FORMATTER'S SYMBOL SETTERS, AND THE COLLECTIONS' 10.6 CONSTRUCTORS. */
	{
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		NSArray *months = [NSArray arrayWithObjects:@"M1", @"M2", @"M3", @"M4", @"M5", @"M6", @"M7",
				   @"M8", @"M9", @"M10", @"M11", @"M12", @"M13", nil];

		[formatter setMonthSymbols:months];
		check([[formatter monthSymbols] count] == 13 &&
		      [[[formatter monthSymbols] objectAtIndex:0] isEqualToString:@"M1"],
		      "-setMonthSymbols: is answered by -monthSymbols");
		[formatter setAMSymbol:@"am"];
		check([[formatter AMSymbol] isEqualToString:@"am"], "-setAMSymbol: is answered by -AMSymbol");
		[formatter release];
	}
	{
		NSMapTable *map = [NSMapTable mapTableWithStrongToStrongObjects];
		NSHashTable *weak = [NSHashTable hashTableWithWeakObjects];

		[map setObject:@"v" forKey:@"k"];
		check([[map objectForKey:@"k"] isEqualToString:@"v"], "NSMapTable 10.6 constructor stores");
		[weak addObject:@"w"];
		check([weak containsObject:@"w"], "NSHashTable +hashTableWithWeakObjects stores");
	}

	/* THE SMALL VALUE DOORS. */
	{
		NSExpression *expression = [NSExpression expressionForBlock:^id(id object, NSArray *args, NSMutableDictionary *context) {
			(void)args; (void)context;
			return object;
		} arguments:[NSArray array]];
		check([expression expressionBlock] != nil, "NSExpression -expressionBlock answers the block");
	}
	{
		NSString *strings = @"/* comment */ \"a\" = \"one\";\n\"b\" = \"two\";";
		NSDictionary *parsed = [strings propertyListFromStringsFileFormat];

		check([[parsed objectForKey:@"a"] isEqualToString:@"one"] &&
		      [[parsed objectForKey:@"b"] isEqualToString:@"two"],
		      "-propertyListFromStringsFileFormat parses a brace-less .strings body");
	}

	[observer release];
	[person release];
	[pool drain];
	printf(g_fail ? "object_surface: FAIL\n" : "object_surface: all checks passed\n");
	return g_fail;
}
