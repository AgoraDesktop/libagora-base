/*
 * foundation_behaviour — the second wave of the behavioural pass.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. `core_values` covers the value types; this covers the MACHINERY an application builds on:
 * predicates and KVC operators, sort descriptors, notifications, operations, the file manager, streams, undo,
 * regular expressions, scanners, date formatting, timers, character sets and the geometry value doors. Each check
 * names the contract, so a failure says what is wrong.
 */

#import <Foundation/Foundation.h>

#include <stdio.h>
#include <string.h>
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

@interface Person : NSObject
{
@public
	NSString *name;
	int age;
}
- (NSString *)name;
- (void)setName:(NSString *)value;
- (int)age;
- (void)setAge:(int)value;
@end

@implementation Person
- (NSString *)name { return name; }
- (void)setName:(NSString *)value { [name release]; name = [value copy]; }
- (int)age { return age; }
- (void)setAge:(int)value { age = value; }
@end

/* THE UNDOABLE SETTER the undo checks need: it registers the inverse of what it is about to do, which is what
 * gives the redo stack its content. */
@interface UndoPerson : Person
{
@public
	NSUndoManager *manager;
}
- (void)setNameUndoably:(NSString *)value;
@end

@implementation UndoPerson
- (void)setNameUndoably:(NSString *)value
{
	[[manager prepareWithInvocationTarget:self] setNameUndoably:name];
	[self setName:value];
}
@end

@interface Observer : NSObject
{
@public
	int count;
	id lastObject;
	NSString *lastName;
}
@end

@implementation Observer
- (void)noted:(NSNotification *)notification
{
	count++;
	lastObject = [notification object];
	lastName = [[notification name] copy];
}
@end

static NSArray *
people(void)
{
	Person *a = [[Person alloc] init];
	Person *b = [[Person alloc] init];
	Person *c = [[Person alloc] init];
	NSArray *result;

	a->name = [@"Ada" copy];
	a->age = 36;
	b->name = [@"Grace" copy];
	b->age = 45;
	c->name = [@"Alan" copy];
	c->age = 41;
	result = [NSArray arrayWithObjects:a, b, c, nil];
	[a release];
	[b release];
	[c release];
	return result;
}

static NSString *
scratchDirectory(void)
{
	static char path[512];
	char template[] = "/tmp/agora-behaviour-XXXXXX";

	if (path[0] == 0) {
		snprintf(path, sizeof path, "%s", mkdtemp(template));
	}
	return [NSString stringWithUTF8String:path];
}

int
main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSArray *persons = people();

	/* ============================== PREDICATES ================================================ */

	{
		NSPredicate *adults = [NSPredicate predicateWithFormat:@"age >= 40"];
		NSPredicate *initial = [NSPredicate predicateWithFormat:@"name BEGINSWITH 'A'"];
		NSPredicate *both = [NSCompoundPredicate andPredicateWithSubpredicates:
				     [NSArray arrayWithObjects:adults, initial, nil]];
		NSPredicate *either = [NSCompoundPredicate orPredicateWithSubpredicates:
				       [NSArray arrayWithObjects:adults, initial, nil]];
		NSPredicate *negated = [NSCompoundPredicate notPredicateWithSubpredicate:adults];

		check([adults evaluateWithObject:[persons objectAtIndex:1]], "a comparison predicate evaluates true");
		check(![adults evaluateWithObject:[persons objectAtIndex:0]], "a comparison predicate evaluates false");
		check([initial evaluateWithObject:[persons objectAtIndex:0]], "BEGINSWITH");
		check([[persons filteredArrayUsingPredicate:both] count] == 1, "an AND compound predicate");
		check([[persons filteredArrayUsingPredicate:either] count] == 3, "an OR compound predicate");
		check([[persons filteredArrayUsingPredicate:negated] count] == 1, "a NOT compound predicate");
	}
	{
		NSPredicate *inList = [NSPredicate predicateWithFormat:@"name IN %@",
				       [NSArray arrayWithObjects:@"Ada", @"Alan", nil]];
		NSPredicate *between = [NSPredicate predicateWithFormat:@"age BETWEEN {40, 46}"];
		NSPredicate *contains = [NSPredicate predicateWithFormat:@"name CONTAINS 'ra'"];
		NSPredicate *nilTest = [NSPredicate predicateWithFormat:@"name == nil"];
		NSPredicate *block = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
			(void)bindings;
			return [(Person *)object age] == 36;
		}];

		check([[persons filteredArrayUsingPredicate:inList] count] == 2, "IN over a collection");
		check([[persons filteredArrayUsingPredicate:between] count] == 2, "BETWEEN {low, high}");
		check([[persons filteredArrayUsingPredicate:contains] count] == 1, "CONTAINS a substring");
		check([[persons filteredArrayUsingPredicate:nilTest] count] == 0, "a nil comparison is false for non-nil");
		check([[persons filteredArrayUsingPredicate:block] count] == 1, "a block predicate");
	}
	{
		NSArray *ages = [persons valueForKey:@"age"];
		NSArray *names = [persons valueForKey:@"name"];

		check([[persons valueForKeyPath:@"@count"] intValue] == 3, "the @count KVC operator");
		check([[persons valueForKeyPath:@"@sum.age"] intValue] == 122, "the @sum operator");
		check([[persons valueForKeyPath:@"@max.age"] intValue] == 45, "the @max operator");
		check([[persons valueForKeyPath:@"@min.age"] intValue] == 36, "the @min operator");
		check([[persons valueForKeyPath:@"@avg.age"] doubleValue] > 40.0, "the @avg operator");
		check([[persons valueForKeyPath:@"@distinctUnionOfObjects.name"] count] == 3,
		      "the @distinctUnionOfObjects operator");
		check([ages count] == 3 && [[ages objectAtIndex:0] intValue] == 36,
		      "valueForKey: maps over an array");
		check([names count] == 3, "valueForKey: maps strings as well as numbers");
	}

	/* ============================== SORT DESCRIPTORS ========================================== */

	{
		NSSortDescriptor *byAge = [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:YES];
		NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO];
		NSArray *sorted = [persons sortedArrayUsingDescriptors:[NSArray arrayWithObject:byAge]];
		NSArray *namesDescending = [persons sortedArrayUsingDescriptors:[NSArray arrayWithObject:byName]];

		check([[[sorted objectAtIndex:0] name] isEqualToString:@"Ada"], "a sort descriptor orders by key");
		check([[[namesDescending objectAtIndex:0] name] isEqualToString:@"Grace"],
		      "a descending sort descriptor");
	}

	/* ============================== NOTIFICATIONS ============================================= */

	{
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		Observer *observer = [[Observer alloc] init];
		NSString *name = @"AgoraProbeNotification";
		id marker = [[[NSObject alloc] init] autorelease];

		[center addObserver:observer selector:@selector(noted:) name:name object:nil];
		[center postNotificationName:name object:marker];
		check(observer->count == 1 && observer->lastObject == marker,
		      "a selector observer receives the notification and its object");
		[center removeObserver:observer name:name object:nil];
		[center postNotificationName:name object:marker];
		check(observer->count == 1, "a removed observer is not called");

		[center addObserver:observer selector:@selector(noted:) name:name object:marker];
		[center postNotificationName:name object:nil];
		check(observer->count == 1, "an object filter excludes a notification with a different object");
		[center postNotificationName:name object:marker];
		check(observer->count == 2, "an object filter admits the matching object");
		[center removeObserver:observer name:name object:marker];
	}
	{
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		NSString *name = @"AgoraBlockNotification";
		__block int calls = 0;
		id token = [center addObserverForName:name
				       object:nil
					queue:nil
				   usingBlock:^(NSNotification *notification) {
			(void)notification;
			calls++;
		}];

		[center postNotificationName:name object:nil];
		[center removeObserver:token];
		[center postNotificationName:name object:nil];
		check(calls == 1, "a block observer runs until it is removed");
	}
	{
		/* REMOVING AN OBSERVER WHILE A NOTIFICATION IS IN FLIGHT must not skip or double-call the survivors. */
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		NSString *name = @"AgoraRemoveDuringPost";
		Observer *first = [[Observer alloc] init];
		Observer *second = [[Observer alloc] init];
		__block int blockCalls = 0;
		id token = [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *n) {
			(void)n;
			blockCalls++;
			[center removeObserver:second name:name object:nil];
		}];

		[center addObserver:first selector:@selector(noted:) name:name object:nil];
		[center addObserver:second selector:@selector(noted:) name:name object:nil];
		[center postNotificationName:name object:nil];
		check(first->count == 1 && blockCalls == 1,
		      "a removal during a post does not disturb the observer already reached");
		{
			/* THE IN-FLIGHT POST MAY STILL REACH IT (Apple allows either order); the NEXT one may not. */
			int reachedDuringFirstPost = second->count;

			[center postNotificationName:name object:nil];
			check(second->count == reachedDuringFirstPost,
			      "an observer removed during a post is not called by the next one");
		}
		[center removeObserver:token];
		[center removeObserver:first name:name object:nil];
	}
	{
		/* A NOTIFICATION QUEUE POSTS WHEN THE LOOP IS IDLE; NSNotificationQueue with NSPostASAP is delivered on the
		 * next pass, which a run-loop turn performs. */
		NSNotificationQueue *queue = [NSNotificationQueue defaultQueue];
		Observer *observer = [[Observer alloc] init];
		NSString *name = @"AgoraQueuedNotification";
		NSNotification *notification = [NSNotification notificationWithName:name object:nil];

		[[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(noted:) name:name object:nil];
		[queue enqueueNotification:notification postingStyle:NSPostASAP];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
		check(observer->count == 1, "the notification queue delivers an ASAP post on the next pass");
		[[NSNotificationCenter defaultCenter] removeObserver:observer name:name object:nil];
	}

	/* ============================== OPERATIONS ================================================ */

	{
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		NSMutableArray *order = [NSMutableArray array];
		__block int completed = 0;
		NSBlockOperation *first = [NSBlockOperation blockOperationWithBlock:^{
			[order addObject:@"one"];
		}];
		NSBlockOperation *second = [NSBlockOperation blockOperationWithBlock:^{
			[order addObject:@"two"];
		}];

		[queue setMaxConcurrentOperationCount:1];
		[second addDependency:first];
		[second setCompletionBlock:^{
			completed = 1;
		}];
		[queue addOperation:second];
		[queue addOperation:first];
		[queue waitUntilAllOperationsAreFinished];
		check([order isEqualToArray:[NSArray arrayWithObjects:@"one", @"two", nil]],
		      "a dependency runs before its dependent, and one-at-a-time preserves the order");
		{
			int spins = 0;

			while (!completed && spins++ < 50) {
				[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
			}
		}
		check(completed == 1, "the completion block runs after the operation finishes");
		[queue release];
	}
	{
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		__block int ran = 0;
		NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{
			ran = 1;
		}];

		[operation cancel];
		[queue addOperation:operation];
		[queue waitUntilAllOperationsAreFinished];
		check(ran == 0 && [operation isFinished], "a cancelled operation finishes without running its block");
		[queue release];
	}
	{
		NSBlockOperation *operation = [NSBlockOperation blockOperationWithBlock:^{}];
		NSBlockOperation *dependency = [NSBlockOperation blockOperationWithBlock:^{}];

		[operation addDependency:dependency];
		check(![operation isReady] && [[operation dependencies] count] == 1,
		      "an operation with an unfinished dependency is not ready");
		check([dependency isReady], "an operation with no dependency is ready");
	}

	/* ============================== FILE MANAGER ============================================== */

	{
		NSFileManager *manager = [NSFileManager defaultManager];
		NSString *root = [scratchDirectory() stringByAppendingPathComponent:@"files"];
		NSString *one = [root stringByAppendingPathComponent:@"one.txt"];
		NSString *two = [root stringByAppendingPathComponent:@"two.txt"];
		NSString *moved = [root stringByAppendingPathComponent:@"moved.txt"];
		NSError *error = nil;

		[manager removeItemAtPath:root error:NULL];
		check([manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:&error],
		      "-createDirectoryAtPath:withIntermediateDirectories:");
		check([manager createFileAtPath:one contents:[@"hello" dataUsingEncoding:NSUTF8StringEncoding]
				      attributes:nil], "-createFileAtPath:contents:attributes:");
		check([manager fileExistsAtPath:one], "-fileExistsAtPath:");
		check([[manager contentsOfDirectoryAtPath:root error:&error] count] == 1,
		      "-contentsOfDirectoryAtPath:error:");
		check([[[manager attributesOfItemAtPath:one error:&error] objectForKey:NSFileSize] intValue] == 5,
		      "-attributesOfItemAtPath: reports NSFileSize");
		check([manager moveItemAtPath:one toPath:moved error:&error], "-moveItemAtPath:toPath:error:");
		check(![manager fileExistsAtPath:one] && [manager fileExistsAtPath:moved], "the move removed the source");
		check([manager copyItemAtPath:moved toPath:two error:&error], "-copyItemAtPath:toPath:error:");
		check([manager fileExistsAtPath:two], "the copy exists");
		{
			NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:root];
			NSUInteger seen = 0;

			while ([enumerator nextObject] != nil) {
				seen++;
			}
			check(seen == 2, "-enumeratorAtPath: visits each name once");
		}
		check([manager removeItemAtPath:root error:&error] && ![manager fileExistsAtPath:root],
		      "-removeItemAtPath:error:");
	}
	{
		/* THE ATOMIC REPLACEMENT: the new item takes the original's place, and the backup is kept when asked. */
		NSFileManager *manager = [NSFileManager defaultManager];
		NSString *root = [scratchDirectory() stringByAppendingPathComponent:@"replace"];
		NSString *original = [root stringByAppendingPathComponent:@"original.txt"];
		NSString *replacement = [root stringByAppendingPathComponent:@"replacement.txt"];
		NSString *backup = [root stringByAppendingPathComponent:@"backup.txt"];
		NSURL *resulting = nil;
		NSError *error = nil;

		[manager removeItemAtPath:root error:NULL];
		[manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL];
		[manager createFileAtPath:original contents:[@"old" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
		[manager createFileAtPath:replacement contents:[@"new" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
		check([manager replaceItemAtURL:[NSURL fileURLWithPath:original]
				 withItemAtURL:[NSURL fileURLWithPath:replacement]
				backupItemName:@"backup.txt"
				       options:NSFileManagerItemReplacementWithoutDeletingBackupItem
			      resultingItemURL:&resulting
					 error:&error],
		      "-replaceItemAtURL:withItemAtURL:... succeeds");
		check([[NSString stringWithContentsOfFile:original encoding:NSUTF8StringEncoding error:NULL]
		       isEqualToString:@"new"], "the replacement's contents are at the original path");
		check([manager fileExistsAtPath:backup], "the backup is kept when the option says not to delete it");
		check([[NSString stringWithContentsOfFile:backup encoding:NSUTF8StringEncoding error:NULL]
		       isEqualToString:@"old"], "the backup holds the replaced item's contents");
		check(resulting != nil && [[resulting path] isEqualToString:original],
		      "the resulting item URL names the original path");
		[manager removeItemAtPath:root error:NULL];
	}

	/* ============================== STREAMS =================================================== */

	{
		NSString *path = [scratchDirectory() stringByAppendingPathComponent:@"stream.bin"];
		NSOutputStream *output = [NSOutputStream outputStreamToFileAtPath:path append:NO];
		NSInputStream *input;
		unsigned char written[] = { 'a', 'b', 'c', 0 };
		unsigned char buffer[8];
		NSInteger count;

		[output open];
		check([output write:written maxLength:3] == 3, "-write:maxLength: writes every byte");
		[output close];
		check([[NSData dataWithContentsOfFile:path] length] == 3, "the file stream wrote the bytes");

		input = [NSInputStream inputStreamWithFileAtPath:path];
		[input open];
		check([input hasBytesAvailable], "-hasBytesAvailable on a non-empty file");
		count = [input read:buffer maxLength:sizeof buffer];
		check(count == 3 && memcmp(buffer, "abc", 3) == 0, "-read:maxLength: reads the bytes back");
		[input close];
	}

	/* ============================== UNDO ====================================================== */

	{
		NSUndoManager *undo = [[NSUndoManager alloc] init];
		Person *person = [[Person alloc] init];

		person->name = [@"before" copy];
		[undo registerUndoWithTarget:person selector:@selector(setName:) object:@"before"];
		[person setName:@"after"];
		check([undo canUndo], "-canUndo after a registration");
		[undo undo];
		check([[person name] isEqualToString:@"before"], "-undo restores the registered value");
		/* A PLAIN registration is the undo action only: the redo stack is filled by what the action REGISTERS
		 * while it runs, and a setter that registers nothing leaves it empty. */
		check(![undo canRedo], "a plain undo action leaves nothing to redo");
		[undo removeAllActions];

		/* THE UNDOABLE SETTER: it registers its own inverse through the proxy, which is the pattern that gives
		 * redo something to replay. */
		person->name = [@"after" copy];
		{
			UndoPerson *undoable = [[UndoPerson alloc] init];

			undoable->manager = undo;
			undoable->name = [@"after" copy];
			[undoable setNameUndoably:@"one"];
			check([[undoable name] isEqualToString:@"one"], "an undoable setter changes the value");
			[undo undo];
			check([[undoable name] isEqualToString:@"after"], "undo reverts through the registered inverse");
			check([undo canRedo], "-canRedo after an undoable action");
			[undo redo];
			check([[undoable name] isEqualToString:@"one"], "-redo re-applies the change");

			[undo beginUndoGrouping];
			[undoable setNameUndoably:@"two"];
			[undoable setNameUndoably:@"three"];
			[undo endUndoGrouping];
			[undo undo];
			check([[undoable name] isEqualToString:@"one"], "one undo reverts a whole group");
			[undoable release];
		}
		[person release];
		[undo release];
	}

	/* ============================== REGULAR EXPRESSIONS ======================================= */

	{
		NSError *error = nil;
		NSRegularExpression *expression =
			[NSRegularExpression regularExpressionWithPattern:@"(\\w+)@(\\w+)\\.com" options:0 error:&error];
		NSString *text = @"mail a@x.com and b@y.com now";
		NSTextCheckingResult *match;
		NSString *replaced;

		check(expression != nil && error == nil, "a regular expression compiles");
		check([expression numberOfMatchesInString:text options:0 range:NSMakeRange(0, [text length])] == 2,
		      "-numberOfMatchesInString: counts every match");
		match = [expression firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
		check(match != nil && [match range].location == 5, "-firstMatchInString: reports the range");
		check([[text substringWithRange:[match range]] isEqualToString:@"a@x.com"], "the match range is exact");
		replaced = [expression stringByReplacingMatchesInString:text
							      options:0
								range:NSMakeRange(0, [text length])
							 withTemplate:@"<$1>"];
		check([replaced isEqualToString:@"mail <a> and <b> now"], "the replacement template expands groups");
		check([NSRegularExpression regularExpressionWithPattern:@"(" options:0 error:&error] == nil && error != nil,
		      "an invalid pattern answers nil and an error");
	}

	/* ============================== SCANNER =================================================== */

	{
		NSScanner *scanner = [NSScanner scannerWithString:@"42 hello 3.5"];
		NSInteger integer = 0;
		NSString *word = nil;
		double real = 0;

		check([scanner scanInteger:&integer] && integer == 42, "-scanInteger:");
		check([scanner scanString:@"hello" intoString:&word] && [word isEqualToString:@"hello"],
		      "-scanString:intoString:");
		check([scanner scanDouble:&real] && real == 3.5, "-scanDouble:");
		check([scanner isAtEnd], "-isAtEnd after the last value");
	}

	/* ============================== DATE FORMATTER ============================================ */

	{
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		NSDate *date;
		NSString *text;

		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
		date = [formatter dateFromString:@"2024-02-29 12:34:56"];
		check(date != nil, "a leap day parses with a fixed format");
		text = date != nil ? [formatter stringFromDate:date] : nil;
		check([text isEqualToString:@"2024-02-29 12:34:56"], "the formatter round-trips its own output");
		check([formatter dateFromString:@"2023-02-29 00:00:00"] == nil,
		      "an impossible date answers nil rather than rolling over");
		[formatter release];
	}

	/* ============================== TIMERS ==================================================== */

	{
		__block int fired = 0;
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *t) {
			(void)t;
			fired++;
		}];

		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
		check(fired == 1, "a scheduled one-shot timer fires once");
		check(![timer isValid], "a one-shot timer is invalid after it fires");
	}
	{
		__block int fired = 0;
		NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.01 repeats:NO block:^(NSTimer *t) {
			(void)t;
			fired++;
		}];

		[timer invalidate];
		[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		check(fired == 0, "an invalidated timer does not fire");
	}

	/* ============================== CHARACTER SETS ============================================ */

	{
		NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
		NSCharacterSet *alphanumeric = [NSCharacterSet alphanumericCharacterSet];

		check([whitespace characterIsMember:' '] && [whitespace characterIsMember:'\n'],
		      "whitespaceAndNewlineCharacterSet contains space and newline");
		check(![whitespace characterIsMember:'a'], "it excludes a letter");
		check([alphanumeric characterIsMember:'7'] && [alphanumeric characterIsMember:'z'],
		      "alphanumericCharacterSet contains digits and letters");
		check(![whitespace characterIsMember:'a'] && [[whitespace invertedSet] characterIsMember:'a'],
		      "-invertedSet complements the set");
		check([@"  abc  " rangeOfCharacterFromSet:alphanumeric].location == 2,
		      "-rangeOfCharacterFromSet: finds the first member");
	}

	/* ============================== GEOMETRY VALUES =========================================== */

	{
		NSValue *rangeValue = [NSValue valueWithRange:NSMakeRange(3, 4)];
		NSRange range = [rangeValue rangeValue];
		NSRange a = NSMakeRange(0, 5);
		NSRange b = NSMakeRange(3, 5);

		check(range.location == 3 && range.length == 4, "a range round-trips through NSValue");
		check(NSEqualRanges(NSIntersectionRange(a, b), NSMakeRange(3, 2)), "NSIntersectionRange");
		check(NSEqualRanges(NSUnionRange(a, b), NSMakeRange(0, 8)), "NSUnionRange");
		check(NSPointInRect(NSMakePoint(1, 1), NSMakeRect(0, 0, 2, 2)), "NSPointInRect");
		check(NSMaxRange(NSMakeRange(2, 3)) == 5, "NSMaxRange");
	}

	[pool drain];
	printf(g_fail ? "foundation_behaviour: FAIL\n" : "foundation_behaviour: all checks passed\n");
	return g_fail;
}
