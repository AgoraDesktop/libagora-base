/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptSuiteRegistry.h — the process-wide registry of suite declarations (W7), in Apple's own file.
 *
 * A suite file declares classes and commands; the registry is where they are recorded so a command can be found by
 * its Apple-event codes. The class is real: it stores and answers what was registered, and `-loadSuitesFromBundle:`
 * refuses by name because this system loads no script suite bundles.
 */
#ifndef FOUNDATION_NSSCRIPTSUITEREGISTRY_H
#define FOUNDATION_NSSCRIPTSUITEREGISTRY_H

#import <CoreFoundation/CFBase.h>	/* FourCharCode */
#import <Foundation/NSObject.h>

@class NSString;
@class NSArray;
@class NSDictionary;
@class NSMutableDictionary;
@class NSScriptClassDescription;
@class NSScriptCommandDescription;

NS_ASSUME_NONNULL_BEGIN

@interface NSScriptSuiteRegistry : NSObject
{
@private
	NSMutableDictionary *_classDescriptions;
	NSMutableDictionary *_commandDescriptions;
	NSMutableDictionary *_suites;
}
+ (NSScriptSuiteRegistry *)sharedScriptSuiteRegistry;
+ (void)setSharedScriptSuiteRegistry:(NSScriptSuiteRegistry *)registry;
@property (readonly, copy) NSArray *suiteNames;
- (nullable NSString *)suiteForAppleEventCode:(FourCharCode)code;
- (FourCharCode)appleEventCodeForSuite:(NSString *)suiteName;
- (nullable NSArray *)classDescriptionsInSuite:(NSString *)suiteName;
- (nullable NSArray *)commandDescriptionsInSuite:(NSString *)suiteName;
- (nullable NSScriptClassDescription *)classDescriptionWithAppleEventCode:(FourCharCode)code;
- (nullable NSScriptCommandDescription *)commandDescriptionWithAppleEventClass:(FourCharCode)eventClass
							       andAppleEventCode:(FourCharCode)eventCode;
- (void)registerClassDescription:(NSScriptClassDescription *)description;
- (void)registerCommandDescription:(NSScriptCommandDescription *)description;
- (void)loadSuitesFromBundle:(id)bundle;
- (void)loadSuiteWithDictionary:(NSDictionary *)suiteDeclaration fromBundle:(nullable id)bundle;
- (nullable id)aeteResource:(NSString *)name;
- (nullable id)bundleForSuite:(NSString *)suiteName;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTSUITEREGISTRY_H */
