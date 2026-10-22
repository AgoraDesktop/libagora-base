/*
 * forwarding — the two invocations trampolines, EXERCISED rather than merely linked.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. `NSInvocation_amd64.S` and `NSInvocation_arm64.S` are the only per-architecture
 * code in this library, and until this suite nothing in libagora-base called either of them: the bridge
 * suite tests toll-free bridging, `linguistic_units` tests text breaking, `normalization` is pure C over
 * Core Foundation. So the aarch64 trampoline could be assembled, linked, loaded and still be wrong — and
 * CI building it on real ARM hardware proved exactly the part that a build can prove, which is nothing
 * about behaviour. Issue 4 was filed as a BUILD failure and this is what upgrades the claim from "it
 * builds on ARM" to "it forwards on ARM".
 *
 * ONE CASE PER TRAMPOLINE, because they fail differently:
 *
 *   1. `fn_forward_entry` — the capture. The runtime calls it when a selector is not implemented, so the
 *      case sends a message no class implements and asserts that `-forwardInvocation:` received the
 *      arguments the CALLER passed. If the register file were captured with the wrong offsets this is a
 *      wrong number, not a crash, which is why the values are chosen to be distinguishable (7 and 0.5 are
 *      not 0 and 0.0).
 *
 *   2. `fn_call_image` — the replay. `-invoke` loads a stored image and makes the call from it. The case
 *      invokes a REAL method with one integer and one floating argument, so a trampoline that mixed the
 *      integer and FP register files would return a wrong sum rather than failing to link.
 *
 * THE SIGNATURE IS DELIBERATELY MIXED `q` and `d`: integers and floating point travel in different
 * register files on both architectures, and a trampoline that handled only one of them would pass a
 * single-type test. The ABI subset NSInvocation documents (six integer, eight floating, no stack
 * arguments) is what these two arguments sit inside.
 *
 * AND THE RETURN VALUE IS CHECKED BOTH WAYS: `fn_forward_entry` has to hand back what the forwarding
 * object stored, and `fn_call_image` has to hand back what the real method returned. Those are different
 * slots in the image (return_int and return_fp) and a test that only checked one would miss the other.
 */
#import <Foundation/Foundation.h>

#include <stdarg.h>
#include <stdio.h>

static int g_fail;

static void check(int ok, const char *fmt, ...)
{
	va_list ap;

	printf("%s ", ok ? "ok  " : "FAIL");
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	printf("\n");
	if (!ok) {
		g_fail++;
	}
}

/* The method the sender uses, declared so a call site can name it. NOTHING implements it on the
 * forwarding case below — that is the point. */
@protocol FNForwardProbe
- (long)probeLong:(long)a double:(double)b;
@end

/* ---- case 1: the object that does not implement the selector ------------------------------- */

static SEL		g_seenSelector;
static id		g_seenTarget;
static long		g_seenLong;
static double		g_seenDouble;
static int		g_forwardCount;

@interface FNForwarder : NSObject
@end

@implementation FNForwarder

/* The runtime asks this before it forwards, so answering is what makes the call forwardable at all. The
 * encoding is `q@:qd`: long return, self, _cmd, long, double. */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
	if (aSelector == @selector(probeLong:double:)) {
		return [NSMethodSignature signatureWithObjCTypes:"q@:qd"];
	}
	return [super methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
	g_forwardCount++;
	g_seenSelector = [anInvocation selector];
	g_seenTarget = [anInvocation target];
	[anInvocation getArgument:&g_seenLong atIndex:2];
	[anInvocation getArgument:&g_seenDouble atIndex:3];

	/* AND AN ANSWER, WHICH IS THE OTHER HALF OF THE TRAMPOLINE: fn_forward_entry reloads the image's
	 * return slots after the handler runs, so a value stored here is what the CALLER receives. */
	{
		long answer = g_seenLong + 1000;
		[anInvocation setReturnValue:&answer];
	}
}

@end

/* ---- case 2: a real method, reached through -invoke ---------------------------------------- */

@interface FNRealTarget : NSObject
@end

@implementation FNRealTarget

- (long)probeLong:(long)a double:(double)b
{
	return a + (long)(b * 100.0);
}

@end

/* ---- the cases ----------------------------------------------------------------------------- */

static void case_forwarding_trampoline(void)
{
	FNForwarder *forwarder = [[FNForwarder alloc] init];
	long result = 0;

	g_forwardCount = 0;
	g_seenSelector = NULL;
	g_seenTarget = nil;
	g_seenLong = 0;
	g_seenDouble = 0.0;

	/* THE SEND NO CLASS ANSWERS. If the trampoline is absent or miscompiled this is a
	 * -doesNotRecognizeSelector: raise rather than a wrong number, and the harness reports the raise. */
	result = [(id<FNForwardProbe>)forwarder probeLong:7 double:0.5];

	check(g_forwardCount == 1, "an unimplemented selector reached -forwardInvocation: exactly once (%d)",
	      g_forwardCount);
	check(g_seenSelector != NULL && sel_isEqual(g_seenSelector, @selector(probeLong:double:)),
	      "the forwarded selector survived the capture");
	check(g_seenTarget == (id)forwarder, "the forwarded target is the receiver, not a copy");
	check(g_seenLong == 7, "the integer argument crossed as 7 (got %ld)", g_seenLong);
	check(g_seenDouble == 0.5, "the floating argument crossed as 0.5 (got %g)", g_seenDouble);
	check(result == 1007, "the return value the forwarding object stored came back (got %ld)", result);

	[forwarder release];
}

static void case_call_image(void)
{
	FNRealTarget *target = [[FNRealTarget alloc] init];
	NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:"q@:qd"];
	NSInvocation *invocation;
	long a = 7;
	double b = 0.5;
	long result = 0;

	check(signature != nil, "the method signature was built from its encoding");
	if (signature == nil) {
		[target release];
		return;
	}

	invocation = [NSInvocation invocationWithMethodSignature:signature];
	check(invocation != nil, "the invocation was made");
	if (invocation == nil) {
		[target release];
		return;
	}

	[invocation setTarget:target];
	[invocation setSelector:@selector(probeLong:double:)];
	[invocation setArgument:&a atIndex:2];
	[invocation setArgument:&b atIndex:3];

	/* fn_call_image LOADS THE IMAGE AND MAKES THE CALL FROM IT. A trampoline that put the double in the
	 * integer register file, or the integer in the FP one, returns a wrong sum here. */
	[invocation invoke];
	[invocation getReturnValue:&result];

	check(result == 7 + 50, "the real method ran from the image and answered 57 (got %ld)", result);

	[target release];
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);

	@try {
		case_forwarding_trampoline();
		case_call_image();
	} @catch (NSException *e) {
		printf("FAIL the suite raised %s: %s\n", [[e name] UTF8String], [[e reason] UTF8String]);
		g_fail++;
	}

	printf("forwarding: %d failure(s)\n", g_fail);
	return g_fail == 0 ? 0 : 1;
}
