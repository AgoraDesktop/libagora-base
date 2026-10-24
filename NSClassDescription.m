/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <Foundation/NSClassDescription.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>
#include <pthread.h>

static NSMutableDictionary *fn_class_descriptions = nil;
static pthread_mutex_t fn_class_descriptions_lock = PTHREAD_MUTEX_INITIALIZER;

@implementation NSClassDescription

+ (void)registerClassDescription:(NSClassDescription *)description forClass:(Class)aClass
{
	if (description == nil || aClass == Nil) {
		return;
	}
	pthread_mutex_lock(&fn_class_descriptions_lock);
	if (fn_class_descriptions == nil) {
		fn_class_descriptions = [[NSMutableDictionary alloc] init];
	}
	[fn_class_descriptions setObject:description forKey:NSStringFromClass(aClass)];
	pthread_mutex_unlock(&fn_class_descriptions_lock);
}

+ (NSClassDescription *)classDescriptionForClass:(Class)aClass
{
	NSClassDescription *description = nil;

	if (aClass == Nil) {
		return nil;
	}
	pthread_mutex_lock(&fn_class_descriptions_lock);
	description = [[[fn_class_descriptions objectForKey:NSStringFromClass(aClass)] retain] autorelease];
	pthread_mutex_unlock(&fn_class_descriptions_lock);
	return description;
}

+ (void)invalidateClassDescriptionCache
{
	pthread_mutex_lock(&fn_class_descriptions_lock);
	[fn_class_descriptions removeAllObjects];
	pthread_mutex_unlock(&fn_class_descriptions_lock);
}

/* NO DECLARATION, NO SCHEMA. An empty array is a fact — this class knows of no attributes — rather than a nil that a
 * caller has to distinguish from "not asked". */
- (NSArray *)attributeKeys { return [NSArray array]; }
- (NSArray *)toOneRelationshipKeys { return [NSArray array]; }
- (NSArray *)toManyRelationshipKeys { return [NSArray array]; }
- (NSString *)inverseForRelationshipKey:(NSString *)relationshipKey
{
	(void)relationshipKey;
	return nil;
}

@end

@implementation NSObject (NSClassDescriptionPrimitives)

- (NSClassDescription *)classDescription
{
	return [NSClassDescription classDescriptionForClass:[self class]];
}

- (NSArray *)attributeKeys
{
	NSClassDescription *description = [self classDescription];

	return description != nil ? [description attributeKeys] : [NSArray array];
}

- (NSArray *)toOneRelationshipKeys
{
	NSClassDescription *description = [self classDescription];

	return description != nil ? [description toOneRelationshipKeys] : [NSArray array];
}

- (NSArray *)toManyRelationshipKeys
{
	NSClassDescription *description = [self classDescription];

	return description != nil ? [description toManyRelationshipKeys] : [NSArray array];
}

- (NSString *)inverseForRelationshipKey:(NSString *)relationshipKey
{
	NSClassDescription *description = [self classDescription];

	return description != nil ? [description inverseForRelationshipKey:relationshipKey] : nil;
}

@end
