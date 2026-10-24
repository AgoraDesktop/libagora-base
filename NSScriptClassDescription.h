/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptClassDescription.h — a class as a script suite describes it.
 *
 * The declaration dictionary is the .scriptSuite/.scriptTerminology shape: `Attributes`, `ToOneRelationships`,
 * `ToManyRelationships`, `Commands`, an `AppleEventCode` and the class it implements. Everything below reads that
 * dictionary; a key that is not declared is answered as absent rather than invented.
 */
#ifndef FOUNDATION_NSSCRIPTCLASSDESCRIPTION_H
#define FOUNDATION_NSSCRIPTCLASSDESCRIPTION_H

#import <CoreFoundation/CFBase.h>	/* FourCharCode */
#import <Foundation/NSClassDescription.h>
#import <Foundation/NSObjCRuntime.h>

@class NSDictionary;
@class NSScriptClassDescription;

NS_ASSUME_NONNULL_BEGIN

@interface NSScriptClassDescription : NSClassDescription
{
@private
	NSString *_suiteName;
	NSString *_className;
	NSDictionary *_declaration;
}

- (nullable instancetype)initWithSuiteName:(NSString *)suiteName
				 className:(NSString *)className
				dictionary:(nullable NSDictionary *)classDeclaration;

@property (readonly, copy) NSString *suiteName;
@property (readonly, copy) NSString *className;
@property (readonly) FourCharCode appleEventCode;

+ (nullable NSScriptClassDescription *)classDescriptionForClass:(Class)aClass;
- (nullable NSScriptClassDescription *)superclassDescription;

- (BOOL)hasPropertyForKey:(NSString *)key;
- (BOOL)hasReadablePropertyForKey:(NSString *)key;
- (BOOL)hasWritablePropertyForKey:(NSString *)key;
- (BOOL)hasOrderedToManyRelationshipForKey:(NSString *)key;
- (BOOL)isReadOnlyKey:(NSString *)key;
- (BOOL)isLocationRequiredToCreateForKey:(NSString *)key;

- (nullable NSString *)typeForKey:(NSString *)key;
- (nullable NSString *)defaultSubcontainerAttributeKey;
- (nullable NSString *)implementationClassName;
- (nullable NSString *)inverseForRelationshipKey:(NSString *)relationshipKey;

- (nullable NSScriptClassDescription *)classDescriptionForKey:(NSString *)key;
- (FourCharCode)appleEventCodeForKey:(NSString *)key;
- (nullable NSString *)keyWithAppleEventCode:(FourCharCode)code;
- (BOOL)matchesAppleEventCode:(FourCharCode)code;

- (nullable NSString *)selectorForCommand:(NSString *)commandName;
- (BOOL)supportsCommand:(NSString *)commandName;

@end

/* THE TWO ROOT-CLASS DOORS APPLE PUTS IN THIS HEADER. */
@interface NSObject (NSScriptClassDescription)
- (FourCharCode)classCode;
+ (NSString *)className;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTCLASSDESCRIPTION_H */
