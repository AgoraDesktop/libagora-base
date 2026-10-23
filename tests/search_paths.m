/*
 * search_paths — `NSSearchPathForDirectoriesInDomains()` and the URL doors: the installation's
 * directory set, answered by domain.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * **THIS SUITE EXISTS BECAUSE THE DOOR USED TO REFUSE.** It answered an empty array and wrote a line on
 * the log, so nothing measured what a caller gets; AppKit worked around it by building `~/Library` out of
 * `NSHomeDirectory()`, and `NSDocumentController`'s autosave failed because `NSTemporaryDirectory()`
 * named a directory the installation did not create. Now that a complete installation carries the Mac OS
 * X directory set (README, "The installation"), the answer is a table and this suite pins it:
 *
 *   1. The USER domain is the home directory's own subdirectory, `expandTilde` changes only its SPELLING.
 *   2. LOCAL and SYSTEM are the machine's trees, and they are DIFFERENT directories for the library
 *      (`/Library` vs `/System/Library`) while the application folder is the same one on both.
 *   3. A domain a directory does not belong to answers NOTHING (`~/Documents` has no local answer), the
 *      NETWORK domain has no tree, and `NSItemReplacementDirectory` is not a location at all.
 *   4. The two UNION types compose from the same directories, in Apple's domain order, without repeats.
 *   5. The URL doors are the same answer in URL spelling, and `create:` really makes the directory.
 *
 * THE ANSWER IS A PATH, NOT AN EXISTENCE CHECK. `/Library` is answered on a machine that has none, which
 * is Apple's behavior and the reason case 2 asks for the spelling rather than `fileExistsAtPath:`.
 */
#import <Foundation/Foundation.h>

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static int g_failed;

static void check(int ok, const char *what)
{
	printf("  %s %s\n", ok ? "ok  " : "FAIL", what);
	if (!ok) {
		g_failed++;
	}
}

static BOOL array_is(NSArray *paths, NSString *first, ...)
{
	va_list arguments;
	BOOL ok = YES;
	int index = 0;
	NSString *expected;

	va_start(arguments, first);
	for (expected = first; expected != nil; expected = va_arg(arguments, NSString *)) {
		if ((NSUInteger)index >= [paths count] || ![[paths objectAtIndex:(NSUInteger)index] isEqual:expected]) {
			ok = NO;
			break;
		}
		index++;
	}
	va_end(arguments);
	return ok && [paths count] == (NSUInteger)index;
}

int main(void)
{
	@autoreleasepool {
		NSString *home = NSHomeDirectory();
		NSArray *paths;

		/* 1. The user domain, and the two spellings of one directory. */
		paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, NO);
		check(array_is(paths, [home stringByAppendingPathComponent:@"Library"], nil),
		      "NSLibraryDirectory in the user domain is ~/Library");

		paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
		check(array_is(paths, @"~/Library", nil),
		      "expandTilde spells the same directory ~/Library");

		paths = NSSearchPathForDirectoriesInDomains(NSUserDirectory, NSUserDomainMask, NO);
		check(array_is(paths, home, nil), "NSUserDirectory in the user domain is the home directory itself");

		paths = NSSearchPathForDirectoriesInDomains(NSUserDirectory, NSUserDomainMask, YES);
		check(array_is(paths, @"~", nil), "the home directory itself spells ~");

		/* 2. Local and system are the machine's trees. */
		paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, NO);
		check(array_is(paths, @"/Library", nil), "NSLibraryDirectory local is /Library");

		paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSSystemDomainMask, NO);
		check(array_is(paths, @"/System/Library", nil), "NSLibraryDirectory system is /System/Library");

		paths = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSLocalDomainMask, NO);
		check(array_is(paths, @"/Applications", nil), "the local application folder is /Applications");

		paths = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSSystemDomainMask, NO);
		check(array_is(paths, @"/Applications", nil), "the system application folder is the same one");

		paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, NO);
		check(array_is(paths, [home stringByAppendingPathComponent:@"Library/Application Support"], nil),
		      "a directory name with a space survives the join");

		paths = NSSearchPathForDirectoriesInDomains(NSCoreServiceDirectory, NSSystemDomainMask, NO);
		check(array_is(paths, @"/System/Library/CoreServices", nil), "CoreServices is the system's");

		/* 3. The refusals: a domain that does not carry the directory, the network, and the two
		 *    types that are not locations. */
		paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSLocalDomainMask, NO);
		check([paths count] == 0, "NSDocumentDirectory has no local answer");

		paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSNetworkDomainMask, NO);
		check([paths count] == 0, "there is no network tree");

		paths = NSSearchPathForDirectoriesInDomains(NSItemReplacementDirectory, NSAllDomainsMask, NO);
		check([paths count] == 0, "NSItemReplacementDirectory is an allocation, not a location");

		/* 4. The unions, in domain order and without repeats. */
		paths = NSSearchPathForDirectoriesInDomains(NSAllLibrariesDirectory, NSAllDomainsMask, NO);
		check(array_is(paths, [home stringByAppendingPathComponent:@"Library"], @"/Library",
			       @"/System/Library", nil),
		      "NSAllLibrariesDirectory is user, local, system");

		paths = NSSearchPathForDirectoriesInDomains(NSAllApplicationsDirectory, NSAllDomainsMask, NO);
		check(array_is(paths, [home stringByAppendingPathComponent:@"Applications"], @"/Applications",
			       @"/Applications/Utilities", nil),
		      "NSAllApplicationsDirectory is user then local/system, without repeats");

		/* 5. The URL doors answer the same table. */
		{
			NSFileManager *manager = [NSFileManager defaultManager];
			NSArray *urls = [manager URLsForDirectory:NSApplicationDirectory
						       inDomains:NSLocalDomainMask | NSSystemDomainMask];
			NSError *error = nil;
			NSURL *url;

			check([urls count] == 1 && [[[urls objectAtIndex:0] path] isEqual:@"/Applications"],
			      "-URLsForDirectory: wraps the same path, and a repeated answer stays one URL");

			url = [manager URLForDirectory:NSLibraryDirectory inDomain:NSUserDomainMask
				      appropriateForURL:nil create:NO error:&error];
			check(url != nil && [[url path] isEqual:[home stringByAppendingPathComponent:@"Library"]],
			      "-URLForDirectory: answers ~/Library without creating it");

			error = nil;
			url = [manager URLForDirectory:NSDocumentDirectory inDomain:NSLocalDomainMask
				      appropriateForURL:nil create:NO error:&error];
			check(url == nil && error != nil && [error code] == ENOENT,
			      "a directory with no answer is nil and an error, not an empty URL");

			/* `create:` IS MEASURED WITH A DIRECTORY THAT IS THE HOME'S OWN AND NOTHING ELSE'S. The
			 * suite leaves the tree as it found it: the leaf is removed again only when this run made it. */
			{
				NSString *leaf = [home stringByAppendingPathComponent:@"Library/Application Scripts"];
				BOOL existed = [[NSFileManager defaultManager] fileExistsAtPath:leaf];

				error = nil;
				url = [manager URLForDirectory:NSApplicationScriptsDirectory inDomain:NSUserDomainMask
					      appropriateForURL:nil create:YES error:&error];
				check(url != nil && error == nil && [[NSFileManager defaultManager] fileExistsAtPath:leaf],
				      "create:YES makes the directory, intermediates and all");

				if (!existed) {
					rmdir([leaf fileSystemRepresentation]);
				}
			}
		}
	}
	printf("%s\n", g_failed == 0 ? "search_paths: all checks passed" : "search_paths: FAILED");
	return g_failed == 0 ? 0 : 1;
}
