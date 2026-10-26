/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptWhoseTests.m — the test tree behind `whose` clauses.
 */
#import <Foundation/NSScriptWhoseTests.h>
#import <Foundation/NSScriptObjectSpecifiers.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>
#import <Foundation/NSCoder.h>

@implementation NSScriptWhoseTest

/* THE BASE HAS NO STATE OF ITS OWN, so its coder pair is the designated funnel and nothing else: a subclass calls
 * -super here and then writes what IT holds, which is why both doors exist on a class with no fields. */
- (instancetype)initWithCoder:(NSCoder *)coder
{
	(void)coder;
	return [super init];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	(void)coder;
}

- (BOOL)isTrue
{
	return NO;
}

@end

@implementation NSSpecifierTest

- (instancetype)initWithObjectSpecifier:(NSScriptObjectSpecifier *)objectSpecifier
		     comparisonOperator:(NSTestComparisonOperation)comparisonOperator
			     testObject:(id)testObject
{
	self = [super init];
	if (self != nil) {
		_objectSpecifier = [objectSpecifier retain];
		_comparisonOperator = comparisonOperator;
		_testObject = [testObject retain];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self != nil) {
		_objectSpecifier = [[coder decodeObjectForKey:@"NSObjectSpecifier"] retain];
		_comparisonOperator = (NSTestComparisonOperation)
			[coder decodeIntegerForKey:@"NSComparisonOperator"];
		_testObject = [[coder decodeObjectForKey:@"NSTestObject"] retain];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	[coder encodeObject:_objectSpecifier forKey:@"NSObjectSpecifier"];
	[coder encodeInteger:(NSInteger)_comparisonOperator forKey:@"NSComparisonOperator"];
	[coder encodeObject:_testObject forKey:@"NSTestObject"];
}

- (void)dealloc
{
	[_objectSpecifier release];
	[_testObject release];
	[super dealloc];
}

- (BOOL)isTrue
{
	id evaluated = [_objectSpecifier objectsByEvaluatingSpecifier];
	id value = evaluated;

	if ([evaluated isKindOfClass:[NSArray class]]) {
		value = [evaluated count] > 0 ? [evaluated objectAtIndex:0] : nil;
	}
	switch (_comparisonOperator) {
	case NSEqualToComparison:
		return [value isEqualTo:_testObject];
	case NSLessThanOrEqualToComparison:
		return [value isLessThanOrEqualTo:_testObject];
	case NSLessThanComparison:
		return [value isLessThan:_testObject];
	case NSGreaterThanOrEqualToComparison:
		return [value isGreaterThanOrEqualTo:_testObject];
	case NSGreaterThanComparison:
		return [value isGreaterThan:_testObject];
	case NSBeginsWithComparison:
		return [value scriptingBeginsWith:[_testObject description]];
	case NSEndsWithComparison:
		return [value scriptingEndsWith:[_testObject description]];
	case NSContainsComparison:
		return [value scriptingContains:[_testObject description]];
	}
	return NO;
}

@end

@implementation NSLogicalTest

/* THE STORAGE, AS A METHOD, because the three DESIGNATED constructors below each establish it and a designated
 * initializer may not chain to another one on `self` (FOUNDATION-10.11-PLAN.md §4.15). */
- (void)fnSetLogicalType:(NSInteger)type tests:(NSArray *)subtests
{
	_logicalType = type;
	_subtests = [subtests copy];
}

/* A CONVENIENCE door (Apple marks the three specialisations, not this one), so it starts from `-init`. */
- (instancetype)initWithType:(NSInteger)type tests:(NSArray *)subtests
{
	self = [self init];
	if (self != nil) {
		[self fnSetLogicalType:type tests:subtests];
	}
	return self;
}

/* THE THREE DESIGNATED DOORS: super, then the storage. Each names its own logical type, which is what the class is. */
- (instancetype)initAndTestWithTests:(NSArray *)subtests
{
	self = [super init];
	if (self != nil) {
		[self fnSetLogicalType:0 tests:subtests];
	}
	return self;
}

- (instancetype)initOrTestWithTests:(NSArray *)subtests
{
	self = [super init];
	if (self != nil) {
		[self fnSetLogicalType:1 tests:subtests];
	}
	return self;
}

- (instancetype)initNotTestWithTest:(NSScriptWhoseTest *)subtest
{
	self = [super init];
	if (self != nil) {
		[self fnSetLogicalType:2 tests:[NSArray arrayWithObject:subtest]];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
	self = [super initWithCoder:coder];
	if (self != nil) {
		_logicalType = [coder decodeIntegerForKey:@"NSLogicalType"];
		_subtests = [[coder decodeObjectForKey:@"NSSubtests"] copy];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
	[super encodeWithCoder:coder];
	[coder encodeInteger:_logicalType forKey:@"NSLogicalType"];
	[coder encodeObject:_subtests forKey:@"NSSubtests"];
}

- (void)dealloc
{
	[_subtests release];
	[super dealloc];
}

- (BOOL)isTrue
{
	NSUInteger i;

	switch (_logicalType) {
	case 0:
		for (i = 0; i < [_subtests count]; i++) {
			if (![[_subtests objectAtIndex:i] isTrue]) {
				return NO;
			}
		}
		return YES;
	case 1:
		for (i = 0; i < [_subtests count]; i++) {
			if ([[_subtests objectAtIndex:i] isTrue]) {
				return YES;
			}
		}
		return NO;
	case 2:
		return ![[_subtests objectAtIndex:0] isTrue];
	}
	return NO;
}

@end
