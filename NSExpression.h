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
+ (NSExpression *)expressionForFunction:(NSString *)name arguments:(NSArray *)parameters;
+ (NSExpression *)expressionForAggregate:(NSArray *)subexpressions;
+ (NSExpression *)expressionForUnionSet:(NSExpression *)left with:(NSExpression *)right;
+ (NSExpression *)expressionForIntersectSet:(NSExpression *)left with:(NSExpression *)right;
+ (NSExpression *)expressionForMinusSet:(NSExpression *)left with:(NSExpression *)right;
+ (NSExpression *)expressionForSubquery:(NSExpression *)expression
                 usingIteratorVariable:(NSString *)variable
                             predicate:(id)predicate;
+ (NSExpression *)expressionForFunction:(NSExpression *)target
                           selectorName:(NSString *)name
                              arguments:(NSArray *)parameters;

- (id)initWithExpressionType:(NSExpressionType)type;

- (NSExpressionType)expressionType;
- (nullable id)constantValue;
- (nullable NSString *)keyPath;
- (nullable NSString *)function;
- (nullable NSString *)variable;
- (nullable NSExpression *)operand;
- (nullable NSArray *)arguments;
- (nullable id)collection;
- (nullable NSPredicate *)predicate;
- (nullable NSExpression *)leftExpression;
- (nullable NSExpression *)rightExpression;

/* THE ONLY DOOR THAT DOES WORK. `object` is the evaluated object (`SELF`); `context` carries the variable
 * bindings and is the same dictionary the predicate evaluates against. */
- (nullable id)expressionValueWithObject:(nullable id)object
                                 context:(nullable NSMutableDictionary *)context;

/* THE BLOCK PAYLOAD (10.6). `+expressionForBlock:arguments:` stores a copied block; this answers it, and nil for
 * every other expression kind — the same total-accessor rule the other payload doors follow. */
@property (nullable, readonly) id (^expressionBlock)(id, NSArray *, NSMutableDictionary *);

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSEXPRESSION_H */
