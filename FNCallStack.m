/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * FNCallStack.m — backtrace(3), when the platform has it.
 *
 * **THE SKIP COUNT IS THE WHOLE CONTRACT.** `backtrace()` includes its own caller, so an unadjusted answer would
 * make every stack begin inside this file and shift by one the frames a caller compares. Each public door's caller
 * expects ITS frame first, so the walk starts past the public method, this file's wrapper, and `backtrace` itself.
 */

#import "FNCallStack.h"
#import <Foundation/NSDebug.h>	/* NSCountFrames, the C door onto this walk */
#import <Foundation/NSArray.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSString.h>

#if defined(__has_include)
#  if __has_include(<execinfo.h>)
#    define FN_HAVE_BACKTRACE 1
#  endif
#endif

#ifdef FN_HAVE_BACKTRACE
#include <execinfo.h>
#include <stdlib.h>
#include <string.h>	/* memmove */
#endif

/* THE CAP. A stack deeper than this is not diagnostic information a caller can use, and an unbounded walk is how a
 * recursive mistake turns a query into a crash. Apple's own number is not published; the value is ours and stated. */
#define FN_MAX_FRAMES 128

/* 2 IS `backtrace` AND THE FN__ FUNCTION BELOW; each public helper adds one more for itself. */
static NSUInteger fn_backtrace(void **frames, NSUInteger skip)
{
#ifdef FN_HAVE_BACKTRACE
	int count = backtrace(frames, (int)FN_MAX_FRAMES);

	if (count <= (int)skip) {
		return 0;
	}
	memmove(frames, frames + skip, sizeof(void *) * (size_t)(count - (int)skip));
	return (NSUInteger)(count - (int)skip);
#else
	(void)frames;
	(void)skip;
	return 0;
#endif
}

NSUInteger FNCallStackCount(void)
{
	void *frames[FN_MAX_FRAMES];

	return fn_backtrace(frames, 2);
}

NSArray *FNCallStackReturnAddresses(void)
{
	void *frames[FN_MAX_FRAMES];
	NSUInteger count = fn_backtrace(frames, 2);
	NSMutableArray *addresses = [NSMutableArray arrayWithCapacity:count];
	NSUInteger i;

	for (i = 0; i < count; i++) {
		[addresses addObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)(uintptr_t)frames[i]]];
	}
	return addresses;
}

NSArray *FNCallStackSymbols(void)
{
#ifdef FN_HAVE_BACKTRACE
	void *frames[FN_MAX_FRAMES];
	NSUInteger count = fn_backtrace(frames, 2);
	NSMutableArray *symbols;
	char **names;
	NSUInteger i;

	if (count == 0) {
		return [NSArray array];
	}
	names = backtrace_symbols(frames, (int)count);
	if (names == NULL) {
		return [NSArray array];
	}
	symbols = [NSMutableArray arrayWithCapacity:count];
	for (i = 0; i < count; i++) {
		[symbols addObject:[NSString stringWithUTF8String:names[i]]];
	}
	free(names);		/* backtrace_symbols allocates; the strings are copied above */
	return symbols;
#else
	return [NSArray array];
#endif
}

/* THE C DOOR, declared in NSDebug.h. It shares the walk, so `NSCountFrames()` and `+[NSThread
 * callStackReturnAddresses]` can never disagree about how deep the stack is. */
NSUInteger NSCountFrames(void)
{
	return FNCallStackCount();
}
