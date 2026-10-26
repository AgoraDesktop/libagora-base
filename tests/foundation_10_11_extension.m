/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * foundation_10_11_extension.m — THE EXTENSION VALUE, ITS HOST, ITEMS BY TYPE, AND AN ACCESS INTENT (10.8–10.10).
 *
 * The extension PROCESS does not exist here, so what is measured is the half that can be: the item's four copied
 * values and its secure archive, the context's refusal-by-name with its handlers still answered, item loading through
 * registered handlers (item, file), and the intent's URL and kind.
 */
#import <Foundation/Foundation.h>
#import <Foundation/NSExtensionItem.h>
#import <Foundation/NSExtensionContext.h>
#import <Foundation/NSExtensionRequestHandling.h>
#import <Foundation/NSItemProvider.h>

#include <stdio.h>

static int g_pass, g_fail;

static void check(int ok, const char *what)
{
	if (ok) { g_pass++; return; }
	g_fail++;
	fprintf(stderr, "FAIL: %s\n", what);
}

@interface RequestHandler : NSObject <NSExtensionRequestHandling>
@end
@implementation RequestHandler
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context { (void)context; }
@end

int main(void)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	/* ---- NSExtensionItem: four values, a copy, and a secure archive ---- */
	{
		NSExtensionItem *item = [[[NSExtensionItem alloc] init] autorelease];
		NSAttributedString *title = [[[NSAttributedString alloc] initWithString:@"title"] autorelease];
		NSAttributedString *text = [[[NSAttributedString alloc] initWithString:@"body"] autorelease];
		NSMutableDictionary *userInfo = [[[NSMutableDictionary alloc] init] autorelease];
		NSData *archive;
		NSExtensionItem *restored;
		NSExtensionItem *copied;

		[userInfo setObject:@"v" forKey:@"k"];
		[item setAttributedTitle:title];
		[item setAttributedContentText:text];
		[item setAttachments:[NSArray arrayWithObject:@"attachment"]];
		[item setUserInfo:userInfo];
		[userInfo setObject:@"changed" forKey:@"k"];
		check([[[item userInfo] objectForKey:@"k"] isEqualToString:@"v"],
		      "userInfo is COPIED, so a later edit by the caller does not reach the item");
		copied = [[item copy] autorelease];
		check(copied != item && [[copied attributedTitle] isEqual:[item attributedTitle]] &&
		      [[copied attachments] isEqual:[item attachments]], "a copy carries the same values");
		check([NSExtensionItem supportsSecureCoding], "the item supports secure coding");
		archive = [NSKeyedArchiver archivedDataWithRootObject:item];
		restored = [NSKeyedUnarchiver unarchiveObjectWithData:archive];
		check([restored isKindOfClass:[NSExtensionItem class]] &&
		      [[[restored attributedTitle] string] isEqualToString:@"title"] &&
		      [[[restored attributedContentText] string] isEqualToString:@"body"] &&
		      [[restored attachments] count] == 1, "and round-trips through the secure archive");
	}

	/* ---- NSExtensionContext: no extension behind it, so the requests refuse and answer NO ---- */
	{
		NSExtensionContext *context = [[[NSExtensionContext alloc] init] autorelease];
		__block int completed = -1;
		__block int opened = -1;
		RequestHandler *handler = [[[RequestHandler alloc] init] autorelease];

		check([context inputItems] != nil && [[context inputItems] count] == 0, "a bare context has no input items");
		[context completeRequestReturningItems:nil completionHandler:^(BOOL expired) {
			completed = expired ? 1 : 0;
		}];
		check(completed == 0, "completing a request answers the handler with NO");
		[context openURL:[NSURL URLWithString:@"http://example/"] completionHandler:^(BOOL success) {
			opened = success ? 1 : 0;
		}];
		check(opened == 0, "opening a URL answers the handler with NO");
		[context cancelRequestWithError:[NSError errorWithDomain:@"x" code:1 userInfo:nil]];
		check([handler conformsToProtocol:@protocol(NSExtensionRequestHandling)],
		      "the request-handling protocol is adoptable");
	}

	/* ---- NSItemProvider: item and file loading by type identifier ---- */
	{
		NSString *type = @"public.plain-text";
		NSString *item = @"provided";
		NSItemProvider *provider = [[[NSItemProvider alloc] initWithItem:(id<NSSecureCoding>)item
								  typeIdentifier:type] autorelease];
		NSString *file = @"/tmp/agora-item-provider.txt";
		NSItemProvider *fileProvider;
		NSArray *identifiers;
		__block id loaded = nil;
		__block NSError *loadError = nil;
		__block id fileLoaded = nil;
		__block NSError *missingError = nil;

		check([provider hasItemConformingToTypeIdentifier:type], "a registered type identifier conforms");
		check(![provider hasItemConformingToTypeIdentifier:@"public.image"], "an unregistered one does not");
		identifiers = [provider registeredTypeIdentifiers];
		check([identifiers count] == 1 && [[identifiers objectAtIndex:0] isEqualToString:type],
		      "the registered identifiers are listed");
		[provider loadItemForTypeIdentifier:type options:nil completionHandler:^(id loadedItem, NSError *error) {
			loaded = [loadedItem retain];
			loadError = [error retain];
		}];
		check([loaded isEqual:item] && loadError == nil, "loading the item answers it with no error");
		[loaded release];
		[loadError release];

		[[@"file-body" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:file atomically:NO];
		fileProvider = [[[NSItemProvider alloc] initWithContentsOfURL:[NSURL fileURLWithPath:file]] autorelease];
		check([fileProvider hasItemConformingToTypeIdentifier:@"public.data"], "a file provider registers public.data");
		[fileProvider loadItemForTypeIdentifier:@"public.data" options:nil completionHandler:^(id loadedItem, NSError *error) {
			(void)error;
			fileLoaded = [loadedItem retain];
		}];
		check(fileLoaded != nil && [[[[NSString alloc] initWithData:fileLoaded
								  encoding:NSUTF8StringEncoding] autorelease]
					     isEqualToString:@"file-body"], "and loads the file's bytes");
		[fileLoaded release];
		[fileProvider loadItemForTypeIdentifier:@"public.image" options:nil completionHandler:^(id loadedItem, NSError *error) {
			(void)loadedItem;
			missingError = [error retain];
		}];
		check(missingError != nil, "an unregistered type answers an error");
		[missingError release];
		[[NSFileManager defaultManager] removeItemAtPath:file error:NULL];
	}

	/* ---- NSFileAccessIntent: a URL and a kind ---- */
	{
		NSURL *url = [NSURL fileURLWithPath:@"/tmp/agora-intent"];
		NSFileAccessIntent *reading = [NSFileAccessIntent readingIntentWithURL:url
									      options:NSFileCoordinatorReadingWithoutChanges];
		NSFileAccessIntent *writing = [NSFileAccessIntent writingIntentWithURL:url
									      options:NSFileCoordinatorWritingForReplacing];

		check(reading != nil && [[reading URL] isEqual:url], "a reading intent carries its URL");
		check(writing != nil && [[writing URL] isEqual:url] && writing != reading,
		      "a writing intent is its own value with the same URL");
	}

	printf("foundation_10_11_extension: %d of %d cases passed, %d failed\n", g_pass, g_pass + g_fail, g_fail);
	[pool release];
	return g_fail == 0 ? 0 : 1;
}
