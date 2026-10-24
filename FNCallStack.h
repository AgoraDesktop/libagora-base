/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * FNCallStack.h — one implementation of the stack query, for the four public doors that ask it.
 *
 * NSThread and NSException both answer `+callStackReturnAddresses` and `+callStackSymbols`, and NSDebug.h's
 * `NSCountFrames()` answers the count. They are three spellings of one walk, so the walk is here rather than three
 * times over, and the public classes are thin.
 *
 * WHAT "THE STACK" MEANS HERE: the CALLER'S frames, with this file's own two helpers removed, so a caller that asks
 * sees its own frame first rather than the implementation's. A build with no `<execinfo.h>` answers an EMPTY array
 * and a count of zero rather than failing: the doors exist on every platform this library targets, and a stack
 * query is diagnostic information, not a dependency.
 */
#ifndef FOUNDATION_FNCALLSTACK_H
#define FOUNDATION_FNCALLSTACK_H

#import <Foundation/NSObjCRuntime.h>

@class NSArray;

NSUInteger FNCallStackCount(void);
NSArray *FNCallStackReturnAddresses(void);
NSArray *FNCallStackSymbols(void);

#endif /* FOUNDATION_FNCALLSTACK_H */
