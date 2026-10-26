/*
 * scripting_surface — the F3/F5/F6/F10/F11 classes, measured by a caller.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. The census can now say 100% of the 10.6 surface has a body; it cannot say the bodies mean
 * anything. This probe exercises the object-specifier walk, a whose-test, three standard commands, a suite-declared
 * class description, the AppleEvent descriptor as data, the AppleScript refusal, a real metadata query over a
 * temporary directory, and the TXT-record codec plus the net-service refusal.
 */

#import <Foundation/Foundation.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

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

@interface Item : NSObject
{
@public
	NSString *itemName;
	NSNumber *size;
}
@end

@implementation Item
- (NSString *)name { return itemName; }
- (void)setName:(NSString *)value { [itemName release]; itemName = [value copy]; }
- (NSNumber *)size { return size; }
- (void)setSize:(NSNumber *)value { [size release]; size = [value copy]; }
@end

@interface Box : NSObject
{
@public
	NSMutableArray *items;
}
@end

@implementation Box
- (NSArray *)items { return items; }
@end

@interface NetProbe : NSObject
{
@public
	int didNotPublish;
	int didNotSearch;
	int metadataUpdated;
}
@end

@implementation NetProbe
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
	(void)sender; (void)errorDict;
	didNotPublish++;
}
- (void)netServiceBrowser:(id)browser didNotSearch:(NSDictionary *)errorDict
{
	(void)browser; (void)errorDict;
	didNotSearch++;
}
- (void)metadataUpdated:(NSNotification *)notification
{
	(void)notification;
	metadataUpdated++;
}
@end

static Box *
makeBox(void)
{
	Box *box = [[Box alloc] init];
	Item *one = [[Item alloc] init];
	Item *two = [[Item alloc] init];
	Item *three = [[Item alloc] init];

	one->itemName = [@"one" copy];
	one->size = [[NSNumber numberWithInt:1] retain];
	two->itemName = [@"two" copy];
	two->size = [[NSNumber numberWithInt:2] retain];
	three->itemName = [@"three" copy];
	three->size = [[NSNumber numberWithInt:3] retain];
	box->items = [[NSMutableArray alloc] initWithObjects:one, two, three, nil];
	[one release];
	[two release];
	[three release];
	return box;
}

int
main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	Box *box = makeBox();

	[[NSScriptExecutionContext sharedScriptExecutionContext] setTopLevelObject:box];

	/* AN INDEX SPECIFIER WALKS container -> key -> element. */
	{
		NSScriptObjectSpecifier *specifier =
			[[NSIndexSpecifier alloc] initWithContainerClassDescription:nil
									  containerSpecifier:nil
										       key:@"items"
										     index:1];
		id object = [specifier objectsByEvaluatingSpecifier];

		check([object isKindOfClass:[NSArray class]] && [[object objectAtIndex:0] isEqual:[[box items] objectAtIndex:1]],
		      "an index specifier names one element of the container's array");
		[specifier release];
	}

	/* A WHOSE SPECIFIER FILTERS WITH A TEST OVER THE OBJECT BEING TESTED. */
	{
		NSScriptObjectSpecifier *property =
			[[NSPropertySpecifier alloc] initWithContainerClassDescription:nil
									   containerSpecifier:nil
											key:@"size"];
		NSScriptWhoseTest *test =
			[[NSSpecifierTest alloc] initWithObjectSpecifier:property
					      comparisonOperator:NSGreaterThanComparison
						      testObject:[NSNumber numberWithInt:1]];
		NSWhoseSpecifier *whose =
			[[NSWhoseSpecifier alloc] initWithContainerClassDescription:nil
								  containerSpecifier:nil
									       key:@"items"
									      test:test];
		NSArray *found;

		[property setContainerIsObjectBeingTested:YES];
		found = [whose objectsByEvaluatingSpecifier];
		check([found count] == 2, "a whose specifier keeps the elements its test accepts");
		[whose release];
		[test release];
		[property release];
	}

	/* THREE STANDARD COMMANDS. */
	{
		NSScriptObjectSpecifier *receivers =
			[[NSPropertySpecifier alloc] initWithContainerClassDescription:nil
									   containerSpecifier:nil
											key:@"items"];
		NSScriptCommand *countCommand = [[NSCountCommand alloc] initWithCommandDescription:nil];
		NSScriptCommand *getCommand = [[NSGetCommand alloc] initWithCommandDescription:nil];
		NSScriptCommand *setCommand = [[NSSetCommand alloc] initWithCommandDescription:nil];
		NSScriptObjectSpecifier *nameSpecifier =
			[[NSPropertySpecifier alloc] initWithContainerClassDescription:nil
									   containerSpecifier:nil
											key:@"name"];

		[countCommand setReceiversSpecifier:receivers];
		check([[countCommand executeCommand] intValue] == 3, "NSCountCommand counts its receivers");

		[getCommand setReceiversSpecifier:receivers];
		check([[getCommand executeCommand] count] == 3, "NSGetCommand answers the receivers");

		[setCommand setReceiversSpecifier:receivers];
		[setCommand setKeySpecifier:nameSpecifier];
		[setCommand setDirectParameter:@"renamed"];
		[setCommand executeCommand];
		check([[[[box items] objectAtIndex:0] name] isEqualToString:@"renamed"],
		      "NSSetCommand writes through the key specifier");
		[setCommand release];
		[getCommand release];
		[countCommand release];
		[nameSpecifier release];
		[receivers release];
	}

	/* A SUITE-DECLARED CLASS DESCRIPTION READS ITS DICTIONARY. */
	{
		NSDictionary *declaration = [NSDictionary dictionaryWithObjectsAndKeys:
			@"Item", @"ImplementationClassName",
			[NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObject:@"NSString" forKey:@"Type"]
						    forKey:@"name"], @"Attributes",
			[NSDictionary dictionaryWithObject:[NSDictionary dictionaryWithObject:@"Box"
										      forKey:@"Class"]
						    forKey:@"items"], @"ToManyRelationships",
			nil];
		NSScriptClassDescription *description =
			[[NSScriptClassDescription alloc] initWithSuiteName:@"Probe" className:@"Item"
								 dictionary:declaration];

		check([[description attributeKeys] containsObject:@"name"], "a class description reports its attributes");
		check([[[description typeForKey:@"name"] description] isEqualToString:@"NSString"],
		      "a class description reports a type");
		check([description hasPropertyForKey:@"items"], "a class description reports a relationship");
		check([description supportsCommand:@"noSuchCommand"] == NO, "an undeclared command is not supported");
		check([[description className] isEqualToString:@"Item"], "the class name is the declared one");
	}

	/* THE APPLE EVENT DESCRIPTOR AS DATA. */
	{
		NSAppleEventDescriptor *text = [NSAppleEventDescriptor descriptorWithString:@"hello"];
		NSAppleEventDescriptor *number = [NSAppleEventDescriptor descriptorWithInt32:42];
		NSAppleEventDescriptor *list = [[[NSAppleEventDescriptor alloc] initListDescriptor] autorelease];
		NSAppleEventDescriptor *record = [[[NSAppleEventDescriptor alloc] initRecordDescriptor] autorelease];

		check([[text stringValue] isEqualToString:@"hello"], "a string descriptor answers its string");
		check([number int32Value] == 42, "an int32 descriptor answers its number");
		[list insertDescriptor:text atIndex:0];
		[list insertDescriptor:number atIndex:1];
		check([list numberOfItems] == 2 && [[[list descriptorAtIndex:0] stringValue] isEqualToString:@"hello"],
		      "a list descriptor holds its items in order");
		[record setDescriptor:text forKeyword:'nm  '];
		check([[[record descriptorForKeyword:'nm  '] stringValue] isEqualToString:@"hello"],
		      "a record descriptor answers by keyword");
		check([[[number coerceToDescriptorType:typeUTF8Text] stringValue] isEqualToString:@"42"],
		      "coercion to text goes through the value");
	}

	/* THE DESCRIPTOR TYPES OF 10.11, AND THE SEND THAT REFUSES. A double, a date and a file URL each round-trip
	 * through their own type code; a process descriptor is a record keyed the way Apple keys it; and a send answers
	 * nil with the feature-unsupported error rather than pretending an event left the process. */
	{
		NSAppleEventDescriptor *doubled = [NSAppleEventDescriptor descriptorWithDouble:2.5];
		NSDate *when = [NSDate dateWithTimeIntervalSinceReferenceDate:1234.5];
		NSAppleEventDescriptor *dated = [NSAppleEventDescriptor descriptorWithDate:when];
		NSURL *file = [NSURL fileURLWithPath:@"/tmp/agora-descriptor.txt"];
		NSAppleEventDescriptor *filed = [NSAppleEventDescriptor descriptorWithFileURL:file];
		NSAppleEventDescriptor *bundled =
			[NSAppleEventDescriptor descriptorWithBundleIdentifier:@"com.example.agora"];
		NSAppleEventDescriptor *appURL =
			[NSAppleEventDescriptor descriptorWithApplicationURL:[NSURL fileURLWithPath:@"/Applications/Agora.app"]];
		NSAppleEventDescriptor *process = [NSAppleEventDescriptor currentProcessDescriptor];
		NSAppleEventDescriptor *byPID =
			[NSAppleEventDescriptor descriptorWithProcessIdentifier:(pid_t)getpid()];
		NSError *sendError = nil;

		check([doubled descriptorType] == typeIEEE64BitFloatingPoint && [doubled doubleValue] == 2.5,
		      "a double descriptor is a 64-bit float and answers its value");
		check([[[NSAppleEventDescriptor descriptorWithInt32:7] description] length] > 0 &&
		      [[NSAppleEventDescriptor descriptorWithInt32:7] doubleValue] == 7.0,
		      "a 'long' descriptor answers a double through the integer door");
		check([dated descriptorType] == typeDate &&
		      fabs([[dated dateValue] timeIntervalSinceReferenceDate] - 1234.5) < 0.001,
		      "a date descriptor is a long datetime and round-trips to the same instant");
		check([filed descriptorType] == typeFileURL && [[filed fileURLValue] isEqual:file],
		      "a file URL descriptor carries its own type code and reads back as the URL");
		check([[filed fileURLValue] isFileURL] && [dated fileURLValue] == nil,
		      "a descriptor of another type has no file URL");
		check([bundled descriptorType] == typeApplicationBundleID &&
		      [[bundled stringValue] isEqualToString:@"com.example.agora"],
		      "a bundle identifier is its own type code with the string as payload");
		check([appURL descriptorType] == typeApplicationURL &&
		      [[appURL stringValue] isEqualToString:@"file:///Applications/Agora.app"],
		      "an application URL is its own type code with the absolute string as payload");
		check([process isRecordDescriptor] && [[process descriptorForKeyword:keyProcessSerialNumber] int32Value] ==
		      (SInt32)getpid(), "the current process descriptor is a record keyed by its process id");
		check([[byPID descriptorForKeyword:keyProcessSerialNumber] int32Value] == (SInt32)getpid() &&
		      [doubled isRecordDescriptor] == NO &&
		      [[[[NSAppleEventDescriptor alloc] initRecordDescriptor] autorelease] isRecordDescriptor],
		      "only a record descriptor answers YES to isRecordDescriptor");
		check([NSAppleEventDescriptor appleEventWithEventClass:'aevt'
								 eventID:'oapp'
							targetDescriptor:nil
								returnID:0
							   transactionID:0] != nil &&
			      [[NSAppleEventDescriptor appleEventWithEventClass:'aevt'
								       eventID:'oapp'
								targetDescriptor:nil
									returnID:0
								   transactionID:0] isRecordDescriptor],
			      "an Apple event IS a record descriptor");
		check([doubled sendEventWithOptions:NSAppleEventSendDefaultOptions timeout:1.0 error:&sendError] == nil &&
		      sendError != nil && [sendError code] == NSFeatureUnsupportedError,
		      "a send refuses with the feature-unsupported error and delivers nothing");
	}

	/* APPLESCRIPT COMPILES AND REFUSES TO RUN. */
	{
		NSError *error = nil;
		NSAppleScript *script = [[NSAppleScript alloc] initWithSource:@"return 1"];

		check([script compileAndReturnError:&error] && error == nil, "an AppleScript compiles");
		check([script executeAndReturnError:&error] == nil && error != nil,
		      "execution refuses with an error naming the absent OSA component");
		[script release];
	}

	/* A REAL METADATA QUERY OVER A TEMPORARY DIRECTORY. */
	{
		char template[] = "/tmp/agora-metadata-XXXXXX";
		char *directory = mkdtemp(template);
		char first[512], second[512];
		FILE *file;
		NSMetadataQuery *query = [[NSMetadataQuery alloc] init];
		NSPredicate *predicate = [NSPredicate predicateWithFormat:@"kMDItemFSSize > 0"];

		snprintf(first, sizeof first, "%s/one.txt", directory);
		snprintf(second, sizeof second, "%s/two.txt", directory);
		file = fopen(first, "w");
		if (file != NULL) {
			fputs("one", file);
			fclose(file);
		}
		file = fopen(second, "w");
		if (file != NULL) {
			fputs("twotwo", file);
			fclose(file);
		}
		[query setSearchScopes:[NSArray arrayWithObject:[NSString stringWithUTF8String:directory]]];
		[query setPredicate:predicate];
		[query setGroupingAttributes:[NSArray arrayWithObject:@"kMDItemContentType"]];
		[query setValueListAttributes:[NSArray arrayWithObject:@"kMDItemContentType"]];
		[query setNotificationBatchingInterval:0.05];
		[query startQuery];
		check([query resultCount] == 2, "the metadata query finds the two files");
		check([[query results] count] == 2 &&
		      [[[query resultAtIndex:0] valueForAttribute:@"kMDItemPath"] isKindOfClass:[NSString class]],
		      "a result answers its attributes");
		check([[query groupedResults] count] > 0, "grouping produces groups");
		check([[query valueLists] count] == 1, "a value-list attribute produces tuples");
		check(![query isGathering] && [query isStarted], "the query is gathered and started");

		/* A LIVE UPDATE: a file added while the query runs is seen by the provider's poll and announced. */
		{
			NetProbe *observer = [[NetProbe alloc] init];
			FILE *third;
			int spins = 0;

			[[NSNotificationCenter defaultCenter] addObserver:observer
								 selector:@selector(metadataUpdated:)
								     name:NSMetadataQueryDidUpdateNotification
								   object:query];
			third = fopen([[[NSString stringWithUTF8String:directory]
					stringByAppendingPathComponent:@"three.txt"] UTF8String], "w");
			if (third != NULL) {
				fputs("three", third);
				fclose(third);
			}
			while (observer->metadataUpdated == 0 && spins++ < 40) {
				[[NSRunLoop currentRunLoop] runUntilDate:
					[NSDate dateWithTimeIntervalSinceNow:0.05]];
			}
			check(observer->metadataUpdated > 0, "an added file produces an update notification");
			check([query resultCount] == 3, "the update brought the new file into the results");
			[[NSNotificationCenter defaultCenter] removeObserver:observer
									name:NSMetadataQueryDidUpdateNotification
								      object:query];
			[observer release];
		}
		[query stopQuery];
		check([query isStopped], "stopQuery marks the query stopped");
		[query release];

		{
			char third[512];

			snprintf(third, sizeof third, "%s/three.txt", directory);
			unlink(third);
		}
		unlink(first);
		unlink(second);
		rmdir(directory);
	}

	/* THE TXT-RECORD CODEC, AND THE NET-SERVICE REFUSAL. */
	{
		NSDictionary *record = [NSDictionary dictionaryWithObject:[@"value" dataUsingEncoding:NSUTF8StringEncoding]
								  forKey:@"key"];
		NSData *data = [NSNetService dataFromTXTRecordDictionary:record];
		NSDictionary *decoded = [NSNetService dictionaryFromTXTRecordData:data];
		NSString *decodedValue = [[[NSString alloc] initWithData:[decoded objectForKey:@"key"]
							       encoding:NSUTF8StringEncoding] autorelease];
		NetProbe *probe = [[NetProbe alloc] init];
		NSNetService *service = [[NSNetService alloc] initWithDomain:@"local."
								      type:@"_probe._tcp."
								      name:@"probe"
								      port:1234];
		NSNetServiceBrowser *browser = [[NSNetServiceBrowser alloc] init];

		check([decodedValue isEqualToString:@"value"], "the TXT-record codec round-trips");
		[service setDelegate:probe];
		[service publish];
		check(probe->didNotPublish == 1, "publishing reports the absent DNS-SD responder");
		[browser setDelegate:probe];
		[browser searchForServicesOfType:@"_probe._tcp." inDomain:@"local."];
		check(probe->didNotSearch == 1, "browsing reports the absent DNS-SD responder");
		[browser release];
		[service release];
		[probe release];
	}

	[box release];
	[pool drain];
	printf(g_fail ? "scripting_surface: FAIL\n" : "scripting_surface: all checks passed\n");
	return g_fail;
}
