/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSItemProvider.h — W4a: ITEMS BY TYPE IDENTIFIER, loaded through registered handlers.
 *
 * A provider is a dictionary from type identifier to a load handler, plus a preview-image handler. `hasItemConforming…`
 * answers whether a handler is registered for the exact identifier: this tree has no Uniform Type Identifier hierarchy,
 * so "conforms" here means "is registered", and the header says so rather than pretending to know that public.jpeg
 * conforms to public.image.
 *
 * **THE HANDLER RUNS ON THE THREAD THAT ASKED.** Apple dispatches it; this slice does not, because a load that is a
 * memory answer (the item, a file's data) has nothing to wait for, and a caller that needs another thread has one.
 *
 * The two block types are the SDK's (10.11's NSItemProvider.h uses `id <NSSecureCoding>`, not the later reading/writing
 * protocols).
 */
#ifndef FOUNDATION_NSITEMPROVIDER_H
#define FOUNDATION_NSITEMPROVIDER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSCoding.h>

@class NSArray;
@class NSData;
@class NSDictionary;
@class NSMutableArray;
@class NSMutableDictionary;
@class NSError;
@class NSString;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

typedef void (^NSItemProviderCompletionHandler)(id _Nullable item, NSError * _Nullable error);
typedef void (^NSItemProviderLoadHandler)(NSItemProviderCompletionHandler _Nullable completionHandler,
					  Class _Nullable expectedValueClass,
					  NSDictionary * _Nullable options);

NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSItemProvider : NSObject
{
@private
	NSMutableDictionary *_handlers;	/* type identifier -> NSItemProviderLoadHandler */
	NSMutableArray *_order;		/* the identifiers, in registration order */
	NSItemProviderLoadHandler _previewHandler;
}
- (instancetype)initWithItem:(nullable id<NSSecureCoding>)item
	      typeIdentifier:(nullable NSString *)typeIdentifier NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)fileURL;
- (void)registerItemForTypeIdentifier:(NSString *)typeIdentifier loadHandler:(NSItemProviderLoadHandler)loadHandler;
- (BOOL)hasItemConformingToTypeIdentifier:(NSString *)typeIdentifier;
- (void)loadItemForTypeIdentifier:(NSString *)typeIdentifier
			  options:(nullable NSDictionary *)options
		completionHandler:(nullable NSItemProviderCompletionHandler)completionHandler;
- (void)loadPreviewImageWithOptions:(nullable NSDictionary *)options
		  completionHandler:(nullable NSItemProviderCompletionHandler)completionHandler NS_AVAILABLE_MAC(10_10);
@property (nullable, copy) NSItemProviderLoadHandler previewImageHandler NS_AVAILABLE_MAC(10_10);
@property (readonly, copy) NSArray *registeredTypeIdentifiers;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSITEMPROVIDER_H */
