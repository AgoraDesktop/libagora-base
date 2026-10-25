/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * NSURLQueryItem.m — the pair, its copy, and its archive.
 *
 * Two strings and a handful of protocols; the interesting part is `-isEqual:`, because a query item is a VALUE and
 * `NSURLComponents -queryItems` compares arrays of them. Apple's rule for the pair is structural: same name string and
 * same value string (or both nil), and nothing else. A class that compared by pointer would make two parsed components
 * unequal to the same query, which is exactly how this class is used.
 */

#import <Foundation/NSURLQueryItem.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSArray.h>

@implementation NSURLQueryItem

- (instancetype)init
{
	return [self initWithName:@"" value:nil];
}

- (instancetype)initWithName:(NSString *)name value:(nullable NSString *)value
{
	self = [super init];
	if (self != nil) {
		/* COPIED, not retained: a pair is a value, and a caller that hands in a mutable string and then edits it
		 * must not change the item it already handed over. */
		_name = [name copy];
		_value = [value copy];
	}
	return self;
}

+ (instancetype)queryItemWithName:(NSString *)name value:(nullable NSString *)value
{
	return [[[self alloc] initWithName:name value:value] autorelease];
}

- (void)dealloc
{
	[_name release];
	[_value release];
	[super dealloc];
}

- (NSString *)name { return _name; }
- (NSString *)value { return _value; }

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;	/* immutable by construction: the same object answers every copy */
	return [self retain];
}

- (BOOL)isEqual:(id)other
{
	NSURLQueryItem *item;

	if (other == self) {
		return YES;
	}
	if (![other isKindOfClass:[NSURLQueryItem class]]) {
		return NO;
	}
	item = (NSURLQueryItem *)other;
	if (![_name isEqualToString:item->_name]) {
		return NO;
	}
	if (_value == nil || item->_value == nil) {
		return _value == item->_value;
	}
	return [_value isEqualToString:item->_value];
}

- (NSUInteger)hash
{
	/* Both strings, because `?a=1` and `?b=1` must not collide more than they must; the value's hash is folded in
	 * only when there is one, so a nameless-value pair is distinct from a pair whose value is the empty string. */
	return [_name hash] ^ (_value == nil ? 0 : [_value hash] * 31);
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<NSURLQueryItem %@=%@>", _name, _value == nil ? @"(nil)" : _value];
}

/* NSSecureCoding: TWO STRINGS AND AN ALLOW-LIST. The keys are Apple's own spellings for the pair, which is what makes
 * an archive written here legible to anything that knows the type. */
+ (BOOL)supportsSecureCoding { return YES; }

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeObject:_name forKey:@"NS.name"];
	[coder encodeObject:_value forKey:@"NS.value"];
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	NSString *name;
	NSString *value;

	name = [coder decodeObjectOfClass:[NSString class] forKey:@"NS.name"];
	if (name == nil) {
		[self release];
		return nil;
	}
	value = [coder decodeObjectOfClass:[NSString class] forKey:@"NS.value"];
	return [self initWithName:name value:value];
}

@end
