/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSDebug.h — Foundation's diagnostic C doors.
 *
 * TEN OF APPLE'S ELEVEN ARE ASSERTION MACROS, and they are the caller's code rather than this library's: NSAssert,
 * NSCAssert, NSAssert1…NSAssert5, NSParameterAssert and their C twins expand to a raise at the call site. Only
 * `NSCountFrames()` is a real symbol, so it is the only thing this header declares. The macros are NOT declared
 * here: a macro cannot be linked, and providing half of Apple's set would make `NSDebug.h` mean something different
 * depending on which macro a caller reached for. A program that needs NSAssert gets it from its own toolchain's
 * <assert.h> or writes the raise.
 *
 * WHY THE FUNCTION IS A SYMBOL AND NOT A MACRO: Apple's own is `FOUNDATION_EXPORT NSUInteger NSCountFrames(void)`,
 * and the census counts a non-inline function by asking `nm -D` for it. A macro would be invisible to that
 * measurement — which is the same reason NSMakeRange is declared `static inline` rather than `#define`d.
 */
#ifndef FOUNDATION_NSDEBUG_H
#define FOUNDATION_NSDEBUG_H

#import <Foundation/NSObjCRuntime.h>

NS_ASSUME_NONNULL_BEGIN

/* THE NUMBER OF CALL FRAMES ON THE CURRENT THREAD'S STACK. Apple's note warns that the answer is undefined for
 * code compiled without frame pointers, and this implementation inherits that caveat: `backtrace(3)` walks what the
 * unwinder can see. */
FOUNDATION_EXPORT NSUInteger NSCountFrames(void);

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSDEBUG_H */
