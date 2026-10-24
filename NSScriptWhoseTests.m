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

@implementation NSScriptWhoseTest

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

- (instancetype)initWithType:(NSInteger)type tests:(NSArray *)subtests
{
	self = [super init];
	if (self != nil) {
		_logicalType = type;
		_subtests = [subtests copy];
	}
	return self;
}

- (instancetype)initAndTestWithTests:(NSArray *)subtests
{
	return [self initWithType:0 tests:subtests];
}

- (instancetype)initOrTestWithTests:(NSArray *)subtests
{
	return [self initWithType:1 tests:subtests];
}

- (instancetype)initNotTestWithTest:(NSScriptWhoseTest *)subtest
{
	return [self initWithType:2 tests:[NSArray arrayWithObject:subtest]];
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
