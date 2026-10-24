/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSException.m — the throwable object.
 *
 * MANUAL OWNERSHIP.
 */

#import <Foundation/NSException.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSArray.h>
#import "FNCallStack.h"
#include <stdio.h>
#include <stdlib.h>
#include <objc/objc-exception.h>	/* the runtime's uncaught hook: the only code that KNOWS */	/* the handler lives in the thread dictionary */
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDictionary.h>
#include <objc/objc-exception.h>

NSString *const NSGenericException = @"NSGenericException";
NSString *const NSRangeException = @"NSRangeException";
NSString *const NSInvalidArgumentException = @"NSInvalidArgumentException";
NSString *const NSInternalInconsistencyException = @"NSInternalInconsistencyException";
/* Cocoa raises this when an allocation fails. Nothing here allocates large enough to fail in
 * practice; the name exists because a class that would raise it needs the spelling to match. */
NSString *const NSMallocException = @"NSMallocException";

/* **THE TWO NAMES `+load` BELOW NEEDS ARE DECLARED HERE AND DEFINED AT THE END OF THE FILE.** The handler and the
 * caller's slot live beside the runtime hook they belong to, which is the last thing in this translation unit —
 * and a load-time install is the only place that can run before any code does. A tentative definition for the
 * variable and a prototype for the function are what let it happen from here. */
static NSUncaughtExceptionHandler fn_uncaught_handler;
static void fn_default_uncaught_handler(id exception);

@implementation NSException

+ (void)load
{
	/* ONCE, AT LOAD, AND ONLY IF NOTHING ELSE HAS CLAIMED THE HOOK — see the note above the default handler. */
	if (fn_uncaught_handler == NULL) {
		NSSetUncaughtExceptionHandler(fn_default_uncaught_handler);
	}
}

NSExceptionName const NSDestinationInvalidException = @"NSDestinationInvalidException";
NSExceptionName const NSInconsistentArchiveException = @"NSInconsistentArchiveException";
NSExceptionName const NSInvalidArchiveOperationException = @"NSInvalidArchiveOperationException";
NSExceptionName const NSInvalidReceivePortException = @"NSInvalidReceivePortException";
NSExceptionName const NSInvalidSendPortException = @"NSInvalidSendPortException";
NSExceptionName const NSInvalidUnarchiveOperationException = @"NSInvalidUnarchiveOperationException";
NSExceptionName const NSInvocationOperationCancelledException = @"NSInvocationOperationCancelledException";
NSExceptionName const NSInvocationOperationVoidResultException = @"NSInvocationOperationVoidResultException";
NSExceptionName const NSObjectInaccessibleException = @"NSObjectInaccessibleException";
NSExceptionName const NSObjectNotAvailableException = @"NSObjectNotAvailableException";
NSExceptionName const NSOldStyleException = @"NSOldStyleException";
NSExceptionName const NSOperationNotSupportedForKeyException = @"NSOperationNotSupportedForKeyException";
NSExceptionName const NSPortReceiveException = @"NSPortReceiveException";
NSExceptionName const NSPortSendException = @"NSPortSendException";
NSExceptionName const NSPortTimeoutException = @"NSPortTimeoutException";
NSExceptionName const NSUndefinedKeyException = @"NSUndefinedKeyException";

NSExceptionName const NSCharacterConversionException = @"NSCharacterConversionException";
NSExceptionName const NSParseErrorException = @"NSParseErrorException";

/* THE STACK AT THE MOMENT OF THE ASK (10.5 addresses, 10.6 symbols). The exception does not carry one — Apple's
 * do not either — so these are the same walk NSThread answers, spelled as the exception's doors. */
- (NSArray *)callStackReturnAddresses
{
	return FNCallStackReturnAddresses();
}

- (NSArray *)callStackSymbols
{
	return FNCallStackSymbols();
}

+ (NSException *)exceptionWithName:(NSString *)name
			    reason:(NSString *)reason
			  userInfo:(NSDictionary *)userInfo
{
	return [[self alloc] initWithName:name reason:reason userInfo:userInfo];
}

- (id)initWithName:(NSString *)name
	    reason:(NSString *)reason
	  userInfo:(NSDictionary *)userInfo
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_name = [name copy];
	_reason = [reason copy];
	_userInfo = [userInfo copy];
	return self;
}

- (NSString *)name
{
	return _name;
}

- (NSString *)reason
{
	return _reason;
}

- (NSDictionary *)userInfo
{
	return _userInfo;
}

/* --- THE CODER DOORS (§62.91: they were missing, and the DO reply needs them) --------------------- */

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_name forKey:@"name"];
	[coder encodeObject:_reason forKey:@"reason"];
	[coder encodeObject:_userInfo forKey:@"userInfo"];
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
	id name = [coder decodeObjectForKey:@"name"];
	id reason = [coder decodeObjectForKey:@"reason"];
	id userInfo = [coder decodeObjectForKey:@"userInfo"];

	if (name == nil) {
		/* AN EXCEPTION WITHOUT A NAME IS NOT ONE — the initialiser refuses that — so an archive carrying none
		 * is refused here rather than handed on as an object every reader would trip over. */
		[self release];
		return nil;
	}
	return [self initWithName:name reason:reason userInfo:userInfo];
}

- (void)raise
{
	/*
	 * THE RUNTIME THROWS IT. objc_exception_throw is the entry point clang's
	 * @try/@catch lowering unwinds through, so a raised NSException is a real
	 * exception rather than a convention — and it does not return.
	 */
	objc_exception_throw(self);
}

+ (void)raise:(NSString *)name format:(NSString *)format, ...
{
	va_list args;

	va_start(args, format);
	[self raise:name format:format arguments:args];
	va_end(args);
}

