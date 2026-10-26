/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptCommandDescription.h — a command's declaration: its suite, its name, its class and its arguments (W7).
 *
 * Apple's own file name for the class W4 wrote inside NSScriptCommand.h. The class reads a command-declaration
 * dictionary (the shape a suite file carries) and answers the facts a command needs before it runs; the registry is
 * NSScriptSuiteRegistry.h, and the commands themselves are NSScriptStandardSuiteCommands.h.
 */
#ifndef FOUNDATION_NSSCRIPTCOMMANDDESCRIPTION_H
#define FOUNDATION_NSSCRIPTCOMMANDDESCRIPTION_H

#import <CoreFoundation/CFBase.h>	/* FourCharCode */
#import <Foundation/NSObject.h>
#import <Foundation/NSCoding.h>

@class NSCoder;
@class NSString;
@class NSArray;
@class NSDictionary;
@class NSScriptCommand;

NS_ASSUME_NONNULL_BEGIN

@interface NSScriptCommandDescription : NSObject
{
@private
	NSString *_suiteName;
	NSString *_commandName;
	NSDictionary *_declaration;
}
- (nullable instancetype)initWithSuiteName:(NSString *)suiteName
			       commandName:(NSString *)commandName
				dictionary:(nullable NSDictionary *)commandDeclaration NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (void)encodeWithCoder:(NSCoder *)coder;
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

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTCOMMANDDESCRIPTION_H */
