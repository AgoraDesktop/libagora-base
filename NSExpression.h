/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSExpression — the value half of the predicate family (§63.161's reversal, COREDATA-PLAN.md §4.1).
 *
 * WHY IT CAME BACK. §63.161 removed the family because it is macOS 10.4 and §11.0's baseline was 10.2.
 * The tree's actual reference is 10.6 (`tests/api-10.6-census.txt` says so in its own preamble), 10.4 is
 * inside 10.6, and `api/10.6/appkit-manifest.txt` carries 29 rows naming a predicate. A ledger cannot list
 * `-fetchPredicate` while the type it returns does not exist. So the family is restored, and this is the
 * class the other three are built on.
 *
 * ONE CLASS, FIVE SHAPES, NOT A SUBCLASS HIERARCHY. Modern Foundation declares NSConstantValueExpression
 * and its siblings as public classes; the 10.6 headers declare ONE `@interface NSExpression` carrying an
 * `NSExpressionType`, and that is what this reproduces. The shape is a type tag plus the payload the tag
 * says is meaningful — which is also why `-constantValue` on a key-path expression answers nil rather than
 * raising: Apple's accessors are total, and a caller that asks the wrong question gets nothing.
 *
 * THE TYPE VALUES ARE APPLE'S NUMBERS, including the deliberate gaps (NSSubqueryExpressionType = 13,
 * NSBlockExpressionType = 19). They are serialised in nibs and archives, so renumbering them would be a
 * source-compatible way to be wrong.
 */

#ifndef FOUNDATION_NSEXPRESSION_H
#define FOUNDATION_NSEXPRESSION_H

#import <Foundation/NSObject.h>
#import <Foundation/NSCoding.h>
#include <stdarg.h>

@class NSString;
@class NSArray;
@class NSMutableDictionary;
@class NSPredicate;

typedef NSUInteger NSExpressionType;

enum {
	NSConstantValueExpressionType = 0,
	NSEvaluatedObjectExpressionType,
	NSVariableExpressionType,
	NSKeyPathExpressionType,
	NSFunctionExpressionType,
	NSUnionSetExpressionType,
	NSIntersectSetExpressionType,
	NSMinusSetExpressionType,
	NSSubqueryExpressionType = 13,
	NSAggregateExpressionType,
	NSBlockExpressionType = 19
};

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSExpression : NSObject <NSCoding, NSCopying>
{
	NSExpressionType _type;
	id _constantValue;		/* NSConstantValueExpressionType */
	NSString *_keyPath;		/* NSKeyPathExpressionType */
	NSString *_variable;		/* NSVariableExpressionType */
	NSString *_function;		/* NSFunctionExpressionType, the symbol name */
	NSArray *_arguments;		/* NSFunctionExpressionType arguments, NSAggregate subexpressions, block arguments */
	id _collection;			/* NSAggregate, and the SUBQUERY's source collection */
	NSPredicate *_predicate;	/* NSSubqueryExpressionType */
	NSExpression *_operand;		/* NSFunctionExpressionType target */
	NSExpression *_left;		/* set expressions */
	NSExpression *_right;
}

/* The eleven constructors are Apple's, including the three set expressions and the subquery. */
+ (NSExpression *)expressionForConstantValue:(nullable id)obj;
+ (NSExpression *)expressionForEvaluatedObject;
+ (NSExpression *)expressionForVariable:(NSString *)string;
+ (NSExpression *)expressionForKeyPath:(NSString *)keyPath;

/* THE ANY-KEY FORM (10.9): a key expression whose key is the evaluated object's OWN key, used by the predicate
 * compiler for `ANY` aggregates. It is a key-path expression with the special key `SELF`. */
+ (NSExpression *)expressionForAnyKey NS_AVAILABLE_MAC(10_9);

/* THE EVALUATION SANDBOX (10.9). A predicate or expression decoded from an UNTRUSTED archive is evaluated only if the
 * receiver says it may be: `-allowEvaluation` unlocks it. This tree never sets the lock — its secure decoding
 * allow-list is the boundary (see PROVENANCE.md) — so the door records the intent and answers YES, which is what a
 * caller who just called it expects. */
