/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * The design is in the two headers. What is here is the copied-value accessors, the action, and an in-process centre
 * whose delivery refuses by name after asking its delegate.
 */
#import <Foundation/NSUserNotification.h>
#import <Foundation/NSUserNotificationCenter.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSAttributedString.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDateComponents.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimeZone.h>

#include <stdio.h>

/* A COPIED-OR-RETAINED SLOT, once: every object door below goes through it. */
static void fn_adopt(id *slot, id value, BOOL copy)
{
	id adopted = copy ? [value copy] : [value retain];

	[*slot release];
	*slot = adopted;
}

@implementation NSUserNotification

- (instancetype)init
{
	self = [super init];
	return self;
}

- (void)dealloc
{
	[_title release]; [_subtitle release]; [_informativeText release]; [_actionButtonTitle release];
	[_userInfo release]; [_deliveryDate release]; [_deliveryTimeZone release];
	[_deliveryRepeatInterval release]; [_actualDeliveryDate release]; [_soundName release];
	[_otherButtonTitle release]; [_identifier release]; [_contentImage release];
	[_responsePlaceholder release]; [_response release]; [_additionalActions release];
	[_additionalActivationAction release];
	[super dealloc];
}

- (NSString *)title { return _title; }
- (void)setTitle:(NSString *)v { fn_adopt((id *)&_title, v, YES); }
- (NSString *)subtitle { return _subtitle; }
- (void)setSubtitle:(NSString *)v { fn_adopt((id *)&_subtitle, v, YES); }
- (NSString *)informativeText { return _informativeText; }
- (void)setInformativeText:(NSString *)v { fn_adopt((id *)&_informativeText, v, YES); }
- (NSString *)actionButtonTitle { return _actionButtonTitle; }
- (void)setActionButtonTitle:(NSString *)v { fn_adopt((id *)&_actionButtonTitle, v, YES); }
- (NSDictionary *)userInfo { return _userInfo; }
- (void)setUserInfo:(NSDictionary *)v { fn_adopt((id *)&_userInfo, v, YES); }
- (NSDate *)deliveryDate { return _deliveryDate; }
- (void)setDeliveryDate:(NSDate *)v { fn_adopt((id *)&_deliveryDate, v, YES); }
- (NSTimeZone *)deliveryTimeZone { return _deliveryTimeZone; }
- (void)setDeliveryTimeZone:(NSTimeZone *)v { fn_adopt((id *)&_deliveryTimeZone, v, YES); }
- (NSDateComponents *)deliveryRepeatInterval { return _deliveryRepeatInterval; }
- (void)setDeliveryRepeatInterval:(NSDateComponents *)v { fn_adopt((id *)&_deliveryRepeatInterval, v, YES); }
- (NSDate *)actualDeliveryDate { return _actualDeliveryDate; }
- (BOOL)isPresented { return _presented; }
- (BOOL)isRemote { return _remote; }
- (NSString *)soundName { return _soundName; }
- (void)setSoundName:(NSString *)v { fn_adopt((id *)&_soundName, v, YES); }
- (NSUserNotificationActivationType)activationType { return _activationType; }
- (NSString *)otherButtonTitle { return _otherButtonTitle; }
- (void)setOtherButtonTitle:(NSString *)v { fn_adopt((id *)&_otherButtonTitle, v, YES); }
- (NSString *)identifier { return _identifier; }
- (void)setIdentifier:(NSString *)v { fn_adopt((id *)&_identifier, v, YES); }
- (id)contentImage { return _contentImage; }
- (void)setContentImage:(id)v { fn_adopt(&_contentImage, v, NO); }
- (NSString *)responsePlaceholder { return _responsePlaceholder; }
- (void)setResponsePlaceholder:(NSString *)v { fn_adopt((id *)&_responsePlaceholder, v, YES); }
- (NSAttributedString *)response { return _response; }
- (id)additionalActions { return _additionalActions; }
- (void)setAdditionalActions:(id)v { fn_adopt(&_additionalActions, v, YES); }
- (NSUserNotificationAction *)additionalActivationAction { return _additionalActivationAction; }
- (BOOL)hasActionButton { return _hasActionButton; }
- (void)setHasActionButton:(BOOL)v { _hasActionButton = v; }
- (BOOL)hasReplyButton { return _hasReplyButton; }
- (void)setHasReplyButton:(BOOL)v { _hasReplyButton = v; }

