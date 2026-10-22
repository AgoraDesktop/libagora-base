/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */

/*
 * FNProtocolMethods.m — the methods a `Protocol` object answers.
 *
 * A protocol HERE IS A RUNTIME OBJECT, and Cocoa messages it: `-name` is what
 * `NSStringFromProtocol` is built on, and `-hash`/`-isEqual:` are what make a
 * protocol usable as a dictionary key - which is the use Apple's documentation
 * gives the `NSStringFromProtocol`/`NSProtocolFromString` pair.
 *
 * The runtime's `Protocol` class has no methods of its own: it roots at the
 * legacy `Object` class and exists so that a `struct objc_protocol` has an
 * isa.  GNUstep Base supplies these methods for this runtime; Agora has no
 * Base, so Foundation does.  They are a category rather than a class
 * implementation because the class object belongs to the runtime.
 */
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSString.h>

#import <objc/runtime.h>

@implementation Protocol (FNProtocolObject)

- (NSString *)name
{
	const char *name = protocol_getName(self);
	return name ? [NSString stringWithUTF8String:name] : nil;
}

- (NSString *)description
{
	return [self name];
}

/* djb2 over the name, the same shape Foundation's string hash uses: equal
 * protocols have equal names, so they must have equal hashes. */
- (NSUInteger)hash
{
	const char *name = protocol_getName(self);
	NSUInteger hash = 5381;
	if (name == NULL) {
		return 0;
	}
	while (*name != '\0') {
		hash = (hash * 33) ^ (unsigned char)*name++;
	}
	return hash;
}

- (BOOL)isEqual:(id)other
{
	Class protocolClass;
	Class c;

	if (other == self) {
		return YES;
	}
	if (other == nil) {
		return NO;
	}
	/* A Protocol object has no NSObject methods, so `-isKindOfClass:` cannot be
	 * asked of it: walk the class chain with the runtime instead. */
	protocolClass = objc_getClass("Protocol");
	for (c = object_getClass(other); c != Nil; c = class_getSuperclass(c)) {
		if (c == protocolClass) {
			NSString *mine = [self name];
			NSString *theirs = [(Protocol *)other name];
			if (mine == nil || theirs == nil) {
				return NO;
			}
			return [mine isEqualToString:theirs];
		}
	}
	return NO;
}

@end
