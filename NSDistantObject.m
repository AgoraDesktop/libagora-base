/*
 * NSDistantObject.m
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * See NSDistantObject.h for the boundary (objects in, objects out), the two shapes and why a proxy is not
 * archivable here. What is here is the forwarding, split once and used by the two doors that must agree about it.
 */

#import <Foundation/NSDistantObject.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#include <objc/runtime.h>
#include <stdio.h>		/* stdio, for the refusal lines' fprintf */	/* protocol_getMethodDescription: the proxy's own protocol doors */

/* THE CONNECTION'S OWN DOOR, DECLARED HERE AND DEFINED IN NSConnection.m: a proxy sends its invocation and waits,
 * and the waiting belongs to the connection because the run loop does. */
@interface NSConnection (FNProxy)
- (nullable id)fnSendInvocation:(NSInvocation *)invocation error:(NSString *_Nullable *_Nullable)outError;
- (BOOL)fnIsService;
@end

/* NSProxy IS A ROOT CLASS WITH NO INITIALIZER (`objc_root_class`, and no `-init`), so clang's designated-initializer
 * analysis has no super door to point at: `-initWithCoder:` is designated because Apple marks it so, the three
 * constructors here initialize this class's own fields, and there is no superclass state to install. The diagnostic is
 * suppressed for this file alone, with this comment as its reason rather than a blanket silence. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

@implementation NSDistantObject

- (instancetype)initWithLocal:(id)object connection:(NSConnection *)connection
{
	/* NO `[super init]`: THIS LIBRARY'S `NSProxy` IS A ROOT CLASS WITH NO `-init`, which §62.55 measured the hard
	 * way. `+alloc` is the whole of construction for a proxy. */
	_target = [object retain];
	_connection = [connection retain];	/* RETAINED: a proxy without its transport is a proxy that cannot call */
	return self;
}

/* THE TWO CLASS-SIDE FACTORIES (§63.19): the initializers above, with Apple's own spelling and the house's
 * AUTORELEASED answer for a name that begins with neither `alloc`, `new` nor `copy`. They delegate rather than
 * restating the construction, so a proxy built either way is the same object. */
+ (id)proxyWithLocal:(id)object connection:(NSConnection *)connection
{
	return [[[self alloc] initWithLocal:object connection:connection] autorelease];
}

+ (id)proxyWithTarget:(id)target connection:(NSConnection *)connection
{
	return [[[self alloc] initWithTarget:target connection:connection] autorelease];
}

- (instancetype)initWithTarget:(id)target connection:(NSConnection *)connection
{
	_target = [target retain];		/* nil means "the far side's root object" */
	_connection = [connection retain];
	return self;
}

/* THE CODER DOORS REFUSE BY NAME. A proxy stands for an object at the other end of a connection, and what an archive
 * would need to carry is the connection - which the per-process name server cannot rebuild (§62.54). Answering nil and
 * raising is the honest reply; an archive that decoded into a proxy with no transport would be an object that looks
 * usable and fails at its first call. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
	(void)coder;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSDistantObject initWithCoder:] cannot rebuild a proxy; a connection "
			"cannot be re-established from an archive\n");
	[self release];
	return nil;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	(void)coder;
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSDistantObject encodeWithCoder:] cannot write a proxy; a connection "
			"cannot be carried in an archive\n");
	[NSException raise:NSInvalidArgumentException
		    format:@"NSDistantObject: a proxy cannot be archived - there is no connection to rebuild from the "
			   "bytes"];
}

/* A PROXY'S CODER CLASS IS THE PROXY'S, not the target's: NSProxy is a root class and does not inherit NSObject's
 * `-classForCoder`, so without this door an archiver asking a proxy would forward the question to the far-side object
 * and get an answer about another process. Answering from the dynamic class is what lets the archiver name this class and
 * reach the coder doors above, which refuse with a reason. */
- (Class)classForCoder
{
	return [self class];
}

- (NSConnection *)connectionForProxy { return _connection; }

- (void)setProtocolForProxy:(Protocol *)aProtocol { _protocol = aProtocol; }
/* `-protocolForProxy` stood here and is GONE (§63.59): Apple declares the setter only, and every reader
 * of the protocol in this file (the two doors below) takes `_protocol` directly. */

/* THE BOUNDARY, IN ONE PLACE. `index` 0 and 1 are the receiver and the selector; every argument after them must be
 * an OBJECT, because that is what the coder can carry — and a method that takes a number is REFUSED with its own
 * name in the message rather than sent with the number's bytes reinterpreted. */
- (BOOL)fnArgumentsAreObjects:(NSMethodSignature *)signature
{
	NSUInteger i;

	for (i = 2; i < [signature numberOfArguments]; i++) {
		const char *type = [signature getArgumentTypeAtIndex:i];

		if (type == NULL || type[0] != '@') {
			return NO;
		}
	}
	return YES;
}

- (BOOL)respondsToSelector:(SEL)selector
{
	if (_target != nil) {
		return [_target respondsToSelector:selector];
	}
	if (_protocol != nil) {
		return protocol_getMethodDescription(_protocol, selector, YES, YES).name != NULL ||
		       protocol_getMethodDescription(_protocol, selector, NO, YES).name != NULL;
	}
	return [super respondsToSelector:selector];	/* the proxy's own doors, and nothing else */
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
	if (_target != nil) {
		return [_target methodSignatureForSelector:selector];
	}
	if (_protocol != nil) {
		struct objc_method_description description =
			protocol_getMethodDescription(_protocol, selector, YES, YES);

		if (description.name == NULL) {
			description = protocol_getMethodDescription(_protocol, selector, NO, YES);
		}
		if (description.name == NULL) {
			return nil;	/* not in the protocol this proxy was declared to speak */
		}
		return [NSMethodSignature signatureWithObjCTypes:description.types];
	}
	return nil;
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
	SEL selector = [invocation selector];
	NSMethodSignature *signature = [invocation methodSignature];
	NSString *error = nil;
	id value;

	/* THE LOCAL SHAPE: the object is here, so the call is a call. */
	if (_target != nil) {
		[invocation invokeWithTarget:_target];
		return;
	}
	if (_connection == nil) {
		[NSException raise:NSInvalidArgumentException
			    format:@"this distant object has no connection to travel over"];
	}
	if (![self fnArgumentsAreObjects:signature]) {
		/* NAMED, WITH THE METHOD, because a caller who hit this has a real question: which method, and why. */
		[NSException raise:NSInvalidArgumentException
			    format:@"%@ can only be sent to a distant object with OBJECT arguments: this library's coder "
				   @"carries objects, and a method taking anything else has no wire format here",
				   NSStringFromSelector(selector)];
	}
	value = [_connection fnSendInvocation:invocation error:&error];
	if (error != nil) {
		[NSException raise:NSInvalidArgumentException format:@"%@", error];
	}
	/* THE RESULT CROSSES AS AN OBJECT, and a method whose result is not one is refused by the same rule as its
	 * arguments — the connection's own check, reported here as the caller's exception. */
	if ([signature methodReturnLength] > 0) {
		[invocation setReturnValue:&value];
	}
}

- (void)dealloc
{
	[_target release];
	[_connection release];
	[super dealloc];
}

@end

#pragma clang diagnostic pop

