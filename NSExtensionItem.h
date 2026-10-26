/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSExtensionItem.h — W4a: the extension's value, its host, and the door an extension implements.
 *
 * AN EXTENSION IS A SECOND PROCESS this system does not launch, so what ships here is the VALUED half: NSExtensionItem
 * is a copyable, securely-codable four-part value, and NSExtensionContext is the host side of a conversation with no
 * extension on the other end — its three request doors REFUSE BY NAME and still answer their completion handlers with
 * NO, which is what a caller checks. `NSExtensionRequestHandling` is the protocol an extension implements; there is
 * nothing here to call it.
 *
 * (Apple splits these into NSExtensionItem.h / NSExtensionContext.h / NSExtensionRequestHandling.h; the split is
 * W7's organisation pass, and the facts are the same either way.)
 */
#ifndef FOUNDATION_NSEXTENSIONITEM_H
#define FOUNDATION_NSEXTENSIONITEM_H

#import <Foundation/NSObject.h>
#import <Foundation/NSCoding.h>

@class NSArray;
@class NSAttributedString;
@class NSDictionary;
@class NSError;
@class NSString;
@class NSURL;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSExtensionItem : NSObject <NSCopying, NSSecureCoding>
{
@private
	NSAttributedString *_attributedTitle;
	NSAttributedString *_attributedContentText;
	NSArray *_attachments;
	NSDictionary *_userInfo;
}
@property (nullable, copy) NSAttributedString *attributedTitle;
@property (nullable, copy) NSAttributedString *attributedContentText;
@property (nullable, copy) NSArray *attachments;
@property (nullable, copy) NSDictionary *userInfo;
@end

/* THE HOST SIDE. There is no extension process, so a request is refused by name; the completion handlers are still
 * called, because a caller that waits for one must not wait forever. */
NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSExtensionContext : NSObject
{
@private
	NSArray *_inputItems;
}
@property (readonly, copy) NSArray *inputItems;
- (void)completeRequestReturningItems:(nullable NSArray *)items
		    completionHandler:(nullable void (^)(BOOL expired))completionHandler;
- (void)cancelRequestWithError:(NSError *)error;
- (void)openURL:(NSURL *)URL completionHandler:(nullable void (^)(BOOL success))completionHandler;
@end

/* WHAT AN EXTENSION IMPLEMENTS. Declared for the shape; nothing here sends it. */
@protocol NSExtensionRequestHandling <NSObject>
- (void)beginRequestWithExtensionContext:(NSExtensionContext *)context;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSEXTENSIONITEM_H */
