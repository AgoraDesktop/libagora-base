/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSCompoundPredicate — AND, OR and NOT. Three types, and the `NOT` case holds exactly one subpredicate
 * while the other two hold any number, which is the one shape rule the class enforces rather than documents.
 */

#ifndef FOUNDATION_NSCOMPOUNDPREDICATE_H
#define FOUNDATION_NSCOMPOUNDPREDICATE_H

#import <Foundation/NSPredicate.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSUInteger NSCompoundPredicateType;

enum {
	NSNotPredicateType = 0,
	NSAndPredicateType,
	NSOrPredicateType
};

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSCompoundPredicate : NSPredicate
{
	NSCompoundPredicateType _type;
	NSArray *_subpredicates;
}

- (id)initWithType:(NSCompoundPredicateType)type subpredicates:(NSArray *)subpredicates;

- (NSCompoundPredicateType)compoundPredicateType;
- (NSArray *)subpredicates;

+ (NSPredicate *)andPredicateWithSubpredicates:(NSArray *)subpredicates;
+ (NSPredicate *)orPredicateWithSubpredicates:(NSArray *)subpredicates;
+ (NSPredicate *)notPredicateWithSubpredicate:(NSPredicate *)predicate;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSCOMPOUNDPREDICATE_H */
