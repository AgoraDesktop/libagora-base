/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The design is in NSItemProvider.h. The store is a type identifier -> handler dictionary plus a preview handler; the
 * file form registers `public.data` and hands back the file's bytes.
 */
#import <Foundation/NSItemProvider.h>
#import <Foundation/FoundationErrors.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <Block.h>

@implementation NSItemProvider

- (instancetype)initWithItem:(id<NSSecureCoding>)item typeIdentifier:(NSString *)typeIdentifier
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_handlers = [[NSMutableDictionary alloc] init];
	_order = [[NSMutableArray alloc] init];
	if (typeIdentifier != nil) {
		id captured = [(id)item retain];
		NSString *type = [typeIdentifier copy];

		[self registerItemForTypeIdentifier:type loadHandler:^(NSItemProviderCompletionHandler completionHandler,
								      Class expectedValueClass,
								      NSDictionary *options) {
			(void)expectedValueClass;
			(void)options;
			completionHandler(captured, nil);
		}];
		[captured release];	/* the handler's Block_copy retained it */
		[type release];
	}
	return self;
}

- (instancetype)initWithContentsOfURL:(NSURL *)fileURL
{
	NSString *type = @"public.data";

	self = [self initWithItem:nil typeIdentifier:nil];
	if (self == nil) {
		return nil;
	}
	{
		NSURL *captured = [fileURL retain];

		[self registerItemForTypeIdentifier:type loadHandler:^(NSItemProviderCompletionHandler completionHandler,
								      Class expectedValueClass,
								      NSDictionary *options) {
			NSData *data;

			(void)expectedValueClass;
			(void)options;
			data = [NSData dataWithContentsOfURL:captured];
			completionHandler(data, data != nil ? nil : [NSError errorWithDomain:NSCocoaErrorDomain
										      code:260	/* NSFileReadNoSuchFileError */
										  userInfo:nil]);
		}];
		[captured release];
	}
	return self;
}

- (void)dealloc
{
	[_handlers release];
	[_order release];
	if (_previewHandler != NULL) {
		Block_release(_previewHandler);
	}
	[super dealloc];
}

- (void)registerItemForTypeIdentifier:(NSString *)typeIdentifier loadHandler:(NSItemProviderLoadHandler)loadHandler
{
	if (typeIdentifier == nil || loadHandler == nil) {
		return;
	}
	if ([_handlers objectForKey:typeIdentifier] == nil) {
		[_order addObject:typeIdentifier];
	}
	[_handlers setObject:Block_copy(loadHandler) forKey:typeIdentifier];
}

- (BOOL)hasItemConformingToTypeIdentifier:(NSString *)typeIdentifier
{
	return [_handlers objectForKey:typeIdentifier] != nil;
}

- (void)loadItemForTypeIdentifier:(NSString *)typeIdentifier
			  options:(NSDictionary *)options
		completionHandler:(NSItemProviderCompletionHandler)completionHandler
{
	NSItemProviderLoadHandler handler = [_handlers objectForKey:typeIdentifier];

	if (handler == nil) {
		if (completionHandler != nil) {
			completionHandler(nil, [NSError errorWithDomain:NSCocoaErrorDomain
								   code:260
							       userInfo:nil]);
		}
		return;
	}
	handler(completionHandler, Nil, options);
}

- (void)setPreviewImageHandler:(NSItemProviderLoadHandler)handler
{
	if (_previewHandler != NULL) {
		Block_release(_previewHandler);
	}
	_previewHandler = (handler != nil ? Block_copy(handler) : NULL);
}

- (NSItemProviderLoadHandler)previewImageHandler
{
	return _previewHandler;
}

- (void)loadPreviewImageWithOptions:(NSDictionary *)options
		  completionHandler:(NSItemProviderCompletionHandler)completionHandler
{
	if (_previewHandler == NULL) {
		if (completionHandler != nil) {
			completionHandler(nil, nil);
		}
		return;
	}
	_previewHandler(completionHandler, Nil, options);
}

- (NSArray *)registeredTypeIdentifiers
{
	return [[_order copy] autorelease];
}

@end
