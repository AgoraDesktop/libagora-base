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
		[query startQuery];
		check([query resultCount] == 2, "the metadata query finds the two files");
		check([[query results] count] == 2 &&
		      [[[query resultAtIndex:0] valueForAttribute:@"kMDItemPath"] isKindOfClass:[NSString class]],
		      "a result answers its attributes");
		check([[query groupedResults] count] > 0, "grouping produces groups");
		check([[query valueLists] count] == 1, "a value-list attribute produces tuples");
		check(![query isGathering] && [query isStarted], "the query is gathered and started");
		[query stopQuery];
		check([query isStopped], "stopQuery marks the query stopped");
		[query release];

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
