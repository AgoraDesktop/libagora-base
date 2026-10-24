/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptCommand.h — a script command, its description, and the suite registry.
 *
 * A command is an OBJECT with a receiver specifier, a direct parameter and named arguments, and `-executeCommand`
 * evaluates them and calls `-performDefaultImplementation`. The subclasses below are the standard suite's nine, each
 * with the default implementation Apple documents; a command whose effect needs a document model (move, clone) says
 * what it could not do in the script-error fields rather than doing half of it.
 */
#ifndef FOUNDATION_NSSCRIPTCOMMAND_H
#define FOUNDATION_NSSCRIPTCOMMAND_H

#import <CoreFoundation/CFBase.h>
#import <Foundation/NSObject.h>

@class NSString;
@class NSArray;
@class NSDictionary;
@class NSMutableDictionary;
@class NSAppleEventDescriptor;
@class NSScriptObjectSpecifier;
@class NSScriptClassDescription;
@class NSScriptCommandDescription;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NSSaveOptions) {
	NSSaveOptionsYes = 0,
	NSSaveOptionsNo = 1,
	NSSaveOptionsAsk = 2
};

@interface NSScriptCommand : NSObject
{
@protected
	NSScriptCommandDescription *_commandDescription;
	id _directParameter;
	NSScriptObjectSpecifier *_receiversSpecifier;
	NSDictionary *_arguments;
	NSAppleEventDescriptor *_appleEvent;
	NSInteger _scriptErrorNumber;
	NSAppleEventDescriptor *_scriptErrorExpectedTypeDescriptor;
	id _scriptErrorOffendingObjectDescriptor;
	NSString *_scriptErrorString;
}

- (instancetype)initWithCommandDescription:(NSScriptCommandDescription *)commandDescription;

+ (nullable NSScriptCommand *)currentCommand;

@property (nullable, strong) NSScriptObjectSpecifier *receiversSpecifier;
@property (nullable, strong) id directParameter;
@property (nullable, copy) NSDictionary *arguments;

@property (nullable, readonly, strong) NSScriptCommandDescription *commandDescription;
@property (nullable, readonly, copy) NSAppleEventDescriptor *appleEvent;
@property (nullable, readonly, strong) id evaluatedReceivers;
@property (nullable, readonly, copy) NSDictionary *evaluatedArguments;

@property (readonly) BOOL isWellFormed;

- (nullable id)executeCommand;
- (nullable id)performDefaultImplementation;

@property NSInteger scriptErrorNumber;
@property (nullable, copy) NSString *scriptErrorString;
@property (nullable, strong) NSAppleEventDescriptor *scriptErrorExpectedTypeDescriptor;
@property (nullable, strong) id scriptErrorOffendingObjectDescriptor;

- (BOOL)suspendExecution;
- (void)resumeExecutionWithResult:(nullable id)result;

@end

/* ---- THE STANDARD SUITE'S COMMANDS ----------------------------------------------------------------------------- */

@interface NSSetCommand : NSScriptCommand
{
@private
	NSScriptObjectSpecifier *_keySpecifier;
}
@property (nullable, strong) NSScriptObjectSpecifier *keySpecifier;
@end

@interface NSDeleteCommand : NSScriptCommand
{
@private
	NSScriptObjectSpecifier *_keySpecifier;
}
@property (nullable, strong) NSScriptObjectSpecifier *keySpecifier;
@end

@interface NSCloneCommand : NSScriptCommand
{
@private
	NSScriptObjectSpecifier *_keySpecifier;
}
@property (nullable, strong) NSScriptObjectSpecifier *keySpecifier;
@end

@interface NSMoveCommand : NSScriptCommand
{
@private
	NSScriptObjectSpecifier *_keySpecifier;
}
@property (nullable, strong) NSScriptObjectSpecifier *keySpecifier;
@end

@interface NSCountCommand : NSScriptCommand
@end

@interface NSExistsCommand : NSScriptCommand
@end

@interface NSGetCommand : NSScriptCommand
@end

@interface NSCreateCommand : NSScriptCommand
{
@private
	NSScriptClassDescription *_createClassDescription;
	NSDictionary *_resolvedKeyDictionary;
}
@property (nullable, readonly, strong) NSScriptClassDescription *createClassDescription;
@property (nullable, readonly, copy) NSDictionary *resolvedKeyDictionary;
@end

@interface NSCloseCommand : NSScriptCommand
{
@private
	NSSaveOptions _saveOptions;
}
@property (readonly) NSSaveOptions saveOptions;
@end

@interface NSQuitCommand : NSScriptCommand
{
@private
	NSSaveOptions _saveOptions;
}
@property (readonly) NSSaveOptions saveOptions;
@end

/* ---- DESCRIPTIONS AND THE REGISTRY ----------------------------------------------------------------------------- */

@interface NSScriptCommandDescription : NSObject
{
@private
	NSString *_suiteName;
	NSString *_commandName;
	NSDictionary *_declaration;
}
- (nullable instancetype)initWithSuiteName:(NSString *)suiteName
			       commandName:(NSString *)commandName
				dictionary:(nullable NSDictionary *)commandDeclaration;
@property (readonly, copy) NSString *suiteName;
@property (readonly, copy) NSString *commandName;
@property (readonly, copy) NSString *commandClassName;
@property (readonly) FourCharCode appleEventClassCode;
@property (readonly) FourCharCode appleEventCode;
@property (readonly) FourCharCode appleEventCodeForReturnType;
@property (readonly, copy) NSArray *argumentNames;
- (nullable NSString *)typeForArgumentWithName:(NSString *)argumentName;
- (FourCharCode)appleEventCodeForArgumentWithName:(NSString *)argumentName;
- (BOOL)isOptionalArgumentWithName:(NSString *)argumentName;
- (nullable NSString *)returnType;
- (nullable NSScriptCommand *)createCommandInstance;
- (nullable NSScriptCommand *)createCommandInstanceWithZone:(nullable NSZone *)zone;
@end

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

#endif /* FOUNDATION_NSSCRIPTCOMMAND_H */
