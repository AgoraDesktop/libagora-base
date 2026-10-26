/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The types are in NSExtensionItem.h / NSExtensionContext.h / NSExtensionRequestHandling.h (W7 split Apple's three
 * names). An item is four copied values and a secure archive of them; a context is a host with no extension behind it,
 * so its requests refuse by name and answer their handlers with NO.
 */
#import <Foundation/NSExtensionItem.h>
#import <Foundation/NSExtensionContext.h>
#import <Foundation/NSExtensionRequestHandling.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSData.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSCoder.h>

#include <stdio.h>

@implementation NSExtensionItem

- (void)dealloc
{
	[_attributedTitle release];
	[_attributedContentText release];
	[_attachments release];
	[_userInfo release];
	[super dealloc];
}

- (NSAttributedString *)attributedTitle { return _attributedTitle; }
- (NSAttributedString *)attributedContentText { return _attributedContentText; }
- (NSArray *)attachments { return _attachments; }
- (NSDictionary *)userInfo { return _userInfo; }

- (void)setAttributedTitle:(NSAttributedString *)value
{
	NSAttributedString *copied = [value copy];
	[_attributedTitle release];
	_attributedTitle = copied;
}
- (void)setAttributedContentText:(NSAttributedString *)value
{
	NSAttributedString *copied = [value copy];
	[_attributedContentText release];
	_attributedContentText = copied;
}
- (void)setAttachments:(NSArray *)value
{
	NSArray *copied = [value copy];
	[_attachments release];
	_attachments = copied;
}
- (void)setUserInfo:(NSDictionary *)value
{
	NSDictionary *copied = [value copy];
	[_userInfo release];
	_userInfo = copied;
}

- (id)copyWithZone:(NSZone *)zone
{
	NSExtensionItem *copy = [[[self class] allocWithZone:zone] init];

	copy->_attributedTitle = [_attributedTitle copy];
	copy->_attributedContentText = [_attributedContentText copy];
	copy->_attachments = [_attachments copy];
	copy->_userInfo = [_userInfo copy];
	return copy;
}

+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_attributedTitle forKey:@"attributedTitle"];
	[coder encodeObject:_attributedContentText forKey:@"attributedContentText"];
	[coder encodeObject:_attachments forKey:@"attachments"];
	[coder encodeObject:_userInfo forKey:@"userInfo"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super init];
	if (self != nil) {
		_attributedTitle = [[coder decodeObjectOfClass:[NSAttributedString class]
						       forKey:@"attributedTitle"] retain];
		_attributedContentText = [[coder decodeObjectOfClass:[NSAttributedString class]
							     forKey:@"attributedContentText"] retain];
		_attachments = [[coder decodeObjectOfClasses:
			[NSSet setWithObjects:[NSArray class], [NSAttributedString class], [NSString class],
						[NSData class], nil]
						      forKey:@"attachments"] retain];
		_userInfo = [[coder decodeObjectOfClasses:
			[NSSet setWithObjects:[NSDictionary class], [NSString class], [NSArray class], nil]
						   forKey:@"userInfo"] retain];
	}
	return self;
}

@end

@implementation NSExtensionContext

- (void)dealloc
{
	[_inputItems release];
	[super dealloc];
}

- (NSArray *)inputItems
{
	return _inputItems != nil ? _inputItems : [NSArray array];
}

- (void)completeRequestReturningItems:(NSArray *)items completionHandler:(void (^)(BOOL))completionHandler
{
	(void)items;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSExtensionContext completeRequestReturningItems:completionHandler:] has no "
			"extension process to complete a request with\n");
	if (completionHandler != nil) {
		completionHandler(NO);
	}
}

- (void)cancelRequestWithError:(NSError *)error
{
	(void)error;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSExtensionContext cancelRequestWithError:] has no extension process whose "
			"request could be cancelled\n");
}

- (void)openURL:(NSURL *)URL completionHandler:(void (^)(BOOL))completionHandler
{
	(void)URL;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSExtensionContext openURL:completionHandler:] has no extension host to "
			"open a URL in\n");
	if (completionHandler != nil) {
		completionHandler(NO);
	}
}

@end
