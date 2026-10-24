/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <Foundation/NSAppleEventManager.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSThread.h>
#include <pthread.h>

static NSString *const FNCurrentEventKey = @"NSAppleEventManagerCurrentEvent";
static NSString *const FNCurrentReplyKey = @"NSAppleEventManagerCurrentReply";
static NSAppleEventManager *fn_apple_event_manager = nil;
static pthread_mutex_t fn_apple_event_manager_lock = PTHREAD_MUTEX_INITIALIZER;

@implementation NSAppleEventManager

+ (NSAppleEventManager *)sharedAppleEventManager
{
	pthread_mutex_lock(&fn_apple_event_manager_lock);
	if (fn_apple_event_manager == nil) {
		fn_apple_event_manager = [[NSAppleEventManager alloc] init];
	}
	pthread_mutex_unlock(&fn_apple_event_manager_lock);
	return fn_apple_event_manager;
}

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_handlers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_handlers release];
	[super dealloc];
}

static NSNumber *fn_handler_key(AEEventClass eventClass, AEEventID eventID)
{
	return [NSNumber numberWithUnsignedLongLong:((unsigned long long)eventClass << 32) | eventID];
}

- (void)setEventHandler:(id)handler
	    andSelector:(SEL)handleEventSelector
	  forEventClass:(AEEventClass)eventClass
	     andEventID:(AEEventID)eventID
{
	NSNumber *key = fn_handler_key(eventClass, eventID);

	if (handler == nil || handleEventSelector == NULL) {
		[_handlers removeObjectForKey:key];
		return;
	}
	[_handlers setObject:[NSArray arrayWithObjects:handler,
			      [NSString stringWithUTF8String:sel_getName(handleEventSelector)], nil]
		      forKey:key];
}

- (void)removeEventHandlerForEventClass:(AEEventClass)eventClass andEventID:(AEEventID)eventID
{
	[_handlers removeObjectForKey:fn_handler_key(eventClass, eventID)];
}

- (NSAppleEventDescriptor *)currentAppleEvent
{
	return [[[NSThread currentThread] threadDictionary] objectForKey:FNCurrentEventKey];
}

- (NSAppleEventDescriptor *)currentReplyAppleEvent
{
	return [[[NSThread currentThread] threadDictionary] objectForKey:FNCurrentReplyKey];
}

/* THE REGISTRY IS REAL AND THE EVENT IS NOT. A raw AppleEvent is a Carbon structure this library has no transport to
 * receive, so there is no descriptor to hand the handler; the handler is still CALLED, with nil/ nil, which is the
 * honest answer for "an event arrived, but its body cannot be represented". A handler that answers is a successful
 * dispatch; no handler is `errAEEventNotHandled`. */
- (OSStatus)dispatchRawAppleEvent:(const void *)appleEvent
		   withRawReply:(void *)appleEventReply
		   handlerRefCon:(void *)handlerRefCon
{
	NSEnumerator *values;
	NSArray *entry;

	(void)appleEvent;
	(void)appleEventReply;
	(void)handlerRefCon;
	values = [_handlers objectEnumerator];
	while ((entry = [values nextObject]) != nil) {
		id handler = [entry objectAtIndex:0];
		SEL selector = sel_registerName([[entry objectAtIndex:1] UTF8String]);

		if ([handler respondsToSelector:selector]) {
			typedef void (*fn_handler)(id, SEL, NSAppleEventDescriptor *, NSAppleEventDescriptor *);
			fn_handler call = (fn_handler)[handler methodForSelector:selector];

			call(handler, selector, nil, nil);
			return 0;
		}
	}
	return -1708;		/* errAEEventNotHandled */
}

- (AESuspensionID)suspendCurrentAppleEvent
{
	return NULL;		/* nothing to suspend without a transport */
}

- (NSAppleEventDescriptor *)appleEventForSuspensionID:(AESuspensionID)suspensionID
{
	(void)suspensionID;
	return nil;
}

- (NSAppleEventDescriptor *)replyAppleEventForSuspensionID:(AESuspensionID)suspensionID
{
	(void)suspensionID;
	return nil;
}

- (void)setCurrentAppleEventAndReplyEventWithSuspensionID:(AESuspensionID)suspensionID
{
	(void)suspensionID;
}

- (void)resumeWithSuspensionID:(AESuspensionID)suspensionID
{
	(void)suspensionID;
}

@end
