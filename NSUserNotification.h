/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSUserNotification.h — W4b: the notification as a VALUE, and the action a user can choose.
 *
 * A notification here is a mutable value with `NSCopying`: twenty-two doors that state what the notification says and
 * how it is delivered, each copied on the way in. Nothing PRESENTS it — that is the centre's business
 * (NSUserNotificationCenter.h), and this system has no notification daemon.
 *
 * `contentImage` is `id` on purpose: Apple's type is AppKit's NSImage, and Foundation does not import AppKit. The value
 * is carried unchanged, which is what the seam can promise.
 */
#ifndef FOUNDATION_NSUSERNOTIFICATION_H
#define FOUNDATION_NSUSERNOTIFICATION_H

#import <Foundation/NSObject.h>

@class NSAttributedString;
@class NSDate;
@class NSDateComponents;
@class NSDictionary;
@class NSString;
@class NSTimeZone;
@class NSUserNotificationAction;

NS_ASSUME_NONNULL_BEGIN

/* APPLE'S VALUES: 0-4, with the two later cases carrying their eras. */
typedef NS_ENUM(NSInteger, NSUserNotificationActivationType) {
	NSUserNotificationActivationTypeNone = 0,
	NSUserNotificationActivationTypeContentsClicked = 1,
	NSUserNotificationActivationTypeActionButtonClicked = 2,
	NSUserNotificationActivationTypeReplied NS_AVAILABLE_MAC(10_9) = 3,
	NSUserNotificationActivationTypeAdditionalActionClicked NS_AVAILABLE_MAC(10_10) = 4
};

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSUserNotification : NSObject <NSCopying>
{
@private
	NSString *_title;
	NSString *_subtitle;
	NSString *_informativeText;
	NSString *_actionButtonTitle;
	NSDictionary *_userInfo;
	NSDate *_deliveryDate;
	NSTimeZone *_deliveryTimeZone;
	NSDateComponents *_deliveryRepeatInterval;
	NSDate *_actualDeliveryDate;
	BOOL _presented;
	BOOL _remote;
	NSString *_soundName;
	NSUserNotificationActivationType _activationType;
	NSString *_otherButtonTitle;
	NSString *_identifier;
	id _contentImage;
	NSString *_responsePlaceholder;
	NSAttributedString *_response;
	id _additionalActions;
	id _additionalActivationAction;
	BOOL _hasActionButton;
	BOOL _hasReplyButton;
}
- (instancetype)init NS_DESIGNATED_INITIALIZER;

@property (nullable, copy) NSString *title;
@property (nullable, copy) NSString *subtitle;
@property (nullable, copy) NSString *informativeText;
@property (nullable, copy) NSString *actionButtonTitle;
@property (nullable, copy) NSDictionary *userInfo;
@property (nullable, copy) NSDate *deliveryDate;
@property (nullable, copy) NSTimeZone *deliveryTimeZone;
@property (nullable, copy) NSDateComponents *deliveryRepeatInterval;
@property (readonly, nullable, copy) NSDate *actualDeliveryDate;
@property (readonly, getter=isPresented) BOOL presented;
@property (readonly, getter=isRemote) BOOL remote;
@property (nullable, copy) NSString *soundName;
@property (readonly) NSUserNotificationActivationType activationType;
@property (nullable, copy) NSString *otherButtonTitle;
@property (nullable, copy) NSString *identifier NS_AVAILABLE_MAC(10_9);
@property (nullable, retain) id contentImage NS_AVAILABLE_MAC(10_9);
@property (nullable, copy) NSString *responsePlaceholder NS_AVAILABLE_MAC(10_9);
@property (readonly, nullable, copy) NSAttributedString *response NS_AVAILABLE_MAC(10_9);
@property (nullable, copy) id additionalActions NS_AVAILABLE_MAC(10_10);
@property (readonly, nullable, copy) NSUserNotificationAction *additionalActivationAction NS_AVAILABLE_MAC(10_10);
@property (getter=hasActionButton) BOOL hasActionButton;
@property (getter=hasReplyButton) BOOL hasReplyButton NS_AVAILABLE_MAC(10_9);
@end

/* An ACTION is an identifier and a title, made by the one factory. */
NS_CLASS_AVAILABLE_MAC(10_10)
@interface NSUserNotificationAction : NSObject <NSCopying>
{
@private
	NSString *_identifier;
	NSString *_title;
}
+ (instancetype)actionWithIdentifier:(nullable NSString *)identifier title:(nullable NSString *)title;
@property (nullable, readonly, copy) NSString *identifier;
@property (nullable, readonly, copy) NSString *title;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSUSERNOTIFICATION_H */
