/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSComparisonPredicate — two expressions and an operator, which is the only leaf the format grammar ever
 * produces. The operator enum is Apple's numbering INCLUDING the 10.5 additions' deliberate 99
 * (`NSContainsPredicateOperatorType`), because a predicate archived on one side and decoded on the other
 * must agree about numbers.
 */

#ifndef FOUNDATION_NSCOMPARISONPREDICATE_H
#define FOUNDATION_NSCOMPARISONPREDICATE_H

#import <Foundation/NSPredicate.h>
#import <Foundation/NSExpression.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSUInteger NSComparisonPredicateModifier;
typedef NSUInteger NSPredicateOperatorType;

enum {
	NSLessThanPredicateOperatorType = 0,
	NSLessThanOrEqualToPredicateOperatorType,
	NSGreaterThanPredicateOperatorType,
	NSGreaterThanOrEqualToPredicateOperatorType,
	NSEqualToPredicateOperatorType,
	NSNotEqualToPredicateOperatorType,
	NSMatchesPredicateOperatorType,
	NSLikePredicateOperatorType,
	NSBeginsWithPredicateOperatorType,
	NSEndsWithPredicateOperatorType,
	NSInPredicateOperatorType,
	NSCustomSelectorPredicateOperatorType,
	NSContainsPredicateOperatorType = 99,
	NSBetweenPredicateOperatorType
};

enum {
	NSCaseInsensitivePredicateOption = 0x01,
	NSDiacriticInsensitivePredicateOption = 0x02
};

enum {
	NSDirectPredicateModifier = 0,
	NSAllPredicateModifier,
	NSAnyPredicateModifier
};

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSComparisonPredicate : NSPredicate
{
	NSPredicateOperatorType _operatorType;
	NSComparisonPredicateModifier _modifier;
	NSUInteger _options;
	SEL _customSelector;
	NSExpression *_lhs;
	NSExpression *_rhs;
}

+ (NSPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                              rightExpression:(NSExpression *)rhs
                                     modifier:(NSComparisonPredicateModifier)modifier
                                         type:(NSPredicateOperatorType)type
                                      options:(NSUInteger)options;
+ (NSPredicate *)predicateWithLeftExpression:(NSExpression *)lhs
                              rightExpression:(NSExpression *)rhs
                              customSelector:(SEL)selector;

- (id)initWithLeftExpression:(NSExpression *)lhs
             rightExpression:(NSExpression *)rhs
                    modifier:(NSComparisonPredicateModifier)modifier
                        type:(NSPredicateOperatorType)type
                     options:(NSUInteger)options NS_DESIGNATED_INITIALIZER;
- (id)initWithLeftExpression:(NSExpression *)lhs
             rightExpression:(NSExpression *)rhs
             customSelector:(SEL)selector NS_DESIGNATED_INITIALIZER;

- (NSPredicateOperatorType)predicateOperatorType;
- (NSComparisonPredicateModifier)comparisonPredicateModifier;
- (NSExpression *)leftExpression;
- (NSExpression *)rightExpression;
- (SEL)customSelector;
- (NSUInteger)options;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSCOMPARISONPREDICATE_H */
