/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSPredicate — the filter half of the family, and the door Core Data's fetch layer stands on
 * (COREDATA-PLAN.md §4.1). Restored with `-filteredArrayUsingPredicate:` and its siblings, because §63.161
 * removed them in one campaign and COREDATA-PLAN.md §0.1's D0 answers the campaign.
 *
 * THE FORMAT STRING IS THE REAL INTERFACE. A predicate built by `+predicateWithFormat:` is text a caller
 * wrote, which is why the parser (`FNPredicateFormat.m`) refuses what it cannot honour instead of guessing:
 * a predicate that silently evaluated to NO would make `NSPredicate` disagree with itself between the
 * format door and the constructed one.
 *
 * `-predicateFormat` IS A CONTRACT, NOT A DEBUG AID: nib files and Core Data's model both carry predicates
 * as strings, so a predicate that cannot render itself cannot be saved.
 */

#ifndef FOUNDATION_NSPREDICATE_H
#define FOUNDATION_NSPREDICATE_H

#import <Foundation/NSObject.h>
#import <Foundation/NSCoding.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSOrderedSet.h>
#import <Foundation/NSMutableOrderedSet.h>
#include <stdarg.h>

@class NSString;
@class NSDictionary;

NS_ASSUME_NONNULL_BEGIN

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSPredicate : NSObject <NSCoding, NSCopying>
{
	void *_reserved;
}

+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat argumentArray:(nullable NSArray *)arguments;
+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat, ...;
+ (NSPredicate *)predicateWithFormat:(NSString *)predicateFormat arguments:(va_list)argList;

+ (NSPredicate *)predicateWithValue:(BOOL)value;

#if __has_feature(blocks)
+ (NSPredicate *)predicateWithBlock:(BOOL (^)(id evaluatedObject, NSDictionary *bindings))block NS_AVAILABLE_MAC(10_6);
#endif

- (NSString *)predicateFormat;

- (NSPredicate *)predicateWithSubstitutionVariables:(NSDictionary *)variables;

- (BOOL)evaluateWithObject:(nullable id)object;

/* THE SAME SANDBOX AS NSExpression's, and the same answer: this tree's boundary is the decoding allow-list, not a flag. */
- (void)allowEvaluation NS_AVAILABLE_MAC(10_9);

/* THE METADATA QUERY LANGUAGE IS THE FORMAT STRING'S (10.4). Spotlight's query syntax is the predicate format this
 * class already parses, so the door names the intent and delegates rather than growing a second parser. */
+ (nullable NSPredicate *)predicateFromMetadataQueryString:(NSString *)queryString NS_AVAILABLE_MAC(10_9);
- (BOOL)evaluateWithObject:(nullable id)object substitutionVariables:(nullable NSDictionary *)bindings NS_AVAILABLE_MAC(10_5);

@end

@interface NSArray<ObjectType> (NSPredicateSupport)
- (NSArray<ObjectType> *)filteredArrayUsingPredicate:(NSPredicate *)predicate;
@end

@interface NSMutableArray<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate;
@end

@interface NSSet<ObjectType> (NSPredicateSupport)
- (NSSet<ObjectType> *)filteredSetUsingPredicate:(NSPredicate *)predicate NS_AVAILABLE_MAC(10_5);
@end

@interface NSMutableSet<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate NS_AVAILABLE_MAC(10_5);
@end

/* THE ORDERED SET'S TWO, declared here because Apple declares them here — beside the other collections' predicate
 * support rather than on the class. A filtered ordered set KEEPS THE ORDER of the members that pass, which is why it can
 * be built by appending to a mutable ordered set (whose set rule already drops a duplicate). */
@interface NSOrderedSet<ObjectType> (NSPredicateSupport)
- (NSOrderedSet<ObjectType> *)filteredOrderedSetUsingPredicate:(NSPredicate *)predicate NS_AVAILABLE_MAC(10_7);
@end

@interface NSMutableOrderedSet<ObjectType> (NSPredicateSupport)
- (void)filterUsingPredicate:(NSPredicate *)predicate NS_AVAILABLE_MAC(10_7);
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSPREDICATE_H */
