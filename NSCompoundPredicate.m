/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSCompoundPredicate.m — AND, OR, NOT. Short-circuiting is explicit rather than left to the compiler, because
 * a predicate's right-hand side may be the expensive half (a MATCHES over a long string) and the order the
 * caller wrote is the order they meant.
 */

#import <Foundation/NSCompoundPredicate.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSString.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSException.h>

@implementation NSCompoundPredicate

- (id)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray *)subpredicates
{
	self = [super init];
	if (self != nil) {
		if (type == NSNotPredicateType && [subpredicates count] != 1) {
			[self release];
			[NSException raise:NSInvalidArgumentException
			            format:@"NSCompoundPredicate: NOT takes exactly one subpredicate, not %lu",
			                   (unsigned long)[subpredicates count]];
			return nil;
		}
		_type = type;
		_subpredicates = [subpredicates copy];
	}
	return self;
}

- (void)dealloc { [_subpredicates release]; [super dealloc]; }

- (NSCompoundPredicateType)compoundPredicateType { return _type; }
- (NSArray *)subpredicates { return _subpredicates; }

+ (NSPredicate *)andPredicateWithSubpredicates:(NSArray *)subpredicates
{
	return [[[self alloc] initWithType:NSAndPredicateType subpredicates:subpredicates] autorelease];
}

+ (NSPredicate *)orPredicateWithSubpredicates:(NSArray *)subpredicates
{
	return [[[self alloc] initWithType:NSOrPredicateType subpredicates:subpredicates] autorelease];
}

+ (NSPredicate *)notPredicateWithSubpredicate:(NSPredicate *)predicate
{
	NSMutableArray *one = [[NSMutableArray alloc] init];
	NSPredicate *result;

	[one addObject:predicate];
	result = [[self alloc] initWithType:NSNotPredicateType subpredicates:one];
	[one release];
	return [result autorelease];
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return [[NSCompoundPredicate allocWithZone:zone] initWithType:_type subpredicates:_subpredicates];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[coder encodeInteger:(NSInteger)_type forKey:@"NSType"];
	[coder encodeObject:_subpredicates forKey:@"NSSubpredicates"];
}

- (id)initWithCoder:(NSCoder *)coder
{
	return [self initWithType:(NSCompoundPredicateType)[coder decodeIntegerForKey:@"NSType"]
	            subpredicates:[coder decodeObjectForKey:@"NSSubpredicates"]];
}

- (BOOL)evaluateWithObject:(id)object { return [self evaluateWithObject:object substitutionVariables:nil]; }

- (BOOL)evaluateWithObject:(id)object substitutionVariables:(NSDictionary *)bindings
{
	NSUInteger i, n = [_subpredicates count];

	if (_type == NSNotPredicateType) {
		if (n == 0) { return YES; }
		return ![[_subpredicates objectAtIndex:0] evaluateWithObject:object substitutionVariables:bindings];
	}
	for (i = 0; i < n; i++) {
		BOOL v = [[_subpredicates objectAtIndex:i] evaluateWithObject:object substitutionVariables:bindings];
		if (_type == NSAndPredicateType) {
			if (!v) { return NO; }
		} else {
			if (v) { return YES; }
		}
	}
	return (_type == NSAndPredicateType);
}

- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)variables
{
	NSMutableArray *substituted = [[NSMutableArray alloc] init];
	NSUInteger i, n = [_subpredicates count];
	NSPredicate *result;

	for (i = 0; i < n; i++) {
		[substituted addObject:[[_subpredicates objectAtIndex:i] predicateWithSubstitutionVariables:variables]];
	}
	result = [[NSCompoundPredicate alloc] initWithType:_type subpredicates:substituted];
	[substituted release];
	return [result autorelease];
}

- (NSString *)predicateFormat
{
	NSUInteger i, n = [_subpredicates count];

	if (_type == NSNotPredicateType) {
		if (n == 0) { return @"NOT (TRUEPREDICATE)"; }
		return [NSString stringWithFormat:@"NOT (%@)", [[_subpredicates objectAtIndex:0] predicateFormat]];
	}
	if (n == 0) { return (_type == NSAndPredicateType) ? @"TRUEPREDICATE" : @"FALSEPREDICATE"; }

	{
		NSMutableString *out = [[NSMutableString alloc] init];
		NSString *joiner = (_type == NSAndPredicateType) ? @" AND " : @" OR ";
		[out appendString:@"("];
		for (i = 0; i < n; i++) {
			if (i > 0) { [out appendString:joiner]; }
			[out appendString:[[_subpredicates objectAtIndex:i] predicateFormat]];
		}
		[out appendString:@")"];
		return [out autorelease];
	}
}

@end
