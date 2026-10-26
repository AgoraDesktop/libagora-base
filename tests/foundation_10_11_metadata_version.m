/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_metadata_version.m — THE QUERY'S 10.9 DOORS, AN ITEM BY URL, AND A VERSION REPLACED THROUGH A
 * COORDINATED INTENT.
 *
 * W6's tail fills NSMetadataQuery (searchItems, operationQueue, the two block walks), NSMetadataItem's
 * `-initWithURL:`, the six NSFileVersion doors that do not need a version store, and NSFileCoordinator's asynchronous
 * intent door. The version replacement is the one that needs the coordinator: Apple runs `-replaceItemAtURL:…` INSIDE a
 * coordinated write accessor, so the probe drives it exactly that way — through `-coordinateAccessWithIntents:queue:
 * byAccessor:` on a real NSOperationQueue — and then reads the target's bytes back.
 */
#import <Foundation/Foundation.h>
#import <Foundation/NSMetadata.h>
#import <Foundation/NSFileVersion.h>
#import <Foundation/NSFileCoordinator.h>
#import <Foundation/NSOperationQueue.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) { g_pass++; return; }
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

static NSString *write_file(NSString *directory, NSString *name, const char *contents)
{
	NSString *path = [directory stringByAppendingPathComponent:name];
	FILE *file = fopen([path fileSystemRepresentation], "w");

	if (file != NULL) {
		fputs(contents, file);
		fclose(file);
	}
	return path;
}

static NSString *read_file(NSString *path)
{
	NSData *data = [NSData dataWithContentsOfFile:path];

	return data != nil ? [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease] : nil;
}

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	char template[] = "/tmp/agora-metadata-version-XXXXXX";
	char *made = mkdtemp(template);
	NSString *directory = [[NSString alloc] initWithUTF8String:made];

	/* ---- NSMetadataQuery: searchItems names the scope, operationQueue is stored, the walks answer the results ---- */
	{
		NSMetadataQuery *query = [[NSMetadataQuery alloc] init];
		NSURL *scope = [NSURL fileURLWithPath:directory];
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		NSMetadataItem *item;
		__block NSUInteger visited = 0;
		__block NSUInteger firstIndex = NSNotFound;

		write_file(directory, @"alpha.txt", "a");
		write_file(directory, @"beta.txt", "bb");
		[query setSearchItems:[NSArray arrayWithObject:scope]];
		[query setOperationQueue:queue];
		check([[query searchItems] count] == 1 && [[[query searchItems] objectAtIndex:0] isEqual:scope],
		      "searchItems reports the file URL it was given");
		check([query operationQueue] == queue, "operationQueue is stored and reported");
		[query startQuery];
		check([query resultCount] == 2, "searchItems alone is the scope: the query walks it");
		[query enumerateResultsUsingBlock:^(id result, NSUInteger index, BOOL *stop) {
			(void)result; (void)index; (void)stop;
			visited++;
		}];
		check(visited == 2, "enumerateResultsUsingBlock visits every result");
		[query enumerateResultsWithOptions:NSEnumerationReverse
					usingBlock:^(id result, NSUInteger index, BOOL *stop) {
			(void)result;
			if (firstIndex == NSNotFound) { firstIndex = index; }
			*stop = YES;
		}];
		check(firstIndex == 1, "a reverse walk starts at the last result and keeps its own index");
		[query stopQuery];
		item = [[[NSMetadataItem alloc] initWithURL:[NSURL fileURLWithPath:
			[directory stringByAppendingPathComponent:@"beta.txt"]]] autorelease];
		check([[[item valueForAttribute:@"kMDItemFSName"] description] isEqualToString:@"beta.txt"] &&
		      [[item valueForAttribute:@"kMDItemFSSize"] unsignedLongLongValue] == 2,
		      "an item made from a URL reads the file's own attributes");
		item = [[[NSMetadataItem alloc] initWithURL:[NSURL fileURLWithPath:
			[directory stringByAppendingPathComponent:@"absent.txt"]]] autorelease];
		check([[item attributes] count] == 0, "a URL that is not there has no file facts to report");
		[query release];
		[queue release];
	}

	/* ---- NSFileVersion: the flags are stored, the saving computer is absent, and a replacement is a real copy ---- */
	{
		NSString *source = write_file(directory, @"source.txt", "second");
		NSString *target = write_file(directory, @"target.txt", "first");
		NSFileVersion *version = [NSFileVersion currentVersionOfItemAtURL:[NSURL fileURLWithPath:source]];
		NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
		NSFileAccessIntent *intent = [NSFileAccessIntent writingIntentWithURL:[NSURL fileURLWithPath:target]
									      options:NSFileCoordinatorWritingForReplacing];
		NSOperationQueue *queue = [[NSOperationQueue alloc] init];
		__block BOOL accessorRan = NO;
		__block BOOL replaced = NO;
		__block NSError *replacementError = nil;

		check(version != nil && [version isResolved] == NO && [version isDiscardable] == NO,
		      "a current version starts with both flags NO");
		[version setResolved:YES];
		[version setDiscardable:YES];
		check([version isResolved] && [version isDiscardable],
		      "the two flags report what the caller set");
		check([version localizedNameOfSavingComputer] == nil,
		      "no saving computer is recorded, so the name is nil rather than invented");
		[coordinator coordinateAccessWithIntents:[NSArray arrayWithObject:intent]
						   queue:queue
					      byAccessor:^(NSError *error) {
			accessorRan = YES;
			if (error != nil) { return; }
			replaced = [version replaceItemAtURL:[NSURL fileURLWithPath:target]
						     options:0
						       error:&replacementError];
		}];
		[queue waitUntilAllOperationsAreFinished];
		check(accessorRan, "the intent door runs its accessor on the queue");
		check(replaced && replacementError == nil && [read_file(target) isEqualToString:@"second"],
		      "the replacement copied this version's bytes over the target");
		[coordinator release];
		[queue release];

		/* THE BY-MOVING FORM, on a fresh pair: the version's own item moves onto the target. */
		{
			NSString *moving = write_file(directory, @"moving.txt", "moved");
			NSString *destination = write_file(directory, @"destination.txt", "older");
			NSFileVersion *mover = [NSFileVersion currentVersionOfItemAtURL:[NSURL fileURLWithPath:moving]];
			BOOL ok = [mover replaceItemAtURL:[NSURL fileURLWithPath:destination]
						  options:NSFileVersionReplacingByMoving
						    error:NULL];

			check(ok && [read_file(destination) isEqualToString:@"moved"] &&
			      ![[NSFileManager defaultManager] fileExistsAtPath:moving],
			      "replacing by moving takes the version's item with it");
		}
	}

	[directory release];
	[[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithUTF8String:template] error:NULL];
	printf("foundation_10_11_metadata_version: %d of %d cases passed, %d failed\n",
	       g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
