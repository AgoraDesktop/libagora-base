/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSClassDescription.h — the registry that says what a class's properties and relationships are called.
 *
 * A plain NSClassDescription answers EMPTY LISTS: without a script-suite declaration there is nothing to report, and
 * an empty list is the truthful answer rather than a fabricated schema. NSScriptClassDescription (its own header) is
 * the subclass built from a suite dictionary.
 */
#ifndef FOUNDATION_NSCLASSDESCRIPTION_H
#define FOUNDATION_NSCLASSDESCRIPTION_H

#import <Foundation/NSObject.h>

@class NSArray;
@class NSString;

NS_ASSUME_NONNULL_BEGIN

@interface NSClassDescription : NSObject

+ (void)registerClassDescription:(NSClassDescription *)description forClass:(Class)aClass;
+ (nullable NSClassDescription *)classDescriptionForClass:(Class)aClass;
+ (void)invalidateClassDescriptionCache;

- (NSArray *)attributeKeys;
- (NSArray *)toOneRelationshipKeys;
- (NSArray *)toManyRelationshipKeys;
- (nullable NSString *)inverseForRelationshipKey:(NSString *)relationshipKey;

@end

/* THE ROOT-CLASS DOORS APPLE PUTS IN THIS HEADER: every object answers its class description's schema, and the default
 * class description has none. */
@interface NSObject (NSClassDescriptionPrimitives)
- (nullable NSClassDescription *)classDescription;
- (NSArray *)attributeKeys;
- (NSArray *)toOneRelationshipKeys;
- (NSArray *)toManyRelationshipKeys;
- (nullable NSString *)inverseForRelationshipKey:(NSString *)relationshipKey;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSCLASSDESCRIPTION_H */
