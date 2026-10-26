/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPathUtilities.h — paths, and the directories the installation carries (W7), in Apple's own file.
 *
 * Two things live here because Apple puts them here: the SEARCH-PATH types and functions (`NSSearchPathDirectory`,
 * `NSSearchPathForDirectoriesInDomains`, and the home/temporary/user-name doors), and the String path category
 * (`NSStringPathExtensions`). NSFileManager.h imports this header because `-URLsForDirectory:inDomains:` takes the
 * types, which is Apple's arrangement too.
 *
 * THE CATEGORY IS APPLE'S HOME FOR THE DOORS, WHICH NSString.h ALSO DECLARES. This tree's NSString.h has carried them
 * on the class since the string slice; W7 adds the category under Apple's name rather than moving them, because a
 * source file that imports only NSString.h has always been able to call them and moving a declaration out from under
 * such a file would be a regression for no client-visible gain. The declarations are identical, so the ledger and the
 * compiler see one door.
 */
#ifndef FOUNDATION_NSPATHUTILITIES_H
#define FOUNDATION_NSPATHUTILITIES_H

#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>

NS_ASSUME_NONNULL_BEGIN

/*
 * THE SEARCH PATH TYPES, and the one place where Apple's own value choices are
 * visible in the API's shape rather than in a header: -URLsForDirectory:inDomains:
 * takes the domain mask and ORs the bits together, so NSSearchPathDomainMask is a
 * bit set even though its cases do not say "Options".
 */
typedef enum {
	NSApplicationDirectory = 0,
	NSDemoApplicationDirectory,
	NSDeveloperApplicationDirectory,
	NSAdminApplicationDirectory,
	NSLibraryDirectory,
	NSDeveloperDirectory,
	NSUserDirectory,
	NSDocumentationDirectory,
	NSDocumentDirectory,
	NSCoreServiceDirectory,
	NSAutosavedInformationDirectory,
	NSDesktopDirectory,
	NSCachesDirectory,
	NSApplicationSupportDirectory,
	NSDownloadsDirectory,
	NSInputMethodsDirectory,
	NSMoviesDirectory,
	NSMusicDirectory,
	NSPicturesDirectory,
	NSPrinterDescriptionDirectory,
	NSSharedPublicDirectory,
	NSPreferencePanesDirectory,
	NSApplicationScriptsDirectory,
	NSItemReplacementDirectory,
	NSAllApplicationsDirectory,
	NSAllLibrariesDirectory,
	NSTrashDirectory
} NSSearchPathDirectory;

typedef enum {
	NSUserDomainMask = 1 << 0,
	NSLocalDomainMask = 1 << 1,
	NSNetworkDomainMask = 1 << 2,
	NSSystemDomainMask = 1 << 3,
	NSAllDomainsMask = 0xFFFF	/* every bit, as its name says */
} NSSearchPathDomainMask;

/* WHERE TEMPORARY FILES GO, as a FUNCTION rather than a method because that is how Apple declares it (the
 * ledger files it under NSFileManager's "Accessing user directories"). The trailing separator is Apple's
 * spelling, and the path is the FSH's own: `/System/Temporary Files`, which a complete Agora installation
 * CREATES (README, "The installation") - a path this function answers has to be one an application can
 * write into, which is what the handoff's autosave failure measured when it was not. The directory is not
 * recreated at mount the way the FNX kernel's init does for its own tree: on a hosted install the
 * installer owns it.
 *
 * NSHomeDirectory() AND NSHomeDirectoryForUser() ARE STILL ABSENT, named: both need the account database,
 * which this tree reads through the passwd domain, and mapping a uid to a home directory is its own row
 * rather than a path constant. Only the temporary directory is answered here. */
NSString *NSTemporaryDirectory(void);

/* ---- THE USER-DIRECTORY AND LEGACY PATH FUNCTIONS (the coverage slice) -------------------------------
 *
 * THE ROW EARLIER IN THIS HEADER THAT DEFERRED NSHomeDirectory() IS NOW PAID: it waited for "the account
 * database", and this tree reads that through the passwd domain - the same getpwuid(3) that
 * NSFileManager's own account-name code and NSUserDefaults already use. A home directory is therefore NOT a
 * policy this class invents: it is the pw_dir the account database answers, exactly as Apple's does. An
 * unknown user answers nil (Apple's contract for NSHomeDirectoryForUser:).
 */
extern NSString * _Nullable NSUserName(void);
extern NSString * _Nullable NSFullUserName(void);
extern NSString * NSHomeDirectory(void);
extern NSString * _Nullable NSHomeDirectoryForUser(NSString * _Nullable userName);
extern NSString * NSOpenStepRootDirectory(void);

/* ---- THE SEARCH PATH, FOR THE DIRECTORIES THE INSTALLATION CARRIES ----------------------------
 *
 * ONE TABLE, ANSWERED BY DOMAIN, AND IT LIVES IN CORE FOUNDATION (CFSystemDirectories.c). Apple's function
 * is a SEARCH (locale directories, the user's chosen folders, network mounts); this system's directories are
 * NAMED by the image instead - the root holds /Applications, /Library, /System, /Users and /Volumes, and a
 * home holds ~/Applications, ~/Desktop, ~/Library and the rest - so the answer for a (directory, domain)
 * pair is a fact rather than a scan. Which directories exist and who creates them is README, "The
 * installation"; this function is that table in the form an Objective-C program asks for it, and
 * CFCopySearchPathForDirectoriesInDomains() is the same table in the form a C program does.
 *
 * A DOMAIN THE DIRECTORY DOES NOT BELONG TO ANSWERS NOTHING (a Documents folder is the user's, a
 * CoreServices directory is the system's), the network domain has no tree on this system, and an answer
 * is never repeated. Two types are unions rather than locations: NSAllApplicationsDirectory and
 * NSAllLibrariesDirectory. NSItemReplacementDirectory is NOT answered, because Apple's answer is a NEW
 * temporary directory per call - an allocation, not a location.
 *
 * `expandTilde` READS AS IT IS NAMED: YES answers the user-domain directory EXPANDED
 * (`/Users/<name>/Library`), NO answers it as `~/Library`. Both name the same directory.
 */
extern NSArray *NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory directory,
							   NSSearchPathDomainMask domainMask,
							   BOOL expandTilde);

/* "Methods for working with paths" — Apple's category name and its home. */
@interface NSString (NSStringPathExtensions)

- (NSString *)lastPathComponent;
- (NSString *)pathExtension;
- (NSString *)stringByDeletingLastPathComponent;
- (NSString *)stringByDeletingPathExtension;
- (NSString *)stringByAppendingPathComponent:(NSString *)component;
- (nullable NSArray *)pathComponents;
- (NSString *)stringByStandardizingPath;
- (BOOL)isAbsolutePath;
- (NSString *)absolutePath;

+ (NSString *)pathWithComponents:(NSArray *)components;
- (NSArray *)stringsByAppendingPaths:(NSArray *)paths;
- (const char *)fileSystemRepresentation;
- (BOOL)getFileSystemRepresentation:(char *)buffer maxLength:(NSUInteger)maxLength;
- (NSString *)stringByExpandingTildeInPath;
- (NSString *)stringByAbbreviatingWithTildeInPath;
- (NSString *)stringByResolvingSymlinksInPath;
- (NSComparisonResult)localizedStandardCompare:(NSString *)string NS_AVAILABLE_MAC(10_6);
- (NSUInteger)completePathIntoString:(NSString * _Nullable * _Nullable)outputName
		       caseSensitive:(BOOL)flag
		    matchesIntoArray:(NSArray * _Nullable * _Nullable)outputArray
			 filterTypes:(nullable NSArray *)filterTypes;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSPATHUTILITIES_H */
