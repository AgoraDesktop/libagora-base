/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptWhoseTests.h — the comparison protocol, and (in the scripting slice) the whose-test family.
 *
 * APPLE DECLARES TWO CATEGORIES ON NSObject IN THIS HEADER, and they are here for the same reason: they are the
 * COMPARISON LANGUAGE a predicate-shaped test speaks, and the scripting system adopted them before NSPredicate
 * existed. `NSComparisonMethods` is the comparison vocabulary (`-isEqualTo:`, `-isLessThan:`, `-isLike:` and the
 * rest); `NSScriptingComparisonMethods` is its scripting spelling (`-scriptingBeginsWith:`, …), which coerces
 * strings and numbers rather than requiring both sides to be the same class.
 *
 * THEY ARE INFORMAL PROTOCOLS ON THE ROOT CLASS, so every object answers them — that is the point: an
 * `NSWhoseSpecifier` can compare two objects it was handed without knowing their classes. The implementations are
 * `NSComparisonMethods.m`, and they are real: `compare:` when the receiver has one, string wildcards for `-isLike:`,
 * and containment for `-doesContain:`.
 */

#ifndef FOUNDATION_NSSCRIPTWHOSETESTS_H
#define FOUNDATION_NSSCRIPTWHOSETESTS_H

#import <Foundation/NSObject.h>

@class NSString;
@class NSArray;
@class NSDictionary;

NS_ASSUME_NONNULL_BEGIN

@interface NSObject (NSComparisonMethods)

- (BOOL)isEqualTo:(nullable id)object;
- (BOOL)isNotEqualTo:(nullable id)object;
- (BOOL)isLessThan:(nullable id)object;
- (BOOL)isLessThanOrEqualTo:(nullable id)object;
- (BOOL)isGreaterThan:(nullable id)object;
- (BOOL)isGreaterThanOrEqualTo:(nullable id)object;
- (BOOL)isLike:(NSString *)object;
- (BOOL)isCaseInsensitiveLike:(NSString *)object;
- (BOOL)doesContain:(id)object;

@end

@interface NSObject (NSScriptingComparisonMethods)

- (BOOL)scriptingIsEqualTo:(nullable id)object;
- (BOOL)scriptingIsNotEqualTo:(nullable id)object;
- (BOOL)scriptingIsLessThan:(nullable id)object;
- (BOOL)scriptingIsLessThanOrEqualTo:(nullable id)object;
- (BOOL)scriptingIsGreaterThan:(nullable id)object;
- (BOOL)scriptingIsGreaterThanOrEqualTo:(nullable id)object;
- (BOOL)scriptingBeginsWith:(NSString *)object;
- (BOOL)scriptingEndsWith:(NSString *)object;
- (BOOL)scriptingContains:(NSString *)object;

@end

/* ---- THE WHOSE-TEST TREE -------------------------------------------------------------------------------------- */

typedef NS_ENUM(NSUInteger, NSTestComparisonOperation) {
	NSEqualToComparison = 0,
	NSLessThanOrEqualToComparison = 1,
	NSLessThanComparison = 2,
	NSGreaterThanOrEqualToComparison = 3,
	NSGreaterThanComparison = 4,
	NSBeginsWithComparison = 5,
	NSEndsWithComparison = 6,
	NSContainsComparison = 7
};

@class NSScriptObjectSpecifier;

/* A QUESTION ABOUT A VALUE. `-isTrue` evaluates it; the base class answers NO, which is the only answer that cannot
 * turn a missing test into a match. */
@interface NSScriptWhoseTest : NSObject
- (BOOL)isTrue;
@end

@interface NSSpecifierTest : NSScriptWhoseTest
{
@private
	NSScriptObjectSpecifier *_objectSpecifier;
	NSTestComparisonOperation _comparisonOperator;
	id _testObject;
}
- (instancetype)initWithObjectSpecifier:(nullable NSScriptObjectSpecifier *)objectSpecifier
		     comparisonOperator:(NSTestComparisonOperation)comparisonOperator
			     testObject:(nullable id)testObject;
@end

@interface NSLogicalTest : NSScriptWhoseTest
{
@private
	NSInteger _logicalType;		/* 0 = and, 1 = or, 2 = not */
	NSArray *_subtests;
}
- (instancetype)initAndTestWithTests:(NSArray *)subtests;
- (instancetype)initOrTestWithTests:(NSArray *)subtests;
- (instancetype)initNotTestWithTest:(NSScriptWhoseTest *)subtest;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTWHOSETESTS_H */
