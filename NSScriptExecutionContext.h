/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSScriptExecutionContext.h — the scripting context a command evaluates against (W7), in Apple's own file.
 *
 * Three references: the top-level object, the object being tested by a `whose` clause, and the range container. The
 * specifiers read them (NSScriptObjectSpecifiers.m); this header only names the class Apple names.
 */
#ifndef FOUNDATION_NSSCRIPTEXECUTIONCONTEXT_H
#define FOUNDATION_NSSCRIPTEXECUTIONCONTEXT_H

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSScriptExecutionContext : NSObject
{
@private
	id _topLevelObject;
	id _objectBeingTested;
	id _rangeContainerObject;
}
+ (NSScriptExecutionContext *)sharedScriptExecutionContext;
@property (nullable, strong) id topLevelObject;
@property (nullable, strong) id objectBeingTested;
@property (nullable, strong) id rangeContainerObject;
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSSCRIPTEXECUTIONCONTEXT_H */