- (void)allowEvaluation NS_AVAILABLE_MAC(10_9);
+ (NSExpression *)expressionForFunction:(NSString *)name arguments:(NSArray *)parameters;
+ (NSExpression *)expressionForAggregate:(NSArray *)subexpressions NS_AVAILABLE_MAC(10_5);
+ (NSExpression *)expressionForUnionSet:(NSExpression *)left with:(NSExpression *)right NS_AVAILABLE_MAC(10_5);
+ (NSExpression *)expressionForIntersectSet:(NSExpression *)left with:(NSExpression *)right NS_AVAILABLE_MAC(10_5);
+ (NSExpression *)expressionForMinusSet:(NSExpression *)left with:(NSExpression *)right NS_AVAILABLE_MAC(10_5);
+ (NSExpression *)expressionForSubquery:(NSExpression *)expression
                 usingIteratorVariable:(NSString *)variable
                             predicate:(id)predicate NS_AVAILABLE_MAC(10_5);
+ (NSExpression *)expressionForFunction:(NSExpression *)target
                           selectorName:(NSString *)name
                              arguments:(NSArray *)parameters NS_AVAILABLE_MAC(10_5);

/* THE FORMAT DOORS (10.6). Apple declares the variadic form once and the other two beside it; declaring a fixed
 * `+expressionWithFormat:` next to the variadic one makes clang take the first and refuse a second argument at the
 * call site, which reads as a header disagreement and is not one. The grammar is `FNPredicateFormat.m`'s, with
 * arithmetic and grouping added and comparisons refused: `1 + 1` is `add:to:(1, 1)`, `2 * (3 + 4)` is
 * `multiply:by:(2, add:to:(3, 4))`, and `1 < 2` raises naming `+predicateWithFormat:`. */
+ (NSExpression *)expressionWithFormat:(NSString *)format, ... NS_AVAILABLE_MAC(10_6);
+ (NSExpression *)expressionWithFormat:(NSString *)format
                            arguments:(va_list)arguments NS_AVAILABLE_MAC(10_6);
+ (NSExpression *)expressionWithFormat:(NSString *)format
                        argumentArray:(NSArray *)arguments NS_AVAILABLE_MAC(10_6);

- (id)initWithExpressionType:(NSExpressionType)type;

- (NSExpressionType)expressionType;
- (nullable id)constantValue;
- (nullable NSString *)keyPath;
- (nullable NSString *)function;
- (nullable NSString *)variable;
- (nullable NSExpression *)operand;
- (nullable NSArray *)arguments;
- (nullable id)collection NS_AVAILABLE_MAC(10_5);
- (nullable NSPredicate *)predicate NS_AVAILABLE_MAC(10_5);
- (nullable NSExpression *)leftExpression NS_AVAILABLE_MAC(10_5);
- (nullable NSExpression *)rightExpression NS_AVAILABLE_MAC(10_5);

/* THE ONLY DOOR THAT DOES WORK. `object` is the evaluated object (`SELF`); `context` carries the variable
 * bindings and is the same dictionary the predicate evaluates against. */
- (nullable id)expressionValueWithObject:(nullable id)object
                                 context:(nullable NSMutableDictionary *)context;

/* THE BLOCK PAYLOAD (10.6). `+expressionForBlock:arguments:` stores a copied block; this answers it, and nil for
 * every other expression kind — the same total-accessor rule the other payload doors follow. The class method is
 * Apple's and was implemented before it was declared; a door a caller cannot name is not a door. */
+ (NSExpression *)expressionForBlock:(id (^)(id, NSArray *, NSMutableDictionary *))block
                          arguments:(NSArray *)arguments NS_AVAILABLE_MAC(10_6);
@property (nullable, readonly) id (^expressionBlock)(id, NSArray *, NSMutableDictionary *);

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSEXPRESSION_H */
