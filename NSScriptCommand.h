/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptCommand.h — ONE script command: a receiver specifier, a direct parameter and named arguments (W7).
 *
 * Apple's file has this class and nothing else; the standard suite's commands are NSScriptStandardSuiteCommands.h,
 * the description is NSScriptCommandDescription.h, and the registry is NSScriptSuiteRegistry.h. A command EVALUATES
 * its arguments and calls `-performDefaultImplementation`, which a subclass overrides; the base's answer is what a
 * bare command does.
 */
#ifndef FOUNDATION_NSSCRIPTCOMMAND_H
#define FOUNDATION_NSSCRIPTCOMMAND_H

#import <CoreFoundation/CFBase.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSCoding.h>

@class NSCoder;
@class NSString;
@class NSArray;
@class NSDictionary;
@class NSMutableDictionary;
@class NSAppleEventDescriptor;
@class NSScriptObjectSpecifier;
@class NSScriptClassDescription;
@class NSScriptCommandDescription;

NS_ASSUME_NONNULL_BEGIN

@interface NSScriptCommand : NSObject <NSCoding>
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

- (instancetype)initWithCommandDescription:(NSScriptCommandDescription *)commandDescription NS_DESIGNATED_INITIALIZER;
/* A COMMAND ARCHIVES, and the coder door is a CONVENIENCE initializer rather than a designated one: Apple's manifest
 * does not mark it, so it reads the description first and hands it to the designated door, which is the funnel every
 * other initializer uses. */
- (nullable instancetype)initWithCoder:(NSCoder *)coder;
- (void)encodeWithCoder:(NSCoder *)coder;

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
@property (nullable, strong) NSAppleEventDescriptor *scriptErrorExpectedTypeDescriptor NS_AVAILABLE_MAC(10_5);
@property (nullable, strong) id scriptErrorOffendingObjectDescriptor NS_AVAILABLE_MAC(10_5);

- (BOOL)suspendExecution;
- (void)resumeExecutionWithResult:(nullable id)result;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTCOMMAND_H */
