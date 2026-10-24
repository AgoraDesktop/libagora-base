/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAppleEventManager.h — the handler registry, and the refusal that is honest about the transport.
 *
 * The registry is real: a handler and selector are stored per (event class, event ID), and `-dispatchRawAppleEvent:`
 * finds and calls one. There is no AppleEvents transport, so nothing here can create a raw event to dispatch, and the
 * suspension doors answer as "there is nothing suspended".
 */
#ifndef FOUNDATION_NSAPPLEEVENTMANAGER_H
#define FOUNDATION_NSAPPLEEVENTMANAGER_H

#import <Foundation/NSObject.h>
#import <Foundation/NSAppleEventDescriptor.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct __AESuspensionID *AESuspensionID;

@interface NSAppleEventManager : NSObject
{
@private
	NSMutableDictionary *_handlers;
}

+ (NSAppleEventManager *)sharedAppleEventManager;

- (void)setEventHandler:(nullable id)handler
	    andSelector:(nullable SEL)handleEventSelector
	  forEventClass:(AEEventClass)eventClass
	     andEventID:(AEEventID)eventID;
- (void)removeEventHandlerForEventClass:(AEEventClass)eventClass andEventID:(AEEventID)eventID;

- (nullable NSAppleEventDescriptor *)currentAppleEvent;
- (nullable NSAppleEventDescriptor *)currentReplyAppleEvent;
- (OSStatus)dispatchRawAppleEvent:(const void *)appleEvent
		   withRawReply:(nullable void *)appleEventReply
		   handlerRefCon:(void *)handlerRefCon;

- (nullable AESuspensionID)suspendCurrentAppleEvent;
- (nullable NSAppleEventDescriptor *)appleEventForSuspensionID:(AESuspensionID)suspensionID;
- (nullable NSAppleEventDescriptor *)replyAppleEventForSuspensionID:(AESuspensionID)suspensionID;
- (void)setCurrentAppleEventAndReplyEventWithSuspensionID:(AESuspensionID)suspensionID;
- (void)resumeWithSuspensionID:(AESuspensionID)suspensionID;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSAPPLEEVENTMANAGER_H */
