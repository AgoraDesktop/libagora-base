/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSUserNotificationCenter.h — W4b: THE CENTRE IS AN IN-PROCESS LEDGER, AND DELIVERY IS REFUSED BY NAME.
 *
 * This system has no notification daemon: nothing draws a banner, nothing plays a sound, nothing waits for a click. So
 * the centre keeps the state a caller can observe — what is scheduled, what was delivered, who the delegate is — and
 * `-deliverNotification:` REFUSES BY NAME after consulting the delegate's `-userNotificationCenter:shouldPresent…`,
 * because "did you present it" is the one question this class must not answer with a silent yes. A scheduled
 * notification stays scheduled; a delivered one is not recorded as delivered, since nothing was.
 */
#ifndef FOUNDATION_NSUSERNOTIFICATIONCENTER_H
#define FOUNDATION_NSUSERNOTIFICATIONCENTER_H

#import <Foundation/NSObject.h>

@class NSArray;
@class NSMutableArray;
@class NSUserNotification;
@class NSUserNotificationCenter;

NS_ASSUME_NONNULL_BEGIN

@protocol NSUserNotificationCenterDelegate <NSObject>
@optional
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
	  didDeliverNotification:(NSUserNotification *)notification;
- (void)userNotificationCenter:(NSUserNotificationCenter *)center
	 didActivateNotification:(NSUserNotification *)notification;
- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
	shouldPresentNotification:(NSUserNotification *)notification;
@end

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSUserNotificationCenter : NSObject
{
@private
	id<NSUserNotificationCenterDelegate> _delegate;	/* ASSIGN: Apple's delegate is not retained */
	NSMutableArray *_scheduled;
	NSMutableArray *_delivered;
}
+ (NSUserNotificationCenter *)defaultUserNotificationCenter;
@property (nullable, assign) id<NSUserNotificationCenterDelegate> delegate;
- (void)scheduleNotification:(NSUserNotification *)notification;
- (void)removeScheduledNotification:(NSUserNotification *)notification;
- (void)deliverNotification:(NSUserNotification *)notification;
- (void)removeDeliveredNotification:(NSUserNotification *)notification;
- (void)removeAllDeliveredNotifications;
@property (readonly, copy) NSArray *scheduledNotifications;
@property (readonly, copy) NSArray *deliveredNotifications;
- (void)setScheduledNotifications:(nullable NSArray *)notifications;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSUSERNOTIFICATIONCENTER_H */
