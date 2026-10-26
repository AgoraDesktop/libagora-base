/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSExtensionItem.h — the extension's VALUE (10.10). W4a wrote the value, its host and the protocol in one header; W7
 * split them into Apple's three names: this file has NSExtensionItem, NSExtensionContext.h has the host side, and
 * NSExtensionRequestHandling.h has the protocol an extension implements.
 *
 * AN EXTENSION IS A SECOND PROCESS this system does not launch, so what ships here is the VALUED half: a copyable,
 * securely-codable four-part value.
 */
#ifndef FOUNDATION_NSEXTENSIONITEM_H
#define FOUNDATION_NSEXTENSIONITEM_H

#import <Foundation/NSObject.h>
#import <Foundation/NSCoding.h>

@class NSArray;
@class NSAttributedString;
@class NSDictionary;

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

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSEXTENSIONITEM_H */
