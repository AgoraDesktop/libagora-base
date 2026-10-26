/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * W5: every door of the XPC family refuses by name. Each site carries its own FOUNDATION-REFUSE line so
 * tests/refusal_census.txt can count them per file — a helper with one line would hide the doors behind it.
 */
#import <Foundation/NSXPCConnection.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSError.h>
#import <Foundation/NSString.h>

#include <stdio.h>

static NSError *fn_xpc_error(void)
{
	return [NSError errorWithDomain:NSCocoaErrorDomain code:3328	/* NSFeatureUnsupportedError */
			       userInfo:nil];
}

@implementation NSXPCConnection

- (instancetype)initWithServiceName:(NSString *)serviceName
{
	(void)serviceName;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection initWithServiceName:] needs launchd's service lookup, "
			"which this system does not have\n");
	[self release];
	return nil;
}

- (instancetype)initWithMachServiceName:(NSString *)name options:(NSXPCConnectionOptions)options
{
	(void)name;
	(void)options;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection initWithMachServiceName:options:] needs Mach services, "
			"which this system does not have\n");
	[self release];
	return nil;
}

- (instancetype)initWithListenerEndpoint:(NSXPCListenerEndpoint *)endpoint
{
	(void)endpoint;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection initWithListenerEndpoint:] needs an XPC listener, which "
			"this system does not have\n");
	[self release];
	return nil;
}

- (NSString *)serviceName { return nil; }
- (NSXPCInterface *)remoteObjectInterface { return nil; }
- (id)exportedObject { return nil; }
- (NSXPCInterface *)exportedInterface { return nil; }
- (NSXPCListenerEndpoint *)endpoint { return nil; }
- (int)processIdentifier { return 0; }
- (uid_t)effectiveUserIdentifier { return 0; }
- (gid_t)effectiveGroupIdentifier { return 0; }
- (int)auditSessionIdentifier { return 0; }

- (void)setRemoteObjectInterface:(NSXPCInterface *)interface
{
	(void)interface;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection setRemoteObjectInterface:] has no connection to hold an "
			"interface\n");
}

- (void)setExportedObject:(id)object
{
	(void)object;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection setExportedObject:] has no connection to export an object "
			"over\n");
}

- (void)setExportedInterface:(NSXPCInterface *)interface
{
	(void)interface;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection setExportedInterface:] has no connection to hold an "
			"interface\n");
}

- (void)resume
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection resume] has no connection to resume\n");
}

- (void)suspend
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection suspend] has no connection to suspend\n");
}

- (void)invalidate
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection invalidate] has no connection to invalidate\n");
}

- (id)remoteObjectProxy
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection remoteObjectProxy] has no connection to proxy across\n");
	return nil;
}

- (id)remoteObjectProxyWithErrorHandler:(void (^)(NSError *))handler
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCConnection remoteObjectProxyWithErrorHandler:] has no connection to "
			"proxy across\n");
	if (handler != nil) {
		handler(fn_xpc_error());
	}
	return nil;
}

@end

@implementation NSXPCInterface

+ (instancetype)interfaceWithProtocol:(Protocol *)protocol
{
	(void)protocol;
	fprintf(stderr, "FOUNDATION-REFUSE: +[NSXPCInterface interfaceWithProtocol:] has no XPC boundary to describe\n");
	return nil;
}

- (Protocol *)protocol { return _protocol; }
- (void)setProtocol:(Protocol *)protocol { _protocol = protocol; }

- (NSArray *)classesForSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
	(void)selector; (void)arg; (void)ofReply;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCInterface classesForSelector:argumentIndex:ofReply:] has no boundary "
			"to describe\n");
	return nil;
}

- (void)setClasses:(NSArray *)classes forSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
	(void)classes; (void)selector; (void)arg; (void)ofReply;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCInterface setClasses:forSelector:argumentIndex:ofReply:] has no "
			"boundary to describe\n");
}

- (NSXPCInterface *)interfaceForSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
	(void)selector; (void)arg; (void)ofReply;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCInterface interfaceForSelector:argumentIndex:ofReply:] has no "
			"boundary to describe\n");
	return nil;
}

- (void)setInterface:(NSXPCInterface *)iface forSelector:(SEL)selector argumentIndex:(NSUInteger)arg ofReply:(BOOL)ofReply
{
	(void)iface; (void)selector; (void)arg; (void)ofReply;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCInterface setInterface:forSelector:argumentIndex:ofReply:] has no "
			"boundary to describe\n");
}

@end

@implementation NSXPCListenerEndpoint
@end

@implementation NSXPCListener

+ (NSXPCListener *)anonymousListener
{
	fprintf(stderr, "FOUNDATION-REFUSE: +[NSXPCListener anonymousListener] needs an XPC listener, which this system "
			"does not have\n");
	return nil;
}

+ (NSXPCListener *)serviceListener
{
	fprintf(stderr, "FOUNDATION-REFUSE: +[NSXPCListener serviceListener] needs launchd's service namespace, which "
			"this system does not have\n");
	return nil;
}

- (instancetype)initWithMachServiceName:(NSString *)name
{
	(void)name;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCListener initWithMachServiceName:] needs Mach services, which this "
			"system does not have\n");
	[self release];
	return nil;
}

- (id<NSXPCListenerDelegate>)delegate { return _delegate; }
- (void)setDelegate:(id<NSXPCListenerDelegate>)delegate { _delegate = delegate; }

- (NSXPCListenerEndpoint *)endpoint
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCListener endpoint] has no listener endpoint to hand out\n");
	return nil;
}

- (void)resume
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCListener resume] has no listener to resume\n");
}

- (void)suspend
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCListener suspend] has no listener to suspend\n");
}

- (void)invalidate
{
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSXPCListener invalidate] has no listener to invalidate\n");
}

@end
