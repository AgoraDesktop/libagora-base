/*
 * null_identity — CFNull and NSNull are one object as far as Core Foundation is concerned.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHY THIS FILE EXISTS. `CFEqual([NSNull null], kCFNull)` is TRUE on x86-64 and FALSE on aarch64, and
 * nothing in the tree asked the question, so nothing noticed. It surfaced only when a CI runner on real
 * ARM hardware first ran the bridge suite (issue 6). The `bridges` suite does ask it — `door_null` is
 * `CFEqual(o, kCFNull)` — but only in the middle of seventy-seven cases, where the failing line names the
 * TYPE and not the reason.
 *
 * SO THIS PROBE PRINTS THE WHOLE ANSWER, ALWAYS, and then asserts it. A test that says only "failed"
 * leaves the next person to rediscover how the two objects differ; a test whose output IS the measurement
 * costs nothing when it passes (ctest discards it) and hands over the diagnosis when it does not. That is
 * the same reason the hyphenation case in tests/linguistic_units.m prints what it found.
 *
 * WHAT THE TWO OBJECTS ARE, MEASURED ON X86-64: `+[NSNull null]` answers a Foundation singleton of class
 * NSNull, and `kCFNull` is Core Foundation's own static `__kCFNull`, whose class is `__NSCFNull` — the
 * subclass `cf_bridged_subclass` builds over NSNull and writes into the static's isa at registration.
 * THEY ARE DIFFERENT POINTERS, so `CFEqual`'s `cf1 == cf2` short-circuit cannot be what passes.
 *
 * THE MECHANISM IS NOT WHAT IT LOOKS LIKE, AND MEASURING IT WAS THE POINT. `CFEqual` has two `-isEqual:`
 * dispatches above its type-and-hook comparison, and on x86-64 NEITHER of them is what answers YES here:
 * `-[NSNull isEqual:]` is pointer identity (`other == self`) and answers NO, and the CF-owned `__NSCFNull`
 * answers NO as well — measured, and correctly, since it inherits that identity test and the pointers
 * differ. So the YES comes from further down Core Foundation's own comparison, past both dispatches. This
 * file prints all of it rather than asserting a story about it: the first version of this comment claimed
 * the second dispatch carried `CFEqual`, and the probe disproved that on its first run.
 */
#import <Foundation/Foundation.h>

#include <CoreFoundation/CoreFoundation.h>
#include <objc/runtime.h>
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

/* A CLASS NAME THAT CANNOT CRASH THE PROBE. `object_getClass` answers NULL for an object with no isa —
 * which is exactly the state `__kCFNull` is in before `__CFNullBindOwnedClass` runs, and exactly what this
 * test may be called on to diagnose — and `class_getName` is not obliged to like being handed it. A
 * diagnostic that segfaults while reporting a defect has replaced the defect with a worse one. */
static const char *cls_name(const void *obj)
{
	Class c = object_getClass((id)obj);
	const char *name;

	if (c == NULL) {
		return "(no class: _cfisa is 0)";
	}
	name = class_getName(c);
	return (name != NULL) ? name : "(unnamed class)";
}

int main(void)
{
	id nsnull = [NSNull null];
	CFNullRef cfnull = kCFNull;
	CFTypeID want = CFNullGetTypeID();

	setvbuf(stdout, NULL, _IONBF, 0);

	/* THE MEASUREMENT, BEFORE ANY VERDICT. Every line here is a fact the fix has to agree with. */
	printf("--- CFNull identity, measured ---\n");
	printf("  CFNullGetTypeID()      = %lu\n", (unsigned long)want);
	printf("  [NSNull null]          = %p  class %s\n", (void *)nsnull, cls_name(nsnull));
	printf("  kCFNull                = %p  class %s\n", (void *)cfnull, cls_name((const void *)cfnull));
	printf("  same pointer           = %d\n", (const void *)nsnull == (const void *)cfnull);
	printf("  CFGetTypeID(nsnull)    = %lu\n", (unsigned long)CFGetTypeID((CFTypeRef)nsnull));
	printf("  CFGetTypeID(kCFNull)   = %lu\n", (unsigned long)CFGetTypeID((CFTypeRef)cfnull));
	printf("  -[NSNull isEqual:]     = %d  (pointer identity, so 0 is correct)\n",
	       [(id)nsnull isEqual:(id)cfnull]);
	printf("  [(id)kCFNull isEqual:] = %d  (the dispatch that carries CFEqual)\n",
	       [(id)cfnull isEqual:(id)nsnull]);
	printf("  CFEqual(kCFNull,kCFNull) = %d\n", CFEqual((CFTypeRef)cfnull, (CFTypeRef)cfnull));
	printf("  CFEqual(nsnull,kCFNull)  = %d\n", CFEqual((CFTypeRef)nsnull, (CFTypeRef)cfnull));
	printf("  CFEqual(kCFNull,nsnull)  = %d\n", CFEqual((CFTypeRef)cfnull, (CFTypeRef)nsnull));
	printf("  CFHash(nsnull) == CFHash(kCFNull) = %d\n",
	       CFHash((CFTypeRef)nsnull) == CFHash((CFTypeRef)cfnull));
	printf("--- verdict ---\n");

	/* AND THE CONTRACT. One object, so every question about the pair has one answer. */
	check(CFGetTypeID((CFTypeRef)nsnull) == want, "NSNull's object is a CFNull");
	check(CFGetTypeID((CFTypeRef)cfnull) == want, "kCFNull is a CFNull");
	check(CFEqual((CFTypeRef)cfnull, (CFTypeRef)cfnull) == 1, "kCFNull equals itself");
	check(CFEqual((CFTypeRef)nsnull, (CFTypeRef)cfnull) == 1,
	      "CFEqual(NSNull null, kCFNull) — the pair is one object");
	check(CFEqual((CFTypeRef)cfnull, (CFTypeRef)nsnull) == 1,
	      "CFEqual(kCFNull, NSNull null) — and equal the other way round");
	check(CFHash((CFTypeRef)nsnull) == CFHash((CFTypeRef)cfnull),
	      "equal objects hash equally (Cocoa's own rule)");

	/* ⚠ NO ASSERTION ON `-[__NSCFNull isEqual:]` HERE, AND THAT IS DELIBERATE. It answers NO on x86-64 —
	 * measured — and NO is CORRECT: `-[NSNull isEqual:]` is pointer identity (`other == self`) and these
	 * are different pointers, so the subclass that inherits that answer is answering rightly. `CFEqual`
	 * is the door whose contract says YES, because it is CORE FOUNDATION's reading of the pair and Core
	 * Foundation has read NSNull and CFNull as one object since long before Foundation existed. Pinning
	 * the subclass to a YES would encode a wrong expectation; the fact is printed above instead, where
	 * it explains why `CFEqual` cannot be reached through either `-isEqual:` dispatch. */

	printf("null_identity: %d failure(s)\n", g_fail);
	return g_fail == 0 ? 0 : 1;
}