- (id)copyWithZone:(NSZone *)zone
{
	NSUserNotification *copy = [[[self class] allocWithZone:zone] init];

	copy->_title = [_title copy];
	copy->_subtitle = [_subtitle copy];
	copy->_informativeText = [_informativeText copy];
	copy->_actionButtonTitle = [_actionButtonTitle copy];
	copy->_userInfo = [_userInfo copy];
	copy->_deliveryDate = [_deliveryDate copy];
	copy->_deliveryTimeZone = [_deliveryTimeZone copy];
	copy->_deliveryRepeatInterval = [_deliveryRepeatInterval copy];
	copy->_actualDeliveryDate = [_actualDeliveryDate copy];
	copy->_presented = _presented;
	copy->_remote = _remote;
	copy->_soundName = [_soundName copy];
	copy->_activationType = _activationType;
	copy->_otherButtonTitle = [_otherButtonTitle copy];
	copy->_identifier = [_identifier copy];
	copy->_contentImage = [_contentImage retain];
	copy->_responsePlaceholder = [_responsePlaceholder copy];
	copy->_response = [_response copy];
	copy->_additionalActions = [_additionalActions copy];
	copy->_additionalActivationAction = [_additionalActivationAction copy];
	copy->_hasActionButton = _hasActionButton;
	copy->_hasReplyButton = _hasReplyButton;
	return copy;
}

@end

@implementation NSUserNotificationAction

+ (instancetype)actionWithIdentifier:(NSString *)identifier title:(NSString *)title
{
	NSUserNotificationAction *action = [[[self alloc] init] autorelease];

	action->_identifier = [identifier copy];
	action->_title = [title copy];
	return action;
}

- (void)dealloc
{
	[_identifier release];
	[_title release];
	[super dealloc];
}

- (NSString *)identifier { return _identifier; }
- (NSString *)title { return _title; }

- (id)copyWithZone:(NSZone *)zone
{
	NSUserNotificationAction *copy = [[[self class] allocWithZone:zone] init];

	copy->_identifier = [_identifier copy];
	copy->_title = [_title copy];
	return copy;
}

@end

@implementation NSUserNotificationCenter

static NSUserNotificationCenter *fn_center = nil;

+ (NSUserNotificationCenter *)defaultUserNotificationCenter
{
	if (fn_center == nil) {
		fn_center = [[NSUserNotificationCenter alloc] init];
	}
	return fn_center;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_scheduled = [[NSMutableArray alloc] init];
		_delivered = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_scheduled release];
	[_delivered release];
	[super dealloc];
}

- (id<NSUserNotificationCenterDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSUserNotificationCenterDelegate>)delegate { _delegate = delegate; }

- (void)scheduleNotification:(NSUserNotification *)notification
{
	if (notification != nil) {
		[_scheduled addObject:notification];
	}
}

- (void)removeScheduledNotification:(NSUserNotification *)notification
{
	[_scheduled removeObjectIdenticalTo:notification];
}

- (void)deliverNotification:(NSUserNotification *)notification
{
	BOOL present = YES;

	/* THE DELEGATE IS CONSULTED, and its answer is reported — then delivery refuses anyway, because there is nothing
	 * to present with. Saying so is the difference between a refusal and a silent success. */
	if (_delegate != nil &&
	    [_delegate respondsToSelector:@selector(userNotificationCenter:shouldPresentNotification:)]) {
		present = [_delegate userNotificationCenter:self shouldPresentNotification:notification];
	}
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSUserNotificationCenter deliverNotification:] cannot present a notification "
			"(delegate would%s present it); this system has no notification daemon\\n",
		present ? "" : " not");
}

- (void)removeDeliveredNotification:(NSUserNotification *)notification
{
	[_delivered removeObjectIdenticalTo:notification];
}

- (void)removeAllDeliveredNotifications
{
	[_delivered removeAllObjects];
}

- (NSArray *)scheduledNotifications { return [[_scheduled copy] autorelease]; }
- (NSArray *)deliveredNotifications { return [[_delivered copy] autorelease]; }

- (void)setScheduledNotifications:(NSArray *)notifications
{
	NSMutableArray *replacement = [[NSMutableArray alloc] init];

	if (notifications != nil) {
		[replacement addObjectsFromArray:notifications];
	}
	[_scheduled release];
	_scheduled = replacement;
}

@end