+ (void)raise:(NSString *)name format:(NSString *)format arguments:(va_list)arguments
{
	va_list copy;
	NSException *exception;

	/* Same rule as the string method: consume a copy, so the caller's list stays
	 * valid for its own va_end. */
	va_copy(copy, arguments);
	exception = [[self alloc] initWithName:name
					reason:[NSString stringWithFormat:format arguments:copy]
				      userInfo:nil];
	va_end(copy);
	[exception raise];
}

- (NSString *)description
{
	if (_reason != nil) {
		return [NSString stringWithFormat:@"%@: %@", _name, _reason];
	}
	return _name;
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return [self retain];	/* +1: `copy` is an OWNED family (plan §15.2) — immutable */
}



@end

/*
 * THE ASSERTION HANDLER (W2d). The store is the THREAD's dictionary, which is why this family waited
 * for `-threadDictionary`: Apple files the key under NSThread's thread properties, and a handler that
 * was global would be one program-wide object where Cocoa gives every thread its own.
 */
NSString *NSAssertionHandlerKey = @"NSAssertionHandler";

@implementation NSAssertionHandler

+ (NSAssertionHandler *)currentHandler
{
	NSMutableDictionary *properties = [[NSThread currentThread] threadDictionary];
	NSAssertionHandler *handler = [properties objectForKey:NSAssertionHandlerKey];

	if (handler == nil) {
		handler = [[NSAssertionHandler alloc] init];
		[properties setObject:handler forKey:NSAssertionHandlerKey];
		/* THE DICTIONARY OWNS IT, and the caller does not — which is what makes this the
		 * per-thread singleton a program replaces through the same key. */
		[handler release];
	}
	return handler;
}

/*
 * THE DEFAULT HANDLER RAISES, and that is the whole contract: an assertion that fires is a failure,
 * not a line in a log. A program that wants the other thing replaces the handler in the thread
 * dictionary — which the probe does, and asserts that the replacement is the one consulted.
 *
 * THE MESSAGE'S SHAPE IS THIS LIBRARY'S (see NSException.h): Apple documents the exception's NAME and
 * that the description is carried, not the exact string.
 */
- (void)handleFailureInMethod:(SEL)selector object:(id)object file:(NSString *)fileName
		   lineNumber:(NSInteger)line description:(NSString *)format, ...
{
	va_list arguments;
	NSString *text;

	va_start(arguments, format);
	text = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);
	[NSException raise:NSInternalInconsistencyException
		    format:@"*** Assertion failure in -[%@ %@], %@:%d — %@",
			   (object != nil) ? (id)[object class] : (id)@"?",
			   NSStringFromSelector(selector), fileName, (int)line, text];
}

- (void)handleFailureInFunction:(NSString *)functionName file:(NSString *)fileName
		     lineNumber:(NSInteger)line description:(NSString *)format, ...
{
	va_list arguments;
	NSString *text;

	va_start(arguments, format);
	text = [[NSString alloc] initWithFormat:format arguments:arguments];
	va_end(arguments);
	[NSException raise:NSInternalInconsistencyException
		    format:@"*** Assertion failure in %@(), %@:%d — %@",
			   functionName, fileName, (int)line, text];
}

@end

/*
 * THE UNCAUGHT-EXCEPTION HANDLER (the gap §62.3 named). -raise calls objc_exception_throw, so an uncaught
 * exception never returns into Foundation and there is no place here that could NOTICE one - the runtime
 * notices, and libobjc exposes the hook for it (objc/objc-exception.h). Both of Apple's functions are here:
 * the setter installs into the runtime AND keeps its own copy, because the runtime's setter ANSWERS the
 * previous handler while having no getter, and Apple's getter must answer the CURRENT one.
 */
static NSUncaughtExceptionHandler fn_uncaught_handler = NULL;

/* **AND THE DEFAULT HANDLER, WHICH IS WHAT WAS MISSING.** An uncaught exception used to kill the process with NO
 * OUTPUT AT ALL — measured, and it cost real time in two units: a Foundation raise looked like a library crash, and
 * a probe that died mid-list printed nothing to say why. Apple prints the name and the reason before it terminates;
 * so does this now, and the message says WHICH, because "Foundation aborted" is not a diagnosis.
 *
 * IT IS INSTALLED AT LOAD AND ONLY IF THE CALLER HAS NOT SET ONE, so `NSSetUncaughtExceptionHandler` still wins
 * when it is used — the default must not be able to displace somebody else's handler. */
static void fn_default_uncaught_handler(id exception)
{
	const char *name = "an exception with no name";
	const char *reason = "no reason given";
	id n = nil, r = nil;

	if ([exception respondsToSelector:@selector(name)]) {
		n = [exception performSelector:@selector(name)];
	}
	if ([exception respondsToSelector:@selector(reason)]) {
		r = [exception performSelector:@selector(reason)];
	}
	if ([n isKindOfClass:[NSString class]]) {
		name = [(NSString *)n UTF8String];
	}
	if ([r isKindOfClass:[NSString class]]) {
		reason = [(NSString *)r UTF8String];
	}
	fprintf(stderr, "*** Terminating due to uncaught exception '%s', reason: '%s'\n", name, reason);
	abort();
}

NSUncaughtExceptionHandler NSGetUncaughtExceptionHandler(void)
{
	return fn_uncaught_handler;
}

void NSSetUncaughtExceptionHandler(NSUncaughtExceptionHandler handler)
{
	/* The two handler TYPES name the same call: the runtime's takes an `id`, Apple's an NSException *, and a
	 * handler written to Apple's signature is the one a caller hands over. */
	fn_uncaught_handler = handler;
	(void)objc_setUncaughtExceptionHandler((objc_uncaught_exception_handler)handler);
}
