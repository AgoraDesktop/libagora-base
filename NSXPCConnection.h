/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSXPCConnection.h — W5: THE XPC FAMILY, DECLARED AND REFUSED BY NAME.
 *
 * XPC is a Mach-service, a listener, a connection and a proxy — and this system has none of them: no launchd services,
 * no Mach ports (NSMachPort.h records the same absence), no serialisation of a proxy across a boundary. Every
 * constructor answers nil with a FOUNDATION-REFUSE line naming the door, and every other door refuses too rather than
 * pretending to hold state for an object that cannot be made. The classes and both protocols exist because a ported
 * caller names them, and the refusal is the contract (COCOA-10.11-SURFACE-PLAN.md §4.3's "refused" disposition).
 *
 * (Apple splits the four classes over three headers; the split is W7's organisation pass, and the facts are the same.)
 */
#ifndef FOUNDATION_NSXPCCONNECTION_H
#define FOUNDATION_NSXPCCONNECTION_H

#import <Foundation/NSObject.h>
#include <sys/types.h>		/* uid_t / gid_t */

@class NSArray;
@class NSDictionary;
@class NSError;
@class NSString;
@class NSXPCConnection;
@class NSXPCInterface;
@class NSXPCListener;
@class NSXPCListenerEndpoint;

NS_ASSUME_NONNULL_BEGIN

/* Apple's one option constant. */
typedef NS_OPTIONS(NSUInteger, NSXPCConnectionOptions) {
	NSXPCConnectionPrivileged = (1UL << 12)
};

@protocol NSXPCProxyCreating <NSObject>
- (id)remoteObjectProxy;
- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *error))handler;
@end

@protocol NSXPCListenerDelegate <NSObject>
@optional
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection;
@end

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSXPCConnection : NSObject <NSXPCProxyCreating>
- (instancetype)initWithServiceName:(NSString *)serviceName;
- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options;
- (instancetype)initWithListenerEndpoint:(NSXPCListenerEndpoint *)endpoint;

@property (nullable, readonly, copy) NSString *serviceName;
@property (nullable, readwrite, strong) NSXPCInterface *remoteObjectInterface;
@property (nullable, readwrite, strong) id exportedObject;
@property (nullable, readwrite, strong) NSXPCInterface *exportedInterface;
@property (readonly) int processIdentifier;
@property (readonly) uid_t effectiveUserIdentifier;
@property (readonly) gid_t effectiveGroupIdentifier;
@property (readonly) int auditSessionIdentifier;
@property (nullable, readonly, strong) NSXPCListenerEndpoint *endpoint;

- (void)resume;
- (void)suspend;
- (void)invalidate;
@end

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSXPCInterface : NSObject
{
@private
	Protocol *_protocol;
}
+ (instancetype)interfaceWithProtocol:(Protocol *)protocol;
@property (assign) Protocol *protocol;
- (NSArray *)classesForSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (void)setClasses:(NSArray *)classes forSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (NSXPCInterface *)interfaceForSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
- (void)setInterface:(NSXPCInterface *)iface forSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply;
@end

/* ZERO DOORS, AND STILL A CLASS: a ported program names the type even if nothing it does with one can work here. */
NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSXPCListenerEndpoint : NSObject
@end

NS_CLASS_AVAILABLE_MAC(10_8)
@interface NSXPCListener : NSObject
{
@private
	NSString *_serviceName;
	id<NSXPCListenerDelegate> _delegate;
}
+ (NSXPCListener *)anonymousListener;
+ (NSXPCListener *)serviceListener;
- (instancetype)initWithMachServiceName:(NSString *)name NS_DESIGNATED_INITIALIZER;
@property (nullable, assign) id<NSXPCListenerDelegate> delegate;
@property (readonly) NSXPCListenerEndpoint *endpoint;
- (void)resume;
- (void)suspend;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSXPCCONNECTION_H */
