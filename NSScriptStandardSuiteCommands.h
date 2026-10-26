/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptStandardSuiteCommands.h — the standard suite's ten commands, in Apple's own file (W7).
 *
 * These were declared in NSScriptCommand.h because the tree wrote one scripting file; Apple gives them a header, and
 * a client that imports it expects exactly these classes. Each is a command with the default implementation Apple
 * documents; a command whose effect needs a document model (move, clone) says what it could not do in the script-error
 * fields rather than doing half of it.
 *
 * `NSSaveOptions` lives here, with the two commands that take it — Apple's home for it, not NSScriptCommand's.
 */
#ifndef FOUNDATION_NSSCRIPTSTANDARDSUITECOMMANDS_H
#define FOUNDATION_NSSCRIPTSTANDARDSUITECOMMANDS_H

#import <Foundation/NSScriptCommand.h>

@class NSScriptObjectSpecifier;
@class NSScriptClassDescription;
@class NSDictionary;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, NSSaveOptions) {
	NSSaveOptionsYes = 0,
	NSSaveOptionsNo = 1,
	NSSaveOptionsAsk = 2
};

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

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTSTANDARDSUITECOMMANDS_H */
