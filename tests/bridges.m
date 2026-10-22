/*
 * bridges — the toll-free bridge, exhaustively.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * WHAT THIS IS FOR. The bridge is a JOINT property of two components: Core Foundation dispatches to
 * Objective-C through `CF_IS_OBJC` (libagora-core) and libagora-base registers which class each of its
 * type ids answers to (NSCFBridging.m). NOTHING IN EITHER COMPONENT'S OWN BUILD CAN SEE THE PAIRING -- a
 * registration that names the wrong class, a class whose methods do not exist, a door that dispatches to
 * something that cannot answer: all of them compile, all of them link, and all of them are silent until
 * something is asked. So every registered type is asked here.
 *
 * EACH CASE IS CHECKED FOR: that Core Foundation agrees on the object's type id; that at least one CORE
 * FOUNDATION DOOR, called on a FOUNDATION OBJECT, reaches the implementation; that the object survives
 * CFRetain/CFRelease; and that CFCopyDescription answers. The door is the per-case part, because the
 * interesting question is never "does the type id match" but "does this particular door work".
 *
 * AND THE REGRESSIONS ARE CASES TOO. Everything this bridge cost to get working -- tagged pointers, the
 * cluster, CFSTR's two layouts, a Core Foundation object wearing no class, singletons -- is a case below,
 * because each of them was a crash and a crash that can come back is worth a test.
 */
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <objc/runtime.h>
#include <sys/wait.h>
#include <unistd.h>

static int g_pass, g_fail;

static void check(int ok, const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	if (ok) {
		g_pass++;
	} else {
		g_fail++;
		fprintf(stderr, "FAIL: ");
		vfprintf(stderr, fmt, ap);
		fprintf(stderr, "\n");
	}
	va_end(ap);
}

/* ------------------------------------------------------------------------ */
/* the table: one row per registered type                                    */
/* ------------------------------------------------------------------------ */

typedef struct {
	const char *name;
	CFTypeID (*typeID)(void);
	id (*make)(void);			/* a FOUNDATION instance */
	int (*door)(id obj);			/* one Core Foundation door on it */
} bridge_case;

static int door_string(id o)
{
	NSString *s = o;
	return CFStringGetLength((CFStringRef)s) == (CFIndex)[s length] &&
	       CFStringGetLength((CFStringRef)s) == 5;
}
static int door_array(id o) { return CFArrayGetCount((CFArrayRef)o) == 2; }
static int door_data(id o) { return CFDataGetLength((CFDataRef)o) == 3; }
static int door_dictionary(id o) { return CFDictionaryGetCount((CFDictionaryRef)o) == 1; }
static int door_set(id o) { return CFSetGetCount((CFSetRef)o) == 1; }
static int door_number(id o)
{
	double d = 0.0;
	return CFNumberGetValue((CFNumberRef)o, kCFNumberDoubleType, &d) && d == 42.0;
}
/* -978307200.0 AND NOT 0.0: Core Foundation counts from 2001 and timeIntervalSince1970 counts from
 * 1970, so a date built at 1970 is a NEGATIVE absolute time. This test asserted 0.0 and reported the
 * door as failing when it was right -- the suite's SECOND false failure, after kCFAllocatorDefault. */
static int door_date(id o) { return CFDateGetAbsoluteTime((CFDateRef)o) == -978307200.0; }
static int door_null(id o) { return CFEqual((CFTypeRef)o, kCFNull); }
static int door_locale(id o) { return CFLocaleGetIdentifier((CFLocaleRef)o) != NULL; }
static int door_timezone(id o) { return CFTimeZoneGetName((CFTimeZoneRef)o) != NULL; }
static int door_calendar(id o) { return CFCalendarGetIdentifier((CFCalendarRef)o) != NULL; }
static int door_charset(id o)
{
	return CFCharacterSetIsCharacterMember((CFCharacterSetRef)o, (UniChar)' ') ? 1 : 0;
}
static int door_error(id o) { return CFErrorGetCode((CFErrorRef)o) == 1; }
static int door_url(id o) { return CFURLGetString((CFURLRef)o) != NULL; }
static int door_attrstr(id o) { return CFAttributedStringGetLength((CFAttributedStringRef)o) == 1; }
static int door_timer(id o) { return CFRunLoopTimerGetInterval((CFRunLoopTimerRef)o) == 1.0; }
static int door_instream(id o) { return CFReadStreamGetStatus((CFReadStreamRef)o) != kCFStreamStatusError; }
static int door_outstream(id o) { return CFWriteStreamGetStatus((CFWriteStreamRef)o) != kCFStreamStatusError; }

static id make_string(void) { return @"hello"; }
static id make_array(void) { return @[ @1, @2 ]; }
static id make_data(void) { return [NSData dataWithBytes:"abc" length:3]; }
static id make_dictionary(void) { return @{ @"k": @"v" }; }
static id make_set(void) { return [NSSet setWithObject:@1]; }
static id make_number(void) { return @42; }
static id make_date(void) { return [NSDate dateWithTimeIntervalSince1970:0.0]; }
static id make_null(void) { return [NSNull null]; }
static id make_locale(void) { return [NSLocale currentLocale]; }
static id make_timezone(void) { return [NSTimeZone timeZoneWithName:@"UTC"]; }
static id make_calendar(void) { return [NSCalendar currentCalendar]; }
static id make_charset(void) { return [NSCharacterSet whitespaceCharacterSet]; }
static id make_error(void) { return [NSError errorWithDomain:@"d" code:1 userInfo:nil]; }
static id make_url(void) { return [NSURL URLWithString:@"http://example.com/"]; }
static id make_attrstr(void) { return [[NSAttributedString alloc] initWithString:@"s"]; }
static id make_timer(void) { return [NSTimer timerWithTimeInterval:1.0 target:nil selector:@selector(self) userInfo:nil repeats:NO]; }
static id make_instream(void) { return [NSInputStream inputStreamWithData:[NSData dataWithBytes:"x" length:1]]; }
static id make_outstream(void) { return [NSOutputStream outputStreamToMemory]; }

static const bridge_case g_cases[] = {
	{ "NSString        <-> CFString",         CFStringGetTypeID,          make_string,     door_string },
	{ "NSArray         <-> CFArray",          CFArrayGetTypeID,           make_array,      door_array },
	{ "NSData          <-> CFData",           CFDataGetTypeID,            make_data,       door_data },
	{ "NSDictionary    <-> CFDictionary",     CFDictionaryGetTypeID,      make_dictionary, door_dictionary },
	{ "NSSet           <-> CFSet",            CFSetGetTypeID,             make_set,        door_set },
	{ "NSNumber        <-> CFNumber",         CFNumberGetTypeID,          make_number,     door_number },
	{ "NSDate          <-> CFDate",           CFDateGetTypeID,            make_date,       door_date },
	{ "NSNull          <-> CFNull",           CFNullGetTypeID,            make_null,       door_null },
	{ "NSLocale        <-> CFLocale",         CFLocaleGetTypeID,          make_locale,     door_locale },
	{ "NSTimeZone      <-> CFTimeZone",       CFTimeZoneGetTypeID,        make_timezone,   door_timezone },
	{ "NSCalendar      <-> CFCalendar",       CFCalendarGetTypeID,        make_calendar,   door_calendar },
	{ "NSCharacterSet  <-> CFCharacterSet",   CFCharacterSetGetTypeID,    make_charset,    door_charset },
	{ "NSError         <-> CFError",          CFErrorGetTypeID,           make_error,      door_error },
	{ "NSURL           <-> CFURL",            CFURLGetTypeID,             make_url,        door_url },
	{ "NSAttributedString <-> CFAttributedString", CFAttributedStringGetTypeID, make_attrstr, door_attrstr },
	{ "NSTimer         <-> CFRunLoopTimer",   CFRunLoopTimerGetTypeID,    make_timer,      door_timer },
	{ "NSInputStream   <-> CFReadStream",     CFReadStreamGetTypeID,      make_instream,   door_instream },
	{ "NSOutputStream  <-> CFWriteStream",    CFWriteStreamGetTypeID,     make_outstream,  door_outstream },
};

/* ------------------------------------------------------------------------ */
/* the regressions                                                           */
/* ------------------------------------------------------------------------ */

/* THE REGRESSIONS, ONE GROUP PER CHILD, for the same reason the cases have one each: a HALT in the
 * middle of this block used to take every group after it with it. */
static void reg_cluster(void)
{
	/* Foundation answers CFArrayGetTypeID() with five classes, and every one of them has to be
	 * recognised -- an equality test against the cluster root would match none. */
	id arrays[] = { @[], @[ @1 ], @[ @1, @2 ], @[ @1, @2, @3, @4, @5, @6, @7, @8, @9 ],
			[NSMutableArray array], [NSMutableArray arrayWithObject:@1] };

	for (size_t i = 0; i < sizeof arrays / sizeof arrays[0]; i++) {
		if ([arrays[i] isKindOfClass:[NSMutableArray class]]) {
			CFArrayAppendValue((CFMutableArrayRef)arrays[i], CFSTR("appended"));
		}
		check(CFArrayGetCount((CFArrayRef)arrays[i]) == (CFIndex)[arrays[i] count],
		      "cluster member %s: CF count %ld vs ObjC count %ld",
		      class_getName([arrays[i] class]),
		      (long)CFArrayGetCount((CFArrayRef)arrays[i]), (long)[arrays[i] count]);
	}
}

static void reg_tagged(void)
{
	/* A short @"..." literal has no isa: the pointer's tag bits hold the class. Reading offset 0 of
	 * one dereferences 0xd19766cde000002c. */
	NSString *tagged[] = { @"x", @"ab", @"hello", @"tagged", @"a somewhat longer literal string" };

	for (size_t i = 0; i < sizeof tagged / sizeof tagged[0]; i++) {
		check(CFStringGetLength((CFStringRef)tagged[i]) == (CFIndex)[tagged[i] length],
		      "tagged pointer %s: CF length %ld vs ObjC length %ld (%s)",
		      [tagged[i] UTF8String], (long)CFStringGetLength((CFStringRef)tagged[i]),
		      (long)[tagged[i] length], class_getName(object_getClass(tagged[i])));

		/* **AND THE RUNTIME'S OWN REFCOUNT DOOR HAS TO DECODE ONE TOO, WHICH IS A DIFFERENT PATH FROM THE
		 * BRIDGE'S AND WAS NOT COVERED BY IT.** `NSObject -retainCount` hands the pointer straight to
		 * `object_getRetainCount_np`, and that door read the word BEFORE the object without asking whether the
		 * object was dereferenceable at all — so `[@"x" retainCount]` SEGFAULTED while `[@"x" length]`,
		 * `[@"x" retain]` and `[@"x" release]` were all fine, because every one of those settles the
		 * small-object case first (`isPersistentObject` answers YES for a tagged pointer, which is why the check
		 * has to come BEFORE any dereference: there is no isa to read).
		 *
		 * THE TWO CLAIMS ARE THAT IT ANSWERS AT ALL AND THAT IT NEVER MOVES. A tagged pointer is never
		 * released, so its count is the SATURATED one — `0x7ffffffffffffffe`, Apple's own reading of retainCount
		 * for a constant string — and a retain cannot change it. Measured before the fix: SIGSEGV, in
		 * `object_getRetainCount_np`, on the first of these literals. */
		{
			unsigned long before = (unsigned long)[tagged[i] retainCount];
			unsigned long after;

			[tagged[i] retain];
			after = (unsigned long)[tagged[i] retainCount];
			check(before > 1000 && after == before,
			      "tagged pointer %s: retainCount %lu, then %lu after a retain — a never-released object "
			      "answers the saturated count and does not move",
			      [tagged[i] UTF8String], before, after);
		}
	}
}

static void reg_cfstr(void)
{
	/* clang's constant, whose isa is a BARE SYMBOL that libagora-base's NSCFConstantString is aliased
	 * to; its layout is clang's and not the runtime's, which is why it is a second class. */
	check(CFStringGetLength(CFSTR("x")) == 1, "CFSTR(\"x\") length %ld", (long)CFStringGetLength(CFSTR("x")));
	check([(NSString *)CFSTR("x") length] == 1, "[CFSTR(\"x\") length] %ld", (long)[(NSString *)CFSTR("x") length]);
	check(CFStringGetLength(CFSTR("")) == 0, "CFSTR(\"\") length %ld", (long)CFStringGetLength(CFSTR("")));
	check(CFEqual(CFSTR("x"), (CFStringRef)@"x"), "CFEqual(CFSTR(\"x\"), @\"x\") is false");

	/* **AND THE INVARIANT EVERY OTHER DISPATCH GUARD IN CORE FOUNDATION RESTS ON: THE CONSTANT'S CLASS HAS A
	 * NAME.** `_CFIsAnObject` refuses an object whose class has no name — which is exactly what a ZEROED
	 * constant-string placeholder looks like — so this single fact decides whether a CFSTR is handed to
	 * Objective-C or kept away from it, and it is the FIRST thing to break when `libagora-core` is loaded before
	 * `libagora-base`. MEASURED BOTH WAYS:
	 *
	 *     Foundation first (every binary in this tree)   class_getName -> NSCFConstantString
	 *     Core Foundation first (an ad-hoc probe)        class_getName -> NULL, and objc_retain SEGFAULTS
	 *
	 * The two `-length` cases above already pass only BECAUSE this holds; this case says so, so that a link-order
	 * change arrives as a named failure rather than as a crash four layers away in a dictionary comparison. */
	check(class_getName(object_getClass((id)CFSTR("x"))) != NULL,
	      "the constant's class has NO NAME, so Core Foundation's own guards will not treat a CFSTR as an object");
}

static void reg_singletons(void)
{
	/* Core Foundation's own statics have no isa at all -- 0 -- and must survive both the CF doors and
	 * CFRetain/CFRelease without being mistaken for objects.
	 *
	 * NOT kCFAllocatorDefault, AND THIS TEST HAD IT WRONG: that symbol IS NULL (CFBase.c: "the default
	 * allocator is the NULL allocator"), so asking for its type id is CFGetTypeID(NULL) and retaining it
	 * is CFRetain(NULL) -- a segfault and a HALT, both correct and both about the sentinel rather than
	 * about the bridge. CFAllocatorGetDefault() is the real object. A test that passes NULL is testing
	 * NULL. */
	CFTypeRef singles[] = { kCFBooleanTrue, kCFBooleanFalse, kCFNull, (CFTypeRef)CFAllocatorGetDefault() };

	for (size_t i = 0; i < sizeof singles / sizeof singles[0]; i++) {
		CFRetain(singles[i]);
		CFRelease(singles[i]);
		check(CFGetTypeID(singles[i]) != 0, "singleton %zu has no type id", i);
	}
	check(CFBooleanGetValue(kCFBooleanTrue) == true, "kCFBooleanTrue is not true");
}

static void reg_native(void)
{
	/* Registering NSString/NSArray made CF's own objects wear Foundation's classes, so
	 * CFArrayAppendValue dispatched into an immutable NSArray. */
	CFMutableArrayRef native = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

	CFArrayAppendValue(native, CFSTR("a"));
	CFArrayAppendValue(native, CFSTR("b"));
	check(CFArrayGetCount(native) == 2, "native mutable array count %ld", (long)CFArrayGetCount(native));
	check(CFArrayGetValueAtIndex(native, 0) != NULL, "native mutable array element is NULL");
	/* THIS ASSERTED THE OPPOSITE UNTIL THE BRIDGE CHANGED IT. `object_getClass(native) == nil` was true
	 * when a Core Foundation object wore NO class at all -- and it wore none because wearing FOUNDATION
	 * class made CFArrayAppendValue dispatch into an immutable NSArray. The answer is Core Foundation OWN
	 * class, which is what it has now, so the assertion tested an implementation detail the bridge was
	 * supposed to CHANGE. THE FIFTH TEST ERROR THIS SUITE HAS HAD, and the first that was wrong by being
	 * right when it was written. */
	check(object_getClass((id)native) != nil, "a Core Foundation array has no class at all");
	check([(id)native count] == 2, "a native array answers -count with %ld, want 2", (long)[(id)native count]);
	CFRelease(native);
}

static void reg_foundation(void)
{
	/* The other direction, which is what toll-free means: a FOUNDATION object driven through the Core
	 * Foundation C API. */
	NSMutableArray *host = [NSMutableArray array];
	NSMutableString *ms = [NSMutableString stringWithString:@"abc"];

	CFArrayAppendValue((CFMutableArrayRef)host, @"one");
	CFArrayAppendValue((CFMutableArrayRef)host, @"two");
	check([host count] == 2, "Foundation array after CF appends: %ld", (long)[host count]);
	check(CFArrayGetCount((CFArrayRef)host) == 2, "CF count after CF appends: %ld",
	      (long)CFArrayGetCount((CFArrayRef)host));

	/* IDENTITY, NOT CONVERSION: the CF door and the ObjC method are the same object, so a mutation
	 * through one is visible through the other. */
	check(CFArrayGetValueAtIndex((CFArrayRef)host, 0) == [host objectAtIndex:0],
	      "the same element is not the same object");

	[ms appendString:@"de"];
	check(CFStringGetLength((CFStringRef)ms) == 5, "mutable string length via CF: %ld",
	      (long)CFStringGetLength((CFStringRef)ms));
}

static void reg_equality(void)
{
	/* The bridge at its most dangerous: a CF-native and a Foundation object compared by CFEqual must
	 * agree when their content does. */
	CFStringRef c1 = CFStringCreateWithCString(NULL, "same", kCFStringEncodingUTF8);

	check(CFEqual(c1, (CFStringRef)@"same"), "CFEqual(CFString, NSString) is false");
	check(CFHash(c1) == CFHash((CFStringRef)@"same"), "CFHash disagrees across the bridge");
	CFRelease(c1);
}

/* THE REFERENCE COUNT IS CORE FOUNDATION'S, AND THIS GROUP MEASURES IT RATHER THAN TRUSTING IT.
 *
 * WHY IT HAS TO BE MEASURED: libobjc2 keeps ITS retain count at ((uintptr_t *)obj)[-1], and for a
 * CFRuntime allocation that word is the MALLOC CHUNK HEADER. So a CF object retained through the
 * Objective-C count does not merely leak -- it rewrites the allocator's metadata (measured: 0x41 -> 0x42
 * under CFRetain -> 0x41 under CFRelease, on CFArray, CFString, CFData, CFDictionary and CFSet alike),
 * and Core Foundation's own count is never touched, so nothing Core Foundation made was ever freed. Both
 * doors were wrong in the same way and neither produced a wrong ANSWER, which is why the suite reported
 * 48 of 51 while this was true: every case above drives a Core Foundation door and reads a value, and no
 * case looked at the word the allocator owns.
 *
 * THE WORD IS READ, NOT COMPARED TO A CONSTANT: its VALUE is the allocator's business (0x41, 0x31, 0x51
 * -- a chunk size with the low bits used as flags), so the assertion is that the two counts leave it
 * ALONE. */
static void reg_reference_count(void)
{
	struct { const char *name; CFTypeRef obj; } cases[5];
	size_t i;

	cases[0].name = "CFArray";
	cases[0].obj = (CFTypeRef)CFArrayCreate(kCFAllocatorDefault, NULL, 0, &kCFTypeArrayCallBacks);
	cases[1].name = "CFString";
	cases[1].obj = (CFTypeRef)CFStringCreateWithCString(NULL, "x", kCFStringEncodingUTF8);
	cases[2].name = "CFData";
	cases[2].obj = (CFTypeRef)CFDataCreate(NULL, (const UInt8 *)"x", 1);
	cases[3].name = "CFDictionary";
	cases[3].obj = (CFTypeRef)CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks,
						     &kCFTypeDictionaryValueCallBacks);
	cases[4].name = "CFSet";
	cases[4].obj = (CFTypeRef)CFSetCreate(NULL, NULL, 0, &kCFTypeSetCallBacks);

	for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
		uintptr_t before, afterCF, afterObjC;

		if (cases[i].obj == NULL) {
			check(0, "%s: could not be made", cases[i].name);
			continue;
		}
		before = ((const uintptr_t *)cases[i].obj)[-1];

		CFRetain(cases[i].obj);
		CFRelease(cases[i].obj);
		afterCF = ((const uintptr_t *)cases[i].obj)[-1];

		[(id)cases[i].obj retain];
		[(id)cases[i].obj release];
		afterObjC = ((const uintptr_t *)cases[i].obj)[-1];

		check(before == afterCF,
		      "%s: CFRetain/CFRelease moved the word before the object (%#lx -> %#lx)",
		      cases[i].name, (unsigned long)before, (unsigned long)afterCF);
		check(before == afterObjC,
		      "%s: -retain/-release moved the word before the object (%#lx -> %#lx)",
		      cases[i].name, (unsigned long)before, (unsigned long)afterObjC);
	}

	/* AND THE COUNT THAT DOES MOVE IS CORE FOUNDATION'S OWN, which is the other half: a function that
	 * changed no count at all would pass the checks above. */
	{
		CFMutableArrayRef a = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
		CFIndex fresh = CFGetRetainCount(a);

		CFRetain(a);
		check(CFGetRetainCount(a) == fresh + 1, "CFRetain did not raise the Core Foundation count");
		[(id)a retain];
		check(CFGetRetainCount(a) == fresh + 2, "-retain did not raise the Core Foundation count");
		[(id)a release];
		CFRelease(a);
		CFRelease(a);	/* the count it was created with */
	}
}

/* AND THE THIRD DOOR OF THE SAME FAMILY, WHICH IS THE ONE THAT CANNOT BE ANSWERED WITH A COUNT: -autorelease.
 *
 * WHY IT NEEDS ITS OWN GROUP. libobjc2's autorelease() asks three questions in order -- the runtime's pool
 * flag, then objc_class_flag_fast_arc, and if both are no it SENDS -autorelease TO THE OBJECT. A Core
 * Foundation-owned class cannot take the second flag (that flag is what puts the retain count back in the
 * malloc chunk header -- see reg_reference_count above), so the object is answering a message the runtime
 * sent because it does not know how to autorelease it. Calling objc_autorelease from that method is a
 * message back to that method, and it was written that way first: a stack that ran away rather than a
 * wrong count.
 *
 * THE FIRST CHECK BELOW IS THAT CASE, and it has to run FIRST: no pool exists yet in this child, so
 * useARCAutoreleasePool is still NO when the message arrives. It passes only if the implementation primes
 * that flag (an empty push and pop) before deferring.
 *
 * THE SECOND IS THE SEMANTIC, and it is the one that can be WRONG rather than fatal: inside a pool that
 * then drains, the deferred release must actually arrive -- at Core Foundation's count, since that is the
 * count this object has. Against the previous implementation (which answered CFAutorelease, a stub that
 * returns its argument) the object was simply never in the pool and this count stayed at 2. */
static void reg_autorelease(void)
{
	CFStringRef s = CFStringCreateWithCString(NULL, "autoreleased", kCFStringEncodingUTF8);
	NSAutoreleasePool *pool;

	check(s != NULL, "the string could not be made");
	if (s == NULL) {
		return;
	}

	/* NO POOL YET: this is the call that used to run the stack away. */
	[(id)s autorelease];
	check(CFGetRetainCount(s) == 1, "an autorelease outside any pool changed the count to %ld",
	      (long)CFGetRetainCount(s));

	/* AND INSIDE ONE, THE DRAIN IS WHERE THE RELEASE ARRIVES. */
	CFRetain(s);
	check(CFGetRetainCount(s) == 2, "CFRetain did not raise the count to 2");
	pool = [[NSAutoreleasePool alloc] init];
	[(id)s autorelease];
	[pool drain];
	check(CFGetRetainCount(s) == 1, "the pool's drain did not deliver the release: count is %ld, want 1",
	      (long)CFGetRetainCount(s));

	CFRelease(s);
}

/* A CORE FOUNDATION TYPE FOUNDATION NEVER BRIDGES STILL WEARS A CLASS, AND THAT IS NEW.
 *
 * WHAT WAS WRONG: _CFRuntimeCreateInstance gave an isa only to a type Foundation had registered a class
 * for. Every other type -- CFUUID, CFBitVector, CFTree, and every CoreText font and CoreGraphics colour
 * space -- came back with isa == 0. Zero is not an object to libobjc2: objc_retain reads obj->isa BEFORE
 * it decides whether to send -retain, so a null isa walks into the malloc chunk header. MEASURED, and
 * this is what the case is for: [NSDictionary setObject:forKey:] with a CTFontRef value died in
 * objc_test_class_flag <- objc_retain. Apple gives every CF type a class, __NSCFType when it has none of
 * its own; Core Foundation now makes the same one.
 *
 * THE ASSERTIONS ARE THE THREE THINGS THAT WERE BROKEN, in the order a consumer meets them: the object
 * has a class; Foundation can HOLD it (which is the objc_retain path, and the one that crashed); and Core
 * Foundation still owns the reference count, so -retain/-release reach CFRetain/CFRelease rather than the
 * allocator's word. A Core Foundation door is driven last, to show the class did not divert dispatch. */
static void reg_unbridged_type(void)
{
	CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
	NSArray *held;
	CFStringRef text;
	CFIndex base;
	uintptr_t before;

	check(uuid != NULL, "CFUUIDCreate returned NULL");
	if (uuid == NULL) {
		return;
	}

	/* ONE: A CLASS AT ALL. */
	check(object_getClass((id)uuid) != nil, "an unbridged Core Foundation type has no class at all");
	check(class_getName(object_getClass((id)uuid)) != NULL, "the unbridged object's class has no name");
	check(CFGetTypeID((CFTypeRef)uuid) == CFUUIDGetTypeID(),
	      "an unbridged Core Foundation object answered the wrong type id");

	/* TWO: FOUNDATION CAN HOLD IT. This is the crash. */
	held = [[NSArray alloc] initWithObjects:(id)uuid, nil];
	check([held count] == 1, "an unbridged Core Foundation object could not be held by an NSArray");
	check([held objectAtIndex:0] == (id)uuid, "the NSArray did not give the object back");
	[held release];

	/* THREE: AND CORE FOUNDATION OWNS THE COUNT. -retain must not touch the word before the object, and
	 * the count it moves must be Core Foundation's. MEASURED AGAINST A BASELINE, NOT 1: CFUUID UNIQUES
	 * ITS UUIDS (__CFUUIDAddUniqueUUIDHasLock) and the table holds a reference, so a fresh CFUUIDCreate
	 * comes back with a count of 2 -- the caller's and the table's. Asserting 1 here was this suite's
	 * SIXTH false failure, and the class change did not cause it: the base count was 2 even while the
	 * object had no class at all. */
	before = ((const uintptr_t *)uuid)[-1];
	base = CFGetRetainCount((CFTypeRef)uuid);
	[(id)uuid retain];
	check(((const uintptr_t *)uuid)[-1] == before,
	      "-retain on an unbridged object moved the allocator's word (%#lx -> %#lx)",
	      (unsigned long)before, (unsigned long)((const uintptr_t *)uuid)[-1]);
	check(CFGetRetainCount((CFTypeRef)uuid) == base + 1,
	      "-retain did not raise the Core Foundation count: %ld, want %ld",
	      (long)CFGetRetainCount((CFTypeRef)uuid), (long)(base + 1));
	[(id)uuid release];
	check(CFGetRetainCount((CFTypeRef)uuid) == base,
	      "-release did not restore the Core Foundation count: %ld, want %ld",
	      (long)CFGetRetainCount((CFTypeRef)uuid), (long)base);

	/* AND A CORE FOUNDATION DOOR STILL REACHES CORE FOUNDATION, not a Foundation method that would not
	 * know CFUUID's storage. */
	text = CFUUIDCreateString(kCFAllocatorDefault, uuid);
	check(text != NULL, "CFUUIDCreateString failed on an unbridged object");
	if (text != NULL) {
		check(CFStringGetLength(text) == 36, "the UUID string is not 36 characters: %ld",
		      (long)CFStringGetLength(text));
		CFRelease(text);
	}

	CFRelease(uuid);
}

/* **THE HYPHENATION RESOURCE, WHICH IS CORE FOUNDATION'S AND WAS DECLARED AND NOT DEFINED UNTIL NOW.**
 * `CFStringGetHyphenationLocationBeforeIndex` and `CFStringIsHyphenationAvailableForLocale` are the pair
 * `NSLayoutManager` reads `NSParagraphStyle -hyphenationFactor` through, and `libagora-core/CFHyphenation.c`
 * records why the data is READ FROM THE SYSTEM rather than vendored (the Debian en_US patterns are
 * GPL/LGPL/MPL, so they cannot be copied into this MIT tree, and Apple's own availability door is documented
 * to answer FALSE for a locale whose data is absent — a lookup that can fail is the contract).
 *
 * **THE EXPECTATIONS ARE WRITTEN THE WAY A DICTIONARY WRITES THEM, AND THEY ARE THE DICTIONARY'S OWN
 * ANSWERS.** Each word is spelled with the breaks this machine's `hyph_en_US.dic` derives through its own
 * patterns — "matter" is `.ma4t3t2`, which forbids "ma|tter" with an even 4, ALLOWS "mat|ter" with an odd 3
 * and forbids "matt|er" with 2 — and the case recovers the INDICES from the hyphenated spelling rather than
 * restating them, so the expectation cannot drift from the word it describes. **`computer` IS THE CASE THAT
 * SHOWS THE FILE'S MINIMA WORKING**: it breaks at 3 and NOWHERE ELSE, because `RIGHTHYPHENMIN 3` forbids the
 * "comput|er" break that would leave only two characters.
 *
 * AND THE ONE FAMILY THIS TIER COULD NOT SETTLE IS ASSERTED NOWHERE. The dictionary's `ad` patterns
 * contradict each other under Liang's maximum rule (`.ad1d4` allows "ad|d" and forbids "add|", `ad4d1in` the
 * reverse), so "adder", "adding" and "added" come out with no break at all — words every English dictionary
 * breaks. That is recorded at length in `CFHyphenation.c` and deliberately left out of this table, because a
 * guess written as an expectation is worse than a gap that is named. */
static void d_hyphenation(void)
{
	static const struct { const char *word; const char *hyphenated; } cases[] = {
		{ "hyphenation", "hy-phen-ation" },
		{ "representation", "rep-re-sen-ta-tion" },
		{ "internationalization", "in-ter-na-tion-al-iza-tion" },
		{ "typography", "ty-pog-ra-phy" },
		/* **AMERICAN, AND THAT IS THE POINT OF THIS ROW.** The en_US dictionary's `n2a2r` forbids the n|a gap, so
		 * the answer is Merriam-Webster's "dic-tio-nary" and NOT the British "dic-tion-ary" — a wrong hand-written
		 * expectation of exactly that kind is what this table caught, which is why the expectation is spelled the way
		 * a dictionary spells it rather than written as indices. */
		{ "dictionary", "dic-tio-nary" },
		{ "algorithm", "al-go-rithm" },
		{ "necessary", "nec-es-sary" },
		{ "associate", "as-so-ciate" },
		{ "progressive", "pro-gres-sive" },
		{ "breakable", "break-able" },
		{ "aardvark", "aard-vark" },
		{ "computer", "com-puter" },
		{ "matter", "mat-ter" },
		{ "letter", "let-ter" },
		{ "running", "run-ning" },
		{ "bigger", "big-ger" },
		{ "sudden", "sud-den" },
		{ "kitten", "kit-ten" },
		{ "bottle", "bot-tle" },
		{ "table", "ta-ble" },
		{ "zebra", "ze-bra" },
		{ "ox", "ox" },
		/* **AND THE THREE WORDS THE `ad` FAMILY DERIVES NOTHING FOR, WHICH ARE NOW ASSERTED RATHER THAN NAMED.**
		 * `.ad1d4`/`ad1d4`/`d1d4` put 1 at the "ad|d" gap and 4 at the "add|" gap while `ad4d1in` puts 4 at "ad|d"
		 * and 1 at "add|i", so the maximum forbids BOTH and no break comes out — which is not what English
		 * dictionaries print. That looked like this tier's mistake until an INDEPENDENT implementation of Liang
		 * was run over the same data: `pyphen` 0.18.1 answers [] for all three, and so does the same
		 * implementation over pyphen's OWN bundled copy of the en_US patterns — a different file of a different
		 * size. The data says this, so the case says it too, and a word with no hyphenation point is spelled in
		 * this table as itself, exactly as `ox` is. The family is not uniformly unbroken: `address` breaks
		 * "ad-dress", and that row is here so a reader can see the difference. */
		{ "adder", "adder" },
		{ "adding", "adding" },
		{ "added", "added" },
		{ "address", "ad-dress" },
	};
	CFLocaleRef locale = CFLocaleCreate(kCFAllocatorDefault, CFSTR("en_US"));
	size_t i;
	int agreed = 0;

	check(locale != NULL, "the en_US locale could not be made");
	if (locale == NULL) {
		return;
	}
	/* **THE AVAILABILITY DOOR IS ASKED FIRST, AND THE ABSENT CASE IS A CASE.** Apple documents this door as the
	 * way to find out whether there is data at all, so a machine without `hyph_en_US.dic` must be able to run
	 * this suite: the case then asserts the same FACT from the other side — a locale with no data answers
	 * kCFNotFound — and says so rather than failing. */
	if (!CFStringIsHyphenationAvailableForLocale(locale)) {
		CFStringRef word = CFStringCreateWithCString(kCFAllocatorDefault, "hyphenation", kCFStringEncodingUTF8);

		printf("  (note: no en_US hyphenation dictionary on this machine; asserting the absent case only)\n");
		check(CFStringGetHyphenationLocationBeforeIndex(word, 11, CFRangeMake(0, 11), 0, locale, NULL) == kCFNotFound,
		      "an unavailable locale must answer kCFNotFound");
		if (word != NULL) {
			CFRelease(word);
		}
		CFRelease(locale);
		return;
	}
	for (i = 0; i < sizeof cases / sizeof cases[0]; i++) {
		CFStringRef word = CFStringCreateWithCString(kCFAllocatorDefault, cases[i].word, kCFStringEncodingUTF8);
		CFIndex expected[8], expectedCount = 0;
		CFIndex found[8], foundCount = 0;
		CFIndex letters = 0, cursor, k;
		UTF32Char hyphen = 0;

		if (word == NULL) {
			check(0, "the word %s could not be made", cases[i].word);
			continue;
		}
		/* THE EXPECTATION, RECOVERED FROM THE HYPHENATED SPELLING rather than restated as numbers. */
		for (k = 0; cases[i].hyphenated[k] != '\0'; k++) {
			if (cases[i].hyphenated[k] == '-') {
				if (expectedCount < 8) {
					expected[expectedCount++] = letters;
				}
			} else {
				letters++;
			}
		}
		/* AND THE ANSWER, WALKED BACKWARDS THE WAY A LAYOUT WOULD: each call finds the last break before the
		 * index it is given, so asking again at the answer gives the one before that. */
		cursor = CFStringGetLength(word);
		while (foundCount < 8) {
			CFIndex at = CFStringGetHyphenationLocationBeforeIndex(word, cursor, CFRangeMake(0, cursor), 0,
								      locale, &hyphen);

			if (at == kCFNotFound) {
				break;
			}
			found[foundCount++] = at;
			cursor = at;
		}
		/* `found` runs the way the walk did, which is BACKWARDS, so it is compared from its far end. */
		if (foundCount != expectedCount) {
			check(0, "%s: %ld breaks, expected %ld", cases[i].word, (long)foundCount, (long)expectedCount);
		} else {
			Boolean same = true;

			for (k = 0; k < expectedCount; k++) {
				if (found[expectedCount - 1 - k] != expected[k]) {
					same = false;
				}
			}
			check(same, "%s did not break as %s", cases[i].word, cases[i].hyphenated);
			if (same) {
				agreed++;
			}
		}
		/* **AND THE HYPHEN IT SUGGESTS IS U+2010**, which Apple's header leaves as "the suggested hyphen character"
		 * and this tier records as its choice; a run with no breaks must not have set it. */
		if (foundCount > 0) {
			check(hyphen == 0x2010, "%s suggested U+%04X rather than U+2010", cases[i].word, (unsigned)hyphen);
		}
		CFRelease(word);
	}
	printf("  (hyphenation: %d of %d words broke exactly as hyph_en_US.dic says)\n",
	       agreed, (int)(sizeof cases / sizeof cases[0]));
	/* **THE SOFT HYPHEN: THE AUTHOR'S OWN BREAK, AND THE DICTIONARY'S ANSWERS SHIFT BY IT.** U+00AD is not a
	 * character any pattern could match, so it comes out of the word the dictionary sees and stays a candidate
	 * of its own — which is why "hy\u00ADphenation" answers 2 (the soft hyphen's index), 3 and 7: the other two
	 * are "hy-phen-ation"'s own 2 and 6, MOVED by the character that now sits between them. */
	{
		CFStringRef soft = CFStringCreateWithCString(kCFAllocatorDefault, "hy\xC2\xADphenation", kCFStringEncodingUTF8);
		CFIndex at;

		check(soft != NULL && CFStringGetLength(soft) == 12, "the soft-hyphen word is not twelve characters");
		if (soft != NULL) {
			at = CFStringGetHyphenationLocationBeforeIndex(soft, 12, CFRangeMake(0, 12), 0, locale, NULL);
			check(at == 7, "the last break before the end of a soft-hyphenated word is 7, not %ld", (long)at);
			at = CFStringGetHyphenationLocationBeforeIndex(soft, 3, CFRangeMake(0, 12), 0, locale, NULL);
			check(at == 2, "a soft hyphen is a break of its own at index 2, not %ld", (long)at);
			CFRelease(soft);
		}
	}
	/* AND THE TWO WAYS A CALLER AVOIDS THE DOOR'S WORK: a location whose predecessor is not a letter has no
	 * hyphenation point before it, and a capitalised word is folded to the dictionary's own case. */
	{
		CFStringRef spaced = CFStringCreateWithCString(kCFAllocatorDefault, "hyphenation ", kCFStringEncodingUTF8);
		CFStringRef capital = CFStringCreateWithCString(kCFAllocatorDefault, "Hyphenation", kCFStringEncodingUTF8);

		check(CFStringGetHyphenationLocationBeforeIndex(spaced, 12, CFRangeMake(0, 12), 0, locale, NULL) == kCFNotFound,
		      "a location after a space has no hyphenation point before it");
		check(CFStringGetHyphenationLocationBeforeIndex(capital, 11, CFRangeMake(0, 11), 0, locale, NULL) == 6,
		      "a capitalised word is folded, so `Hyphenation` breaks like `hyphenation`");
		if (spaced != NULL) {
			CFRelease(spaced);
		}
		if (capital != NULL) {
			CFRelease(capital);
		}
	}
	/* **THE CONTRACT'S OWN REFUSALS**, each named in the header as a case the door must survive: an empty limit
	 * range "generates no hyphen location", and a location of 0 has nothing before it by definition. */
	{
		CFStringRef word = CFStringCreateWithCString(kCFAllocatorDefault, "hyphenation", kCFStringEncodingUTF8);

		check(CFStringGetHyphenationLocationBeforeIndex(word, 11, CFRangeMake(5, 0), 0, locale, NULL) == kCFNotFound,
		      "an empty limit range generates no hyphen location");
		check(CFStringGetHyphenationLocationBeforeIndex(word, 0, CFRangeMake(0, 11), 0, locale, NULL) == kCFNotFound,
		      "a location of 0 has no hyphenation point before it");
		check(CFStringGetHyphenationLocationBeforeIndex(word, 11, CFRangeMake(3, 8), 0, locale, NULL) == 6,
		      "a limit range's location is the earliest index the door may answer with");
		/* **AND ITS END IS A CEILING, WHICH IS THE HALF OF `limitRange` THAT WAS WRONG UNTIL A DOOR ABOVE THIS ONE
		 * WAS TESTED.** Apple calls `limitRange` "the range of characters within the string to search", so an
		 * answer outside it is not an answer; treating it as a floor alone told a caller about the break at 6 when
		 * the caller's range ended at 6. */
		check(CFStringGetHyphenationLocationBeforeIndex(word, 11, CFRangeMake(0, 6), 0, locale, NULL) == 2,
		      "a limit range's END is a ceiling: a range ending at 6 cannot be told about the break at 6");
		if (word != NULL) {
			CFRelease(word);
		}
	}
	/* AND A LOCALE WITH NO DICTIONARY AT ALL, which is the answer the availability door promises. `xx_ZZ` can
	 * never name a file, so this asserts the ABSENT branch without depending on which languages a machine has. */
	{
		CFLocaleRef bogus = CFLocaleCreate(kCFAllocatorDefault, CFSTR("xx_ZZ"));
		CFStringRef word = CFStringCreateWithCString(kCFAllocatorDefault, "hyphenation", kCFStringEncodingUTF8);

		if (bogus != NULL) {
			check(!CFStringIsHyphenationAvailableForLocale(bogus), "xx_ZZ must report no hyphenation data");
			check(CFStringGetHyphenationLocationBeforeIndex(word, 11, CFRangeMake(0, 11), 0, bogus, NULL) == kCFNotFound,
			      "and must answer kCFNotFound");
			CFRelease(bogus);
		}
		if (word != NULL) {
			CFRelease(word);
		}
	}
	CFRelease(locale);
}

static const struct { const char *name; void (*fn)(void); } g_regressions[] = {
	{ "regression: the class cluster",        reg_cluster },
	{ "regression: tagged pointers",          reg_tagged },
	{ "regression: CFSTR",                    reg_cfstr },
	{ "regression: the singletons",           reg_singletons },
	{ "regression: a native Core Foundation object", reg_native },
	{ "regression: Foundation through CF",    reg_foundation },
	{ "regression: equality across the bridge", reg_equality },
	{ "regression: whose reference count",    reg_reference_count },
	{ "regression: autorelease of a CF object", reg_autorelease },
	{ "regression: a type Foundation never bridges", reg_unbridged_type },
};

/* ------------------------------------------------------------------------ */
/* the door table: MANY doors per type, not one                              */
/* ------------------------------------------------------------------------ */

/* THE FIRST VERSION OF THIS SUITE TESTED ONE DOOR PER TYPE, AND THAT WAS THE LIMIT OF IT. The
 * registrations were measured, not the contract: CFTimeZoneGetName passed while three other CFTimeZone
 * accessors segfaulted, and CFURLGetString passed while five other CFURL doors threw
 * '-[NSURL _cfurl] is not implemented'. A scan for doors that validate a CF type without dispatching
 * found twenty-four candidates; these are the ones that are not creation doors, and each runs in its own
 * child so one crash costs one door.
 *
 * THE SUSPECTS WITH NO ENTRY HERE, AND WHY: CFErrorCreate, CFErrorCreateWithUserInfoKeysAndValues,
 * CFLocaleCreate, CFTimeZoneCreate and its variants, CFTimeZoneSetDefault and
 * CFTimeZoneSetAbbreviationDictionary. Every one of them CREATES a Core Foundation object or sets a
 * global; none of them is handed a Foundation object to bridge, so the scan's own heuristic is what
 * flagged them. */
static void cb_count(const void *value, void *ctx) { (void)value; (*(int *)ctx)++; }

static void d_array_apply(void)
{
	NSArray *a = @[ @1, @2 ];
	int n = 0;

	CFArrayApplyFunction((CFArrayRef)a, CFRangeMake(0, 2), cb_count, &n);
	printf("    = %d (want 2)\n", n);
}

static void d_data_find(void)
{
	NSData *b = [NSData dataWithBytes:"hello" length:5];
	NSData *n = [NSData dataWithBytes:"ll" length:2];
	CFRange r = CFDataFind((CFDataRef)b, (CFDataRef)n, CFRangeMake(0, 5), 0);

	printf("    = {%ld,%ld} (want {2,2})\n", (long)r.location, (long)r.length);
}

/* CFDictionaryGetKeyIfPresent HAS NO ENTRY: the scan flagged it, but it is declared nowhere in
 * Core Foundation's public headers -- so it is not a door a caller can reach, and a bridge test is about
 * the doors callers reach. That is the scan's heuristic showing its edges, not a defect. */

static void d_tz_seconds(void)
{
	NSTimeZone *z = [NSTimeZone timeZoneWithName:@"UTC"];

	printf("    = %g\n", (double)CFTimeZoneGetSecondsFromGMT((CFTimeZoneRef)z, 0.0));
}

static void d_tz_abbrev(void)
{
	NSTimeZone *z = [NSTimeZone timeZoneWithName:@"UTC"];
	CFStringRef s = CFTimeZoneCopyAbbreviation((CFTimeZoneRef)z, 0.0);

	printf("    = %s\n", s ? [(NSString *)s UTF8String] : "(null)");
	if (s) CFRelease(s);
}

static void d_tz_isdst(void)
{
	NSTimeZone *z = [NSTimeZone timeZoneWithName:@"UTC"];

	printf("    = %d\n", (int)CFTimeZoneIsDaylightSavingTime((CFTimeZoneRef)z, 0.0));
}

static void d_url_path(void)
{
	CFStringRef p = CFURLCopyPath((CFURLRef)[NSURL URLWithString:@"http://example.com/a/b"]);

	printf("    = %s (want /a/b)\n", p ? [(NSString *)p UTF8String] : "(null)");
	if (p) CFRelease(p);
}

static void d_url_hasdir(void) { printf("    = %d\n", (int)CFURLHasDirectoryPath((CFURLRef)[NSURL URLWithString:@"http://example.com/a/"])); }
static void d_url_decomp(void) { printf("    = %d\n", (int)CFURLCanBeDecomposed((CFURLRef)[NSURL URLWithString:@"http://example.com/a"])); }

static void d_url_netloc(void)
{
	CFStringRef s = CFURLCopyNetLocation((CFURLRef)[NSURL URLWithString:@"http://example.com/a"]);

	printf("    = %s (want example.com)\n", s ? [(NSString *)s UTF8String] : "(null)");
	if (s) CFRelease(s);
}

static void d_url_dellast(void)
{
	CFURLRef d = CFURLCreateCopyDeletingLastPathComponent(NULL, (CFURLRef)[NSURL URLWithString:@"http://example.com/a/b"]);

	printf("    = %s\n", d ? [(NSString *)CFURLGetString(d) UTF8String] : "(null)");
	if (d) CFRelease(d);
}

static void d_url_apppath(void)
{
	CFURLRef d = CFURLCreateCopyAppendingPathComponent(NULL, (CFURLRef)[NSURL URLWithString:@"http://example.com/a"], CFSTR("b"), false);

	printf("    = %s\n", d ? [(NSString *)CFURLGetString(d) UTF8String] : "(null)");
	if (d) CFRelease(d);
}

static void d_url_bytes(void)
{
	CFRange r = CFURLGetByteRangeForComponent((CFURLRef)[NSURL URLWithString:@"http://example.com/a"], kCFURLComponentPath, NULL);

	printf("    = {%ld,%ld}\n", (long)r.location, (long)r.length);
}

static void d_str_fastc(void) { printf("    = %p\n", (const void *)CFStringGetCStringPtr(CFSTR("fast"), kCFStringEncodingUTF8)); }
static void d_str_fastcontents(void) { printf("    = %p\n", (const void *)CFStringGetCharactersPtr((CFStringRef)@"fast")); }
static void d_str_lower(void) { CFStringRef s = CFStringCreateMutableCopy(NULL, 0, (CFStringRef)@"ABC"); CFStringLowercase((CFMutableStringRef)s, NULL); printf("    = %s (want abc)\n", [(NSString *)s UTF8String]); CFRelease(s); }
static void d_str_sub(void) { CFStringRef s = CFStringCreateWithSubstring(NULL, (CFStringRef)@"hello", CFRangeMake(1, 3)); printf("    = %s (want ell)\n", s ? [(NSString *)s UTF8String] : "(null)"); if (s) CFRelease(s); }

static const struct { const char *name; void (*fn)(void); } g_extra_doors[] = {
	{ "The hyphenation resource, which is Core Foundation's",        d_hyphenation },
	{ "CFArrayApplyFunction on an NSArray",                       d_array_apply },
	{ "CFDataFind on NSData",                                     d_data_find },
	{ "CFTimeZoneGetSecondsFromGMT on NSTimeZone",                d_tz_seconds },
	{ "CFTimeZoneCopyAbbreviation on NSTimeZone",                 d_tz_abbrev },
	{ "CFTimeZoneIsDaylightSavingTime on NSTimeZone",             d_tz_isdst },
	{ "CFURLCopyPath on NSURL",                                   d_url_path },
	{ "CFURLHasDirectoryPath on NSURL",                           d_url_hasdir },
	{ "CFURLCanBeDecomposed on NSURL",                            d_url_decomp },
	{ "CFURLCopyNetLocation on NSURL",                            d_url_netloc },
	{ "CFURLCreateCopyDeletingLastPathComponent on NSURL",        d_url_dellast },
	{ "CFURLCreateCopyAppendingPathComponent on NSURL",           d_url_apppath },
	{ "CFURLGetByteRangeForComponent on NSURL",                   d_url_bytes },
	{ "CFStringGetCStringPtr on a CFSTR",                         d_str_fastc },
	{ "CFStringGetCharactersPtr on an NSString",                  d_str_fastcontents },
	{ "CFStringLowercase on a mutable string built from NSString", d_str_lower },
	{ "CFStringCreateWithSubstring from an NSString",             d_str_sub },
};

static int run_one_case(const bridge_case *c)
{
	int before = g_fail;
	id obj = c->make();

	if (obj == nil) {
		check(0, "%s: the Foundation object could not be made", c->name);
		return 1;
	}
		/* EACH CASE IS CAUGHT, because a bridged door that reaches a Foundation method the class does
		 * not implement RAISES -- and an uncaught exception ends the process, which would let one
		 * missing method hide the other seventeen types. A raise is a failure like any other, and the
		 * count is the point. */
		@try {
			check(CFGetTypeID((CFTypeRef)obj) == c->typeID(),
			      "%s: CFGetTypeID is %lu, want %lu", c->name,
			      (unsigned long)CFGetTypeID((CFTypeRef)obj), (unsigned long)c->typeID());
			check(c->door(obj) != 0, "%s: the Core Foundation door did not answer", c->name);
			CFRetain((CFTypeRef)obj);
			CFRelease((CFTypeRef)obj);
			check(CFCopyDescription((CFTypeRef)obj) != NULL, "%s: CFCopyDescription is NULL", c->name);
	} @catch (NSException *e) {
		check(0, "%s: raised %s: %s", c->name,
		      [[e name] UTF8String], [[e reason] UTF8String]);
	}
	return g_fail - before;
}

/* ONE CHILD PER CASE, AND THAT IS NOT PARANOIA -- IT IS THE ONLY WAY TO SEE THE WHOLE TABLE. Three
 * different things can end a case: a wrong answer (counted), an Objective-C exception (caught below), and
 * Core Foundation's own HALT, which is SIGILL and which @try CANNOT catch. The last of those killed the
 * whole run at the seventh case, so the other eleven types were never looked at. A child costs one case
 * and the tally survives.
 *
 * THE COUNTS CANNOT CROSS THE FORK, so the child reports through its exit status and the parent counts
 * CASES. The FAIL detail lines still come from the child, on the same stderr. */
static int run_in_child(const char *name, int (*fn)(void))
{
	pid_t pid;
	int status;

	fflush(NULL);
	pid = fork();
	if (pid == 0) {
		_exit(fn() == 0 ? 0 : 1);
	}
	if (pid < 0) {
		fprintf(stderr, "FAIL: %s: fork failed\n", name);
		return 1;
	}
	if (waitpid(pid, &status, 0) < 0) {
		fprintf(stderr, "FAIL: %s: waitpid failed\n", name);
		return 1;
	}
	if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
		printf("ok   %s\n", name);
		return 0;
	}
	if (WIFSIGNALED(status)) {
		fprintf(stderr, "FAIL: %s: killed by signal %d\n", name, WTERMSIG(status));
	} else {
		fprintf(stderr, "FAIL: %s: checks failed\n", name);
	}
	return 1;
}

/* ------------------------------------------------------------------------ */
/* THE OTHER DIRECTION, WHICH NOTHING TESTED: a NATIVE Core Foundation object */
/* handed TO Foundation as an argument                                        */
/* ------------------------------------------------------------------------ */

/* UNTIL THIS GROUP EXISTED THE SUITE COULD NOT TELL THAT THE BRIDGE WAS HALF
 * BUILT. Every other case drives Core Foundation with a Foundation object; this
 * one asks the reverse, and the reverse needs a Core Foundation object to WEAR A
 * CLASS. Measured when this was written: CFString had one (__NSCFString) and
 * CFArray, CFData, CFNumber and CFDate had none, so Foundation's methods
 * segfaulted on them -- while the suite reported 41 of 41, because it never asked.
 *
 * ONE CHILD PER CASE, as everything else here, because the failure mode is a crash
 * rather than an answer. */
/* and likewise the string: -isEqual: is derived, and it can only answer if -length and
 * -characterAtIndex: reach Core Foundation. */
static void arg_cfstring(void)
{
	CFStringRef s = CFStringCreateWithCString(NULL, "same", kCFStringEncodingUTF8);
	NSString *sub;

	check([@"same" isEqual:(id)s], "a native CFString is not -isEqual: to an equal NSString");
	sub = [(id)s substringToIndex:2];
	check(sub != nil && [sub isEqualToString:@"sa"],
	      "a derived string method answered %s, want sa", sub ? [sub UTF8String] : "(nil)");
}

static void arg_cfarray(void)
{
	CFArrayRef a = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks);

	check([(id)a count] == 0, "a native CFArray answered count %ld, want 0", (long)[(id)a count]);
}

static void arg_cfdata(void)
{
	CFDataRef d = CFDataCreate(NULL, (const UInt8 *)"x", 1);
	NSData *copy = [(id)d copy];

	check([(id)d length] == 1, "a native CFData answered length %ld, want 1", (long)[(id)d length]);
	check(copy != nil && [copy length] == 1, "a derived data method failed");
}

static void arg_cfdict(void)
{
	CFDictionaryRef d = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

	check([(id)d count] == 0, "a native CFDictionary answered count %ld, want 0", (long)[(id)d count]);
}

static void arg_cfset(void)
{
	CFSetRef x = CFSetCreate(NULL, NULL, 0, &kCFTypeSetCallBacks);

	check([(id)x count] == 0, "a native CFSet answered count %ld, want 0", (long)[(id)x count]);
}

static void arg_cfnumber(void)
{
	CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, (int[]){ 7 });
	double d = [(id)n doubleValue];

	check([(id)n intValue] == 7, "a native CFNumber answered intValue %d, want 7", (int)[(id)n intValue]);
	check(d == 7.0, "a derived number method answered %g, want 7", d);
}

/* ASKING FOR A DERIVED METHOD AND NOT THE PRIMITIVE, and this case is why: it reported ok while being
 * wrong. -timeIntervalSinceReferenceDate is the primitive and can pass by coincidence -- Foundation own
 * implementation could read the same field at the same offset -- while -timeIntervalSince1970 is built
 * on it and has to go THROUGH it. Core Foundation counts from 2001, so a date at 0.0 is -978307200. */
static void arg_cfdate(void)
{
	CFDateRef d = CFDateCreate(NULL, 0.0);

	check([(id)d timeIntervalSinceReferenceDate] == 0.0,
	      "a native CFDate answered %g, want 0", (double)[(id)d timeIntervalSinceReferenceDate]);
	/* +978307200 AND NOT -978307200: Core Foundation counts from 2001 and this date is AT the 2001
	 * reference, so the 1970 domain is POSITIVE -- while the case further up uses a date at the 1970
	 * reference and correctly expects the negative. THE FOURTH TEST EXPECTATION THIS SUITE HAS HAD
	 * WRONG, and the value it printed was right: 9.78307e+08. */
	check([(id)d timeIntervalSince1970] == 978307200.0,
	      "a DERIVED date method answered %g, want +978307200", (double)[(id)d timeIntervalSince1970]);
}

static void arg_cfnull(void)
{
	check([(id)kCFNull description] != nil, "a native CFNull has no description");
}

static void arg_cfurl(void)
{
	/* THE SAME TEXT IS MADE INTO A URL TWICE, ONCE FROM A NATIVE CFString AND ONCE FROM CFSTR(), AND THE
	 * SECOND IS THE REGRESSION CASE. Core Foundation's URL parser used to record the components differently
	 * for the two: CFURLCopyHostName answered "example.com" for a URL made from CFStringCreateWithCString and
	 * NULL for one made from CFSTR, whose class is a Foundation object and whose parse therefore went through
	 * Core Foundation's Objective-C-dispatch path. THE PARSER WAS NOT AT FAULT -- measured, with temporary
	 * instrumentation, both parses produced flags=0x2001c029 with HAS_HOST set and three ranges. The byte door
	 * underneath it was: CFStringGetBytes dispatches into Foundation's
	 * -getBytes:maxLength:usedLength:encoding:options:range:remainingRange: and handed it a CFStringEncoding
	 * (kCFStringEncodingUTF8 is 0x08000100 where NSUTF8StringEncoding is 4), a number no NSStringEncoding
	 * table knows, so every bridged string converted to nothing. _retainedComponentString's
	 * UnescapeAllWithUTF8 checks that answer and returns NULL, which is where the host went.
	 *
	 * THAT DOOR NOW RE-ASKS THE CONVERSION IN CORE FOUNDATION'S NUMBERING (libagora-base/NSString.m), and
	 * this case asserts BOTH FORMS so they cannot drift apart again -- the six component questions below are
	 * asked of each. */
	CFStringRef text = CFStringCreateWithCString(NULL, "http://example.com/a/b?q=1#frag", kCFStringEncodingUTF8);
	CFStringRef fileText = CFStringCreateWithCString(NULL, "file:///tmp/x", kCFStringEncodingUTF8);
	CFURLRef u = CFURLCreateWithString(NULL, text, NULL);
	CFURLRef f = CFURLCreateWithString(NULL, fileText, NULL);
	CFURLRef bridged = CFURLCreateWithString(NULL, CFSTR("http://example.com/a/b?q=1#frag"), NULL);
	NSString *path = [(id)u path];

	check(path != nil && [path isEqualToString:@"/a/b"],
	      "a native CFURL answered path %s, want /a/b", path ? [path UTF8String] : "(nil)");

	/* AND THE SAME QUESTIONS OF THE URL BUILT FROM A BARE CFSTR. Every expectation is the one above, so a
	 * bridged string that reaches Core Foundation's byte door with an unconvertible encoding fails HERE. */
	check(bridged != NULL, "a CFURL could not be made from a CFSTR at all");
	if (bridged != NULL) {
		CFStringRef host = CFURLCopyHostName(bridged);

		check(host != NULL, "a CFSTR-built CFURL lost its host in the parser (the defect this case guards)");
		if (host != NULL) {
			check([(id)host isEqualToString:@"example.com"],
			      "a CFSTR-built CFURL answered host %s, want example.com", [(id)host UTF8String]);
			CFRelease(host);
		}
		check([[(id)bridged scheme] isEqualToString:@"http"],
		      "a CFSTR-built CFURL answered scheme %s", [[(id)bridged scheme] UTF8String] ?: "(nil)");
		check([[(id)bridged path] isEqualToString:@"/a/b"],
		      "a CFSTR-built CFURL answered path %s, want /a/b", [[(id)bridged path] UTF8String] ?: "(nil)");
		check([[(id)bridged query] isEqualToString:@"q=1"],
		      "a CFSTR-built CFURL answered query %s, want q=1", [[(id)bridged query] UTF8String] ?: "(nil)");
		check([[(id)bridged fragment] isEqualToString:@"frag"],
		      "a CFSTR-built CFURL answered fragment %s, want frag", [[(id)bridged fragment] UTF8String] ?: "(nil)");
		check([[(id)bridged absoluteString] isEqualToString:@"http://example.com/a/b?q=1#frag"],
		      "a CFSTR-built CFURL answered absoluteString %s",
		      [[(id)bridged absoluteString] UTF8String] ?: "(nil)");
	}

	/* AND THE REST OF THE PRIMITIVES, ONE LINE EACH, BECAUSE A TYPE IS NOT BRIDGED BY ITS FIRST DOOR.
	 * Twelve of them had to be written for this class -- NSURL reads ten ivars through its accessors -- and
	 * -path alone would have observed exactly one. Every expectation below is what an NSURL answers for
	 * the same string, so a door that reaches uninitialised storage, or the wrong Core Foundation door,
	 * fails here rather than in a caller's program. */
	check([[(id)u absoluteString] isEqualToString:@"http://example.com/a/b?q=1#frag"],
	      "a native CFURL answered absoluteString %s", [[(id)u absoluteString] UTF8String]);
	check([[(id)u scheme] isEqualToString:@"http"],
	      "a native CFURL answered scheme %s", [[(id)u scheme] UTF8String] ?: "(nil)");
	check([[(id)u host] isEqualToString:@"example.com"],
	      "a native CFURL answered host %s", [[(id)u host] UTF8String] ?: "(nil)");
	check([[(id)u query] isEqualToString:@"q=1"],
	      "a native CFURL answered query %s, want q=1", [[(id)u query] UTF8String] ?: "(nil)");
	check([[(id)u fragment] isEqualToString:@"frag"],
	      "a native CFURL answered fragment %s, want frag", [[(id)u fragment] UTF8String] ?: "(nil)");
	check(![(id)u isFileURL], "a native http URL says it is a file URL");
	check([(id)f isFileURL], "a native file URL says it is not a file URL");
	check([[(id)f path] isEqualToString:@"/tmp/x"],
	      "a native file URL answered path %s, want /tmp/x", [[(id)f path] UTF8String]);
	check([[(id)u relativeString] isEqualToString:@"http://example.com/a/b?q=1#frag"],
	      "a native CFURL answered relativeString %s", [[(id)u relativeString] UTF8String]);

	/* AND TEN OF THE DERIVED ONES, WHICH ARE THE HALF THAT PROVES THE BASE CLASS WAS ROUTED THROUGH THE
	 * PRIMITIVES RATHER THAN LEFT READING ITS IVARS: every one of these is computed in libagora-base out
	 * of parts that a Core Foundation object has none of. */
	check([[(id)u relativePath] isEqualToString:@"/a/b?q=1#frag"],
	      "a native CFURL answered relativePath %s", [[(id)u relativePath] UTF8String]);
	check([[(id)u resourceSpecifier] isEqualToString:@"//example.com/a/b?q=1#frag"],
	      "a native CFURL answered resourceSpecifier %s", [[(id)u resourceSpecifier] UTF8String]);
	check([[(id)u lastPathComponent] isEqualToString:@"b"],
	      "a native CFURL answered lastPathComponent %s", [[(id)u lastPathComponent] UTF8String]);
	check(![(id)u hasDirectoryPath], "a native CFURL says a file-less path is a directory");
	check([[(id)u URLByDeletingLastPathComponent] absoluteString] != nil,
	      "a native CFURL answered nothing for URLByDeletingLastPathComponent");
	check([[(id)u URLByAppendingPathComponent:@"c"] absoluteString] != nil,
	      "a native CFURL answered nothing for URLByAppendingPathComponent:");
	check([[(id)u standardizedURL] absoluteString] != nil,
	      "a native CFURL answered nothing for standardizedURL");
	check([(id)u baseURL] == nil, "a native CFURL has a base URL");
	check([[u description] isEqualToString:[f description]] == NO,
	      "two different URLs have the same description");
}

static void arg_cftz(void)
{
	CFTimeZoneRef z = CFTimeZoneCreateWithName(NULL, CFSTR("UTC"), true);
	NSString *name = [(id)z name];

	check(name != nil && [name isEqualToString:@"UTC"],
	      "a native CFTimeZone answered name %s, want UTC", name ? [name UTF8String] : "(nil)");
}

static void arg_cflocale(void)
{
	CFLocaleRef l = CFLocaleCreate(NULL, CFSTR("en_US"));
	NSString *ident = [(id)l localeIdentifier];

	check(ident != nil && [ident isEqualToString:@"en_US"],
	      "a native CFLocale answered localeIdentifier %s, want en_US", ident ? [ident UTF8String] : "(nil)");
	/* AND DERIVED DOORS, BECAUSE THIS TYPE HAS EXACTLY ONE PRIMITIVE: everything below rides on
	 * -localeIdentifier, computed in libagora-base out of ICU, so if the primitive is not the one the
	 * owned class answers these read storage a Core Foundation object does not have. */
	check([[(id)l languageCode] isEqualToString:@"en"],
	      "a native CFLocale answered languageCode %s, want en",
	      [[(id)l languageCode] UTF8String] ?: "(nil)");
	check([[(id)l countryCode] isEqualToString:@"US"],
	      "a native CFLocale answered countryCode %s, want US",
	      [[(id)l countryCode] UTF8String] ?: "(nil)");
	check([[(id)l objectForKey:NSLocaleLanguageCode] isEqualToString:@"en"],
	      "a native CFLocale answered objectForKey:NSLocaleLanguageCode %s, want en",
	      [[(id)l objectForKey:NSLocaleLanguageCode] UTF8String] ?: "(nil)");
	check([[(id)l description] isEqualToString:@"<NSLocale: en_US>"],
	      "a native CFLocale answered description %s", [[(id)l description] UTF8String] ?: "(nil)");
	check([(id)l isEqual:[NSLocale localeWithLocaleIdentifier:@"en_US"]],
	      "a native CFLocale is not -isEqual: to the NSLocale with the same identifier");
}

static void arg_cferror(void)
{
	CFErrorRef e = CFErrorCreate(NULL, CFSTR("AgoraTest"), 42, NULL);
	NSString *domain = [(id)e domain];

	check(domain != nil && [domain isEqualToString:@"AgoraTest"],
	      "a native CFError answered domain %s, want AgoraTest", domain ? [domain UTF8String] : "(nil)");
	check([(id)e code] == 42, "a native CFError answered code %ld, want 42", (long)[(id)e code]);
	check([(id)e userInfo] != nil, "a native CFError has no userInfo");
	/* DERIVED, over the three primitives: -description is composed in libagora-base out of all three. */
	check([[(id)e description] length] > 0, "a native CFError answered no description");
}

static void arg_cfattributed(void)
{
	/* THE TWO PRIMITIVES, THEN THE DOORS THE ROUTING IN libagora-base WAS FOR. The string is made WITH an
	 * attribute on it, because a run-less attributed string would not exercise the run door at all -- and
	 * "no attributes" is a case the two sides do not agree about anyway (the base class answers nil, Core
	 * Foundation answers an empty dictionary). */
	CFStringRef key = CFStringCreateWithCString(NULL, "k", kCFStringEncodingUTF8);
	CFStringRef value = CFStringCreateWithCString(NULL, "v", kCFStringEncodingUTF8);
	CFStringRef text = CFStringCreateWithCString(NULL, "hello", kCFStringEncodingUTF8);
	CFDictionaryRef attrs = CFDictionaryCreate(NULL, (const void **)&key, (const void **)&value, 1,
						   &kCFTypeDictionaryKeyCallBacks,
						   &kCFTypeDictionaryValueCallBacks);
	CFAttributedStringRef a;
	NSString *s;
	NSRange reported = NSMakeRange(999, 999);

	a = CFAttributedStringCreate(NULL, text, attrs);
	check(a != NULL, "the attributed string could not be made");
	if (a == NULL) {
		return;
	}

	/* THE PRIMITIVES. */
	s = [(id)a string];
	check(s != nil && [s isEqualToString:@"hello"],
	      "a native CFAttributedString answered string %s, want hello", s ? [s UTF8String] : "(nil)");
	check([(id)a length] == 5, "a native CFAttributedString answered length %ld, want 5",
	      (long)[(id)a length]);
	check([(id)a attributesAtIndex:0 effectiveRange:&reported] != nil,
	      "a native CFAttributedString answered no attributes at all");
	check(reported.location == 0 && reported.length == 5,
	      "the attributes at 0 apply over {%lu,%lu}, want {0,5}",
	      (unsigned long)reported.location, (unsigned long)reported.length);
	/* AND THE SAME DOOR WITH A NULL OUT-PARAMETER, which both sides allow and which the owned class must not
	 * dereference. */
	check([[[(id)a attributesAtIndex:0 effectiveRange:NULL] objectForKey:@"k"] isEqualToString:@"v"],
	      "the attribute value did not come back through a NULL effective range");

	/* AND THE FOUR DOORS THAT USED TO WALK THE RUN TABLE, which are what the libagora-base routing was for:
	 * a read, a copy, the initialiser, and the enumerator. Each would otherwise have read Core Foundation
	 * storage as if it were this class's `_runs`. */
	check([[(id)a attributedSubstringFromRange:NSMakeRange(1, 3)] string] != nil,
	      "a native CFAttributedString answered nothing for attributedSubstringFromRange:");
	check([[(id)a copy] isEqualToAttributedString:(NSAttributedString *)a],
	      "a native CFAttributedString's -copy is not equal to it");
	{
		NSMutableAttributedString *relayed =
			[[[NSMutableAttributedString alloc] initWithAttributedString:(id)a] autorelease];
		__block NSUInteger spans = 0;

		check(relayed != nil && [[relayed string] isEqualToString:@"hello"],
		      "-initWithAttributedString: did not carry the string over");
		check([relayed length] == 5, "-initWithAttributedString: carried %lu characters, want 5",
		      (unsigned long)[relayed length]);
		[(id)a enumerateAttributesInRange:NSMakeRange(0, 5) options:0
				       usingBlock:^(NSDictionary *at, NSRange r, BOOL *stop) {
			(void)at; (void)r; (void)stop;
			spans++;
		}];
		check(spans == 1, "the enumerator reported %lu spans, want 1", (unsigned long)spans);
	}
}

static void arg_cfcharset(void)
{
	/* THE TEXT IS A BARE CFSTR, AND IT USED TO HAVE TO BE A NATIVE CFString: a CFSTR reached Core
	 * Foundation's byte door through the Objective-C-dispatch path and came back converted to nothing. That
	 * is fixed at the door (libagora-base/NSString.m), so the CFSTR form is now the stronger test and is the
	 * one used. */
	CFStringRef text = CFSTR("abc");
	CFCharacterSetRef w = CFCharacterSetCreateWithCharactersInString(NULL, text);
	CFCharacterSetRef inv;
	CFMutableCharacterSetRef mut;
	NSData *bitmap;
	const unsigned char *bytes;

	check(w != NULL, "the character set could not be made");
	if (w == NULL) {
		return;
	}

	/* THE PRIMITIVES. */
	check([(id)w characterIsMember:'a'], "a native CFCharacterSet says 'a' is not a member");
	check(![(id)w characterIsMember:'z'], "a native CFCharacterSet says 'z' is a member");
	check([(id)w longCharacterIsMember:'a'], "a native CFCharacterSet says 'a' is not a member (long form)");
	check([(id)w hasMemberInPlane:0], "a native CFCharacterSet has nothing in plane 0");
	check(![(id)w hasMemberInPlane:1], "a native CFCharacterSet claims plane 1 has members");

	/* AND THE BITMAP, WHICH IS THE ONE THING THIS TYPE'S BRIDGE CHANGED THE SHAPE OF: Core Foundation's bare
	 * 8192-byte plane-0 form, with the bits in it, on BOTH sides now. */
	bitmap = [(id)w bitmapRepresentation];
	check([bitmap length] == 8192, "the bitmap is %lu bytes, want 8192", (unsigned long)[bitmap length]);
	if ([bitmap length] == 8192) {
		bytes = (const unsigned char *)[bitmap bytes];

		check((bytes['a' / 8] & (1u << ('a' % 8))) != 0, "the bitmap does not carry 'a'");
		check((bytes['z' / 8] & (1u << ('z' % 8))) == 0, "the bitmap carries 'z'");
		/* THE ROUND TRIP, which is what the format decision was for: a bitmap out of an owned set goes back
		 * in through the Foundation class method. */
		check([[NSCharacterSet characterSetWithBitmapRepresentation:bitmap] characterIsMember:'a'],
		      "a bitmap from an owned set did not come back holding 'a'");
	}

	/* AND THE TWO DOORS THAT ANSWER WITH A WHOLE SET. */
	/* **THE TWO COPIES COME BACK THROUGH THE BRIDGE, SO THEY ARRIVE AS OBJECTS AND ARE CAST BACK HERE.** The
	 * receiver is a `CFCharacterSetRef` held in a Core Foundation variable, but `-invertedSet` and `-mutableCopy`
	 * are asked of it as an OBJECT (that is the whole point of the door), so what they answer is typed
	 * `NSCharacterSet *`/`id` — correct at run time because these are toll-free, and the cast is what tells the
	 * compiler the two spellings of the same pointer were deliberate. */
	inv = (CFCharacterSetRef)[(id)w invertedSet];
	check(inv != NULL && [(id)inv characterIsMember:'z'], "the inverted set does not hold 'z'");
	mut = (CFMutableCharacterSetRef)[(id)w mutableCopy];
	check(mut != NULL && [(id)mut characterIsMember:'a'], "the mutable copy does not hold 'a'");
	check([[(id)w description] length] > 0, "an owned set answered no description");
}

static void arg_cfreadstream(void)
{
	/* Core Foundation's own constructor, so the object under test is Core Foundation's and not one Foundation
	 * built. The bytes live on this stack frame for the length of the case, which is what kCFAllocatorNull's
	 * "do not free this" deallocator is for. */
	const UInt8 bytes[] = { 'a', 'b', 'c' };
	CFReadStreamRef s = CFReadStreamCreateWithBytesNoCopy(NULL, bytes, (CFIndex)sizeof bytes, kCFAllocatorNull);
	UInt8 buffer[8];
	CFIndex n;

	check(s != NULL, "the read stream could not be made");
	if (s == NULL) {
		return;
	}
	/* THE ONE DOOR THAT HAS NO CORE FOUNDATION COUNTERPART, and the answer Foundation expects of a stream no
	 * Foundation loop is watching. */
	check([(id)s fnStreamDescriptor] == -1, "a CF read stream answered descriptor %d, want -1",
	      [(id)s fnStreamDescriptor]);

	[(id)s open];
	check([(id)s streamStatus] == 2, "status after open is %lu, want 2 (kCFStreamStatusOpen)",
	      (unsigned long)[(id)s streamStatus]);
	check([(id)s hasBytesAvailable], "a CF read stream over three bytes says it has none");
	n = [(id)s read:buffer maxLength:sizeof buffer];
	check(n == 3, "a CF read stream read %ld bytes, want 3", (long)n);
	check(buffer[0] == 'a' && buffer[2] == 'c', "the bytes read back are not the bytes that went in");
	check([(id)s propertyForKey:(id)CFSTR("no such property")] == nil,
	      "a CF read stream answered an unknown property");
	[(id)s close];
}

static void arg_cfwrite_stream(void)
{
	CFWriteStreamRef s = CFWriteStreamCreateWithAllocatedBuffers(NULL, kCFAllocatorSystemDefault);
	const char *text = "xyz";

	check(s != NULL, "the write stream could not be made");
	if (s == NULL) {
		return;
	}
	[(id)s open];
	check([(id)s streamStatus] == 2, "status after open is %lu, want 2 (kCFStreamStatusOpen)",
	      (unsigned long)[(id)s streamStatus]);
	check([(id)s hasSpaceAvailable], "a CF write stream says it has no space");
	check([(id)s write:text maxLength:3] == 3, "a CF write stream wrote %ld bytes, want 3",
	      (long)[(id)s write:text maxLength:3]);
	[(id)s close];
}

static void arg_cftimer(void)
{
	/* CORE FOUNDATION'S OWN TIMER, with a context and no callout needed: nothing here runs a run loop, so the
	 * callback is never reached. */
	CFRunLoopTimerContext context = { 0, NULL, NULL, NULL, NULL };
	CFRunLoopTimerRef t = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 100.0, 5.0, 0, 0,
						   NULL, &context);

	check(t != NULL, "the timer could not be made");
	if (t == NULL) {
		return;
	}
	check([(id)t timeInterval] == 5.0, "a native CFRunLoopTimer answered timeInterval %g, want 5",
	      (double)[(id)t timeInterval]);
	check([(id)t isValid], "a native CFRunLoopTimer is not valid");
	check([(id)t tolerance] == 0.0, "a native CFRunLoopTimer answered tolerance %g, want 0",
	      (double)[(id)t tolerance]);
	check([(id)t fireDate] != nil, "a native CFRunLoopTimer answered no fire date");
	/* -fnRepeats IS EXERCISED THROUGH -description AND IS NOT CALLED DIRECTLY: it is a private accessor with no
	 * declaration in a public header, so a message to it compiles as an `id` return and would read eight bytes
	 * where one was written. The description below carries its answer, which is Core Foundation's
	 * CFRunLoopTimerDoesRepeat. */
	/* AND THE ONE PRIMITIVE WITH NO CORE FOUNDATION COUNTERPART: a CF timer holds a context, not a user-info
	 * object, so nil is the true answer. */
	check([(id)t userInfo] == nil, "a CF timer answered a userInfo object");
	check([[(id)t description] length] > 0, "a native CFRunLoopTimer answered no description");

	/* THE WRITE DOORS, AND ONE OF THEM IS INERT ON THIS PLATFORM -- MEASURED, NOT ASSUMED: Core Foundation's
	 * own CFRunLoopTimerGetTolerance/SetTolerance are written `#if TARGET_OS_MAC`, with `return 0.0` and an
	 * empty body otherwise, so a CF timer's tolerance IS 0 here and the setter IS a no-op. That is the answer
	 * this case asserts, because it is what this platform's Core Foundation does. */
	[(id)t setTolerance:0.5];
	check([(id)t tolerance] == 0.0, "a CF timer's tolerance is %g, want 0 (Core Foundation stubs it off-Mac)",
	      (double)[(id)t tolerance]);
	[(id)t fire];	/* must not crash: a CF timer's callout belongs to Core Foundation's run loop */
	check([(id)t isValid], "a native CFRunLoopTimer stopped being valid without -invalidate");
	[(id)t invalidate];
	check(![(id)t isValid], "an invalidated CFRunLoopTimer still says it is valid");
}

static void arg_cfcalendar(void)
{
	/* A BARE CFSTR FOR THE IDENTIFIER, for the reason arg_cfcharset gives: it used to have to be a native
	 * CFString, and now that the byte door converts, the bridged form is the stronger test.
	 *
	 * AND THIS CASE IS WHY CFTimeZoneCopySystem'S tm_zone GUARD EXISTS: constructing any Core Foundation
	 * calendar reaches _CFCalendarInitialize -> CFTimeZoneCopyDefault -> CFTimeZoneCopySystem, which used to
	 * segfault inside libc on this system (no /etc/localtime, no TZ, and a localtime that leaves tm_zone NULL).
	 * That crash is what kept this type unverifiable, and it is fixed in libagora-core/CFTimeZone.c. */
	CFStringRef identifier = CFSTR("gregorian");
	CFCalendarRef c = CFCalendarCreateWithIdentifier(NULL, identifier);

	check(c != NULL, "the calendar could not be made");
	if (c == NULL) {
		return;
	}

	/* THE FIVE READ PRIMITIVES, which are the whole state this class has. */
	check([[(id)c calendarIdentifier] isEqualToString:@"gregorian"],
	      "a native CFCalendar answered identifier %s, want gregorian",
	      [[(id)c calendarIdentifier] UTF8String] ?: "(nil)");
	check([(id)c timeZone] != nil, "a native CFCalendar has no time zone");
	check([(id)c locale] != nil, "a native CFCalendar has no locale");
	check([(id)c firstWeekday] >= 1 && [(id)c firstWeekday] <= 7,
	      "a native CFCalendar answered firstWeekday %lu", (unsigned long)[(id)c firstWeekday]);
	check([(id)c minimumDaysInFirstWeek] >= 1,
	      "a native CFCalendar answered minimumDaysInFirstWeek %lu",
	      (unsigned long)[(id)c minimumDaysInFirstWeek]);

	/* AND THE FOUR WRITES. */
	[(id)c setFirstWeekday:3];
	check([(id)c firstWeekday] == 3, "setFirstWeekday: did not take: %lu",
	      (unsigned long)[(id)c firstWeekday]);
	[(id)c setMinimumDaysInFirstWeek:4];
	check([(id)c minimumDaysInFirstWeek] == 4, "setMinimumDaysInFirstWeek: did not take: %lu",
	      (unsigned long)[(id)c minimumDaysInFirstWeek]);

	/* AND ONE COMPUTATION DOOR, WHICH IS THE WHOLE POINT OF THE ROUTING IN libagora-base: the decomposition
	 * runs in ICU, against the identifier, time zone and locale that a Core Foundation calendar supplied
	 * THROUGH the accessors. Nothing in the table answers this door; it is inherited, and it works.
	 *
	 * THE CALENDAR IS PUT IN UTC FIRST, AND THAT IS NOT FUSSINESS: its time zone is the SYSTEM one, so
	 * 1970-01-01T00:00:00Z decomposes to 1969 in a western zone. THIS CASE ASSERTED 1970 AND WAS WRONG, and the
	 * failure was the calendar being RIGHT -- the same species of wrong expectation this suite has had to
	 * correct five times before (kCFAllocatorDefault, the epoch, the date test, the groups that only printed).
	 * Setting the zone makes the expectation independent of where the suite runs, and it exercises
	 * -setTimeZone: on the way. */
	[(id)c setTimeZone:(id)[NSTimeZone timeZoneWithName:@"UTC"]];
	{
		NSDateComponents *parts = [(id)c components:NSCalendarUnitYear | NSCalendarUnitMonth
						  fromDate:[NSDate dateWithTimeIntervalSince1970:0.0]];

		check(parts != nil && [parts year] == 1970,
		      "a CF calendar in UTC decomposed 1970-01-01 into year %ld, want 1970",
		      parts != nil ? (long)[parts year] : -1);
	}
	check([[(id)c description] length] > 0, "a native CFCalendar answered no description");
}

/* THE OTHER DIRECTION: A CORE FOUNDATION DOOR ASKED OF A FOUNDATION OBJECT. Every case above hands Core
 * Foundation's object to Foundation; this one hands Foundation's object to Core Foundation, which is where
 * the forwarding doors live -- a door Core Foundation sends that Foundation does not implement RAISES, and
 * nothing in the bridge had looked in this direction at all before.
 *
 * THIS ONE IS FIXED AND THE CASE GUARDS IT. Before libagora-base implemented -_cfStreamError, the first
 * check below was an uncaught NSInvalidArgumentException naming -[NSInputStream _cfStreamError] -- measured
 * with a probe, and a raise in this harness is a forked child that exits non-zero, so this case fails when
 * the door is missing rather than passing quietly.
 *
 * THE CALENDAR PAIR WAS THE SAME HOLE AND IS FIXED TOO: the case below this one drives
 * CFCalendarDecomposeAbsoluteTime, ComposeAbsoluteTime and AddComponents at a Foundation NSCalendar. */
static void arg_forward_cfstreamerror(void)
{
	NSInputStream *broken = [[NSInputStream alloc] initWithFileAtPath:@"/nonexistent/agora/definitely/not/here"];
	CFStreamError err;
	NSError *cocoa;

	/* A STREAM THAT WAS NEVER OPENED IS ERROR-FREE, which is Core Foundation's {0, 0}. */
	err = CFReadStreamGetError((CFReadStreamRef)broken);
	check(err.domain == 0 && err.error == 0,
	      "an unopened Foundation stream reported {%ld,%d} to Core Foundation, want {0,0}",
	      (long)err.domain, (int)err.error);

	/* AND AFTER A FAILED OPEN THE PAIR CARRIES THE NSError's OWN DOMAIN AND CODE, which is the whole
	 * point of the door: the same numbers Cocoa reports, in Core Foundation's numbering. */
	[broken open];
	cocoa = [broken streamError];
	check(cocoa != nil, "a Foundation stream on a nonexistent path reported no error after -open");
	if (cocoa != nil) {
		err = CFReadStreamGetError((CFReadStreamRef)broken);
		check(err.domain == kCFStreamErrorDomainPOSIX,
		      "a POSIX stream error was reported to Core Foundation as domain %ld, want %d (POSIX)",
		      (long)err.domain, (int)kCFStreamErrorDomainPOSIX);
		check(err.error == (SInt32)[cocoa code],
		      "Core Foundation read error %d where Cocoa reported %ld",
		      (int)err.error, (long)[cocoa code]);
	}

	/* AND THE WRITE SIDE INHERITS IT, because the door is on NSStream's own head. */
	{
		NSOutputStream *out = [[NSOutputStream alloc] initToFileAtPath:@"/nonexistent/agora/out" append:NO];

		err = CFWriteStreamGetError((CFWriteStreamRef)out);
		check(err.domain == 0 && err.error == 0,
		      "an unopened Foundation output stream reported {%ld,%d}, want {0,0}",
		      (long)err.domain, (int)err.error);
		[out release];
	}
	[broken release];
}

/* AND THE THREE CALENDAR DOORS, THE SAME SPECIES OF HOLE IN THE SAME DIRECTION, NOW FIXED. Core
 * Foundation's compose, decompose and add each dispatch at an Objective-C calendar through a selector
 * whose parts are '...:at :componentDescription :va_list' -- the shape Swift's bridge implements upstream,
 * which the call sites' own comment records ("Note: We do not toll-free bridge for Swift"). Nothing
 * implemented them here, and a Foundation NSCalendar handed to any of the three raised, measured:
 *
 *     -[NSCalendar _composeAbsoluteTime:::] is not implemented
 *
 * libagora-base answers all three now (NSCFBridging.m), and the expectations below are Core Foundation's
 * own values rather than values read back out of this implementation: the reference instant is
 * 2001-01-01 00:00:00 UTC, 1970-01-01 is -978307200 seconds from it, and adding a month to the 31st of
 * January CLAMPS to the 28th because that is what ICU does and what Cocoa's own
 * -dateByAddingComponents:toDate:options: does -- a field-wise add would have rolled over into March, which
 * is how the first version of the door was caught being wrong. */
static void arg_forward_cfcalendar(void)
{
	NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
	int y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0;
	CFAbsoluteTime at = 0;

	[cal setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];

	/* DECOMPOSE. */
	check(CFCalendarDecomposeAbsoluteTime((CFCalendarRef)cal, 0.0, "yMdHms", &y, &mo, &d, &h, &mi, &s),
	      "Core Foundation could not decompose an instant through a Foundation calendar");
	check(y == 2001 && mo == 1 && d == 1 && h == 0 && mi == 0 && s == 0,
	      "a Foundation calendar decomposed the reference instant as %04d-%02d-%02d %02d:%02d:%02d, want 2001-01-01 00:00:00",
	      y, mo, d, h, mi, s);

	/* COMPOSE. */
	check(CFCalendarComposeAbsoluteTime((CFCalendarRef)cal, &at, "yMdHms", 1970, 1, 1, 0, 0, 0),
	      "Core Foundation could not compose an instant through a Foundation calendar");
	check(at == -978307200.0, "a Foundation calendar composed 1970-01-01 as %.1f, want -978307200.0", (double)at);

	/* ADD, both directions. */
	at = 0;
	check(CFCalendarAddComponents((CFCalendarRef)cal, &at, 0, "d", 1) && at == 86400.0,
	      "one day added to the reference instant gave %.1f, want 86400.0", (double)at);
	at = 0;
	check(CFCalendarAddComponents((CFCalendarRef)cal, &at, 0, "d", -1) && at == -86400.0,
	      "one day subtracted from the reference instant gave %.1f, want -86400.0", (double)at);

	/* AND THE CLAMP. */
	at = 0;
	check(CFCalendarComposeAbsoluteTime((CFCalendarRef)cal, &at, "yMd", 2001, 1, 31),
	      "the 31st of January could not be composed");
	check(CFCalendarAddComponents((CFCalendarRef)cal, &at, 0, "M", 1),
	      "a month could not be added");
	y = mo = d = 0;
	check(CFCalendarDecomposeAbsoluteTime((CFCalendarRef)cal, at, "yMd", &y, &mo, &d)
	      && y == 2001 && mo == 2 && d == 28,
	      "2001-01-31 plus one month came back as %04d-%02d-%02d, want 2001-02-28 (ICU clamps; a field-wise add rolls over)",
	      y, mo, d);

	/* NANOSECONDS, which Core Foundation carries on a character of its own and takes from the instant
	 * rather than from a field. */
	{
		int32_t nanos = 0;

		check(CFCalendarDecomposeAbsoluteTime((CFCalendarRef)cal, 0.25, "#", &nanos) && nanos == 250000000,
		      "the sub-second part of 0.25 decomposed as %d, want 250000000", (int)nanos);
	}

	/* AND THE LEGACY REINTERPRETATION OF 'y', WHICH CORE FOUNDATION APPLIES AND THIS BRIDGE NOW REPRODUCES
	 * RATHER THAN DEVIATING FROM. With a WEEKDAY and a WEEK-OF-YEAR -- its old-week character '^' -- and
	 * neither a month nor a day, Core Foundation reads the year it is given as the YEAR-FOR-WEEK-OF-YEAR, so
	 * the 'y' spelling must agree exactly with an explicit 'Y'. THE CONTROL IS THE OTHER HALF OF THE RULE:
	 * without a weekday it must NOT fire, or ordinary years would be reinterpreted behind a caller's back. */
	{
		CFAbsoluteTime asYear = 0, asYearWOY = 0, controlY = 0, controlYWOY = 0;

		CFCalendarComposeAbsoluteTime((CFCalendarRef)cal, &asYear, "y^E", 2020, 1, 1);
		CFCalendarComposeAbsoluteTime((CFCalendarRef)cal, &asYearWOY, "Y^E", 2020, 1, 1);
		check(asYear == asYearWOY,
		      "the legacy 'y' rule did not fire: 'y^E' gave %.1f where 'Y^E' gave %.1f",
		      (double)asYear, (double)asYearWOY);

		CFCalendarComposeAbsoluteTime((CFCalendarRef)cal, &controlY, "yd", 2020, 1);
		CFCalendarComposeAbsoluteTime((CFCalendarRef)cal, &controlYWOY, "Yd", 2020, 1);
		check(controlY != controlYWOY,
		      "the legacy 'y' rule fired WITHOUT a weekday: 'yd' and 'Yd' both gave %.1f", (double)controlY);
	}
	[cal release];
}

/* AND THE BOOLEAN CORNER OF NSNumber, WHICH IS A BRIDGE OF ITS OWN AND WAS NOT ONE. Apple's NSNumber
 * documentation says NSNumber is toll-free bridged with CFNumber "for integer and floating point values,
 * and CFBoolean for Boolean values", and an NSNumber made from a BOOL really is a CFBoolean there. Here it
 * was not: the type was registered for nothing, so Core Foundation answered the wrong type id, CFBooleanGetValue
 * answered FALSE for every Boolean (it dispatches to -boolValue and falls back to an identity test against
 * kCFBooleanTrue), and messaging kCFBooleanTrue crashed outright because the constant wore no class.
 *
 * THE EXPECTATIONS ARE APPLE'S NUMBERS AND NOT THIS IMPLEMENTATION'S. The last check is the one that keeps
 * a wrong fix from passing: registering [NSNumber class] for the Boolean type would make every one of these
 * true while turning EVERY number into a Boolean, so the discriminator is asserted with them. */
static void arg_cfboolean(void)
{
	/* the type ids, in both directions of the question */
	check(CFGetTypeID((CFTypeRef)@YES) == CFBooleanGetTypeID(),
	      "an NSNumber made from YES reported a type id that is not CFBoolean's");
	check(CFGetTypeID((CFTypeRef)@NO) == CFBooleanGetTypeID(),
	      "an NSNumber made from NO reported a type id that is not CFBoolean's");
	check(CFGetTypeID((CFTypeRef)@1) == CFNumberGetTypeID(),
	      "an NSNumber made from the integer 1 is no longer a CFNumber");
	check(CFGetTypeID((CFTypeRef)[NSNumber numberWithDouble:1.5]) == CFNumberGetTypeID(),
	      "an NSNumber made from a double is no longer a CFNumber");

	/* THE SILENT ONE: every Boolean answered false to Core Foundation before this. */
	check(CFBooleanGetValue((CFBooleanRef)@YES) == 1, "CFBooleanGetValue said YES was false");
	check(CFBooleanGetValue((CFBooleanRef)@NO) == 0, "CFBooleanGetValue said NO was true");

	/* AND THE CRASHING ONE: Core Foundation's own constants had no class to message. */
	check([(NSNumber *)kCFBooleanTrue boolValue] == 1, "kCFBooleanTrue did not answer -boolValue 1");
	check([(NSNumber *)kCFBooleanFalse boolValue] == 0, "kCFBooleanFalse did not answer -boolValue 0");

	/* THE PRIMITIVES BEHIND THAT: a Boolean built by Foundation and Core Foundation's constant have to be
	 * equal, which only holds if the owned class's -agKind and value doors agree with AGNumberBoolean. */
	check([(NSNumber *)kCFBooleanTrue isEqual:@YES], "kCFBooleanTrue is not equal to an NSNumber YES");
	check(![(NSNumber *)kCFBooleanTrue isEqual:@NO], "kCFBooleanTrue is equal to an NSNumber NO");
	check([[(NSNumber *)kCFBooleanTrue description] length] > 0,
	      "Core Foundation's Boolean answered no description through Foundation");
	{
		/* -objCType ANSWERS A C STRING AND NOT AN NSString, which this check got wrong first time: it sent
		 * -length to the char * and the case died of SIGSEGV in the forked child. The suite caught it as a
		 * failed case rather than a hang, which is what the fork is for. */
		const char *encoding = [(NSNumber *)kCFBooleanTrue objCType];

		check(encoding != NULL && encoding[0] != '\0',
		      "Core Foundation's Boolean answered no objCType through Foundation");
	}
}

/* ---------------------------------------------------------------------------------------------------- */
/* AND THE MUTABLE ARRAY'S STORAGE CONTRACT, WHICH THE MUTABLE BRIDGE RESTS ON.                         */
/* ---------------------------------------------------------------------------------------------------- */
/* A Core Foundation array handed to Foundation has to answer as an NSMutableArray without inheriting this
 * library's storage code -- AGArrayMutable implements NOTHING, so everything NSMutableArray does reads
 * _items, _count and _mutations, which over a Core Foundation object is silent corruption. The class below
 * is the proof that the routing is COMPLETE: it puts its elements somewhere else entirely, answers the
 * seven primitives and nothing else, and every other method of NSMutableArray has to work over that
 * storage. A method that still reads the class's own ivars gives a wrong answer here or dies. */
@interface FNForeignMutableArray : NSMutableArray {
	@public
	id _store[32];
	unsigned long _storeCount;
	unsigned long _storeMutations;
}
@end

@implementation FNForeignMutableArray
- (NSUInteger)count { return _storeCount; }
- (id)objectAtIndex:(NSUInteger)i { return _store[i]; }
- (void)insertObject:(id)o atIndex:(NSUInteger)i
{
	unsigned long k;

	for (k = _storeCount; k > i; k--) { _store[k] = _store[k - 1]; }
	_store[i] = [o retain];
	_storeCount++;
	_storeMutations++;
}
- (void)removeObjectAtIndex:(NSUInteger)i
{
	unsigned long k;

	[_store[i] release];
	for (k = i; k + 1 < _storeCount; k++) { _store[k] = _store[k + 1]; }
	_storeCount--;
	_storeMutations++;
}
- (void)removeAllObjects
{
	unsigned long k;

	for (k = 0; k < _storeCount; k++) { [_store[k] release]; }
	_storeCount = 0;
	_storeMutations++;
}
- (void)replaceObjectAtIndex:(NSUInteger)i withObject:(id)o
{
	[o retain];
	[_store[i] release];
	_store[i] = o;
	_storeMutations++;
}
- (unsigned long *)fnMutationWord { return &_storeMutations; }
@end

static void arg_mutable_array_primitives(void)
{
	FNForeignMutableArray *a = [[FNForeignMutableArray alloc] init];
	NSArray *snapshot;
	NSString *joined;
	NSUInteger seen = 0;

	[a addObject:@"a"];
	[a addObject:@"b"];
	[a addObject:@"c"];
	check([a count] == 3, "-addObject: did not reach foreign storage");
	[a removeLastObject];
	check([a count] == 2, "-removeLastObject did not reach foreign storage");
	[a insertObject:@"z" atIndex:0];
	check([[a objectAtIndex:0] isEqual:@"z"], "-insertObject:atIndex: did not reach foreign storage");
	[a replaceObjectAtIndex:1 withObject:@"A"];
	check([[a objectAtIndex:1] isEqual:@"A"], "-replaceObjectAtIndex:withObject: did not reach foreign storage");
	[a exchangeObjectAtIndex:0 withObjectAtIndex:2];
	check([[a objectAtIndex:0] isEqual:@"b"] && [[a objectAtIndex:2] isEqual:@"z"],
	      "-exchangeObjectAtIndex:withObjectAtIndex: read storage of its own");
	[a setObject:@"q" atIndexedSubscript:0];
	check([[a objectAtIndex:0] isEqual:@"q"], "setObject:atIndexedSubscript: read storage of its own");
	[a removeObjectIdenticalTo:@"A"];
	check([a count] == 2, "-removeObjectIdenticalTo: read storage of its own");
	[a addObjectsFromArray:@[ @"1", @"2" ]];
	check([a count] == 4, "-addObjectsFromArray: read storage of its own");
	[a removeObject:@"2" inRange:NSMakeRange(0, [a count])];
	check([a count] == 3, "-removeObject:inRange: read storage of its own");
	snapshot = [a copy];
	check([snapshot count] == 3 && [snapshot isKindOfClass:[NSArray class]], "-copy read storage of its own");
	[a sortUsingSelector:@selector(compare:)];
	check([[a objectAtIndex:0] isEqual:@"1"], "-sortUsingSelector: read storage of its own");
	for (id element in a) {
		(void)element;
		seen++;
	}
	check(seen == 3, "fast enumeration did not read the storage's own mutation word");
	joined = [a componentsJoinedByString:@","];
	check(joined != nil && [joined length] > 0, "a derived string door read storage of its own");
	[a removeAllObjects];
	check([a count] == 0, "-removeAllObjects did not reach foreign storage");
	[a release];
}

/* AND THE MUTABLE HALF OF A CORE FOUNDATION ARRAY, WHICH IS THE FIRST OF THESE TYPES TO HAVE ONE.
 * CFMutableArrayRef and CFArrayRef SHARE ONE TYPE ID, so Core Foundation picks the class at CREATION from
 * the category its constructor passes -- __NSCFMutableArray against __NSCFArray -- and the owned class's
 * methods ARE Core Foundation's, over Core Foundation's storage.
 *
 * THE EXPECTATIONS ARE WHAT APPLE ANSWERS: a mutable Core Foundation array is an NSMutableArray and an
 * immutable one is not; mutation works from EITHER side and is visible to the other; and the two
 * TWO-ARGUMENT mutators are here because they are the ones that were silently broken -- an owned class
 * built with an abbreviated type encoding receives NO SEND for a selector with two arguments or more, and
 * measured, "v@:@@Q" gave the message to Foundation's implementation while Foundation's own
 * "v32@0:8@16Q24" delivered it. That is why a mutable row takes its types from the prototype.
 *
 * THE IMMUTABLE HALF IS ASSERTED WITH -respondsToSelector: AND NOT BY TRYING IT. Sending -addObject: to a
 * Core Foundation array that is not mutable TERMINATES the process with a message (the same way it did
 * before any of this existed), and a case that terminates is a FAILED case in this harness -- the fork
 * would report it as one. So the question "is this array mutable" is asked the way a program should ask it. */
static void arg_mutable_cfarray(void)
{
	CFMutableArrayRef m = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
	CFArrayRef immutable = CFArrayCreate(NULL, (const void *[]){ CFSTR("only") }, 1, &kCFTypeArrayCallBacks);
	NSUInteger seen = 0;

	check([(id)m isKindOfClass:[NSMutableArray class]],
	      "a CFMutableArrayRef is not an NSMutableArray");
	check(![(id)immutable isKindOfClass:[NSMutableArray class]],
	      "a CFArrayRef claims to be mutable");
	check(![(id)immutable respondsToSelector:@selector(addObject:)],
	      "an immutable CFArray responds to -addObject:");

	/* BOTH DIRECTIONS, THROUGH BOTH APIS. */
	[(NSMutableArray *)m addObject:@"a"];
	[(NSMutableArray *)m addObject:@"b"];
	[(NSMutableArray *)m insertObject:@"z" atIndex:0];
	check([(id)m count] == 3 && CFArrayGetCount(m) == 3,
	      "after two -addObject: and an -insertObject:atIndex:, Foundation sees %ld and Core Foundation %ld",
	      (long)[(id)m count], (long)CFArrayGetCount(m));
	check([[(id)CFArrayGetValueAtIndex(m, 0) description] isEqualToString:@"z"],
	      "the inserted element is not first where Core Foundation looks");

	CFArrayAppendValue(m, CFSTR("c"));
	check([(id)m count] == 4 && [[(id)[(id)m objectAtIndex:3] description] isEqualToString:@"c"],
	      "Core Foundation's own append is not visible through Foundation");

	[(NSMutableArray *)m replaceObjectAtIndex:0 withObject:@"Q"];
	check([[(id)CFArrayGetValueAtIndex(m, 0) description] isEqualToString:@"Q"],
	      "-replaceObjectAtIndex:withObject: did not reach Core Foundation");

	[(NSMutableArray *)m removeObjectAtIndex:0];
	check(CFArrayGetCount(m) == 3 && [[(id)CFArrayGetValueAtIndex(m, 0) description] isEqualToString:@"a"],
	      "-removeObjectAtIndex: did not reach Core Foundation");

	for (id element in (id)m) {
		(void)element;
		seen++;
	}
	check(seen == 3, "fast enumeration over a mutable Core Foundation array saw %lu", (unsigned long)seen);

	[(NSMutableArray *)m removeAllObjects];
	check(CFArrayGetCount(m) == 0 && [(id)m count] == 0, "-removeAllObjects did not reach Core Foundation");
}

/* AND THE SECOND MUTABLE TYPE, WHICH NEEDED NO FOUNDATION ROUTING AT ALL. NSMutableDictionary's own
 * implementation already delegates to three internal storage doors -- -setObjectInternal:forKey:,
 * -removeObjectInternalForKey: and -removeAllInternalObjects -- and measured, it touches storage nowhere
 * else, so a class with storage of its own only has to answer those three (and bring its own mutation word
 * for the fast-enumeration loop, which is the one thing it cannot inherit). Core Foundation's dictionary is
 * a CFBasicHash underneath, so the class is chosen by the CATEGORY its mutable creator passes to the
 * re-stamp every dictionary and set goes through.
 *
 * MEASURED AND NOT ASSUMED: CFDictionaryGetValue finds a value that Foundation's tagged NSString stored and
 * the other way round, -isKindOfClass: says yes for the mutable one and no for an immutable one, and an
 * immutable Core Foundation dictionary does not respond to -setObject:forKey: at all. */
static void arg_mutable_cfdictionary(void)
{
	CFMutableDictionaryRef d = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
							     &kCFTypeDictionaryValueCallBacks);
	CFDictionaryRef immutable = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks,
						       &kCFTypeDictionaryValueCallBacks);
	NSUInteger seen = 0;

	check([(id)d isKindOfClass:[NSMutableDictionary class]],
	      "a CFMutableDictionaryRef is not an NSMutableDictionary");
	check(![(id)immutable isKindOfClass:[NSMutableDictionary class]],
	      "an immutable CFDictionary claims to be mutable");
	check(![(id)immutable respondsToSelector:@selector(setObject:forKey:)],
	      "an immutable CFDictionary responds to -setObject:forKey:");

	/* FOUNDATION MUTATES, CORE FOUNDATION LOOKS -- and the key was a tagged NSString. */
	[(NSMutableDictionary *)d setObject:@"v" forKey:@"k"];
	check([(id)d count] == 1 && CFDictionaryGetCount(d) == 1,
	      "after -setObject:forKey:, Foundation sees %ld and Core Foundation %ld",
	      (long)[(id)d count], (long)CFDictionaryGetCount(d));
	check([[(id)CFDictionaryGetValue(d, CFSTR("k")) description] isEqualToString:@"v"],
	      "Core Foundation cannot read a value Foundation stored under a tagged key");

	/* AND THE OTHER WAY ROUND. */
	CFDictionarySetValue(d, CFSTR("k2"), CFSTR("v2"));
	check([[(id)[(id)d objectForKey:@"k2"] description] isEqualToString:@"v2"],
	      "Foundation cannot read a value Core Foundation stored");

	for (id key in (id)d) {
		(void)key;
		seen++;
	}
	check(seen == 2, "fast enumeration over a mutable Core Foundation dictionary saw %lu", (unsigned long)seen);

	[(NSMutableDictionary *)d removeObjectForKey:@"k"];
	check(CFDictionaryGetCount(d) == 1, "-removeObjectForKey: did not reach Core Foundation");
	[(NSMutableDictionary *)d removeAllObjects];
	check(CFDictionaryGetCount(d) == 0 && [(id)d count] == 0, "-removeAllObjects did not reach Core Foundation");
}

/* AND THE THIRD MUTABLE TYPE, WHICH IS THE CHEAPEST OF THE THREE AND THE FIRST TO NEED NO FOUNDATION
 * ROUTING AT ALL. A set's whole storage contract is ONE door -- -fnReplaceMembers: -- and measured, every
 * mutable operation funnels through it: -addObject: copies the members, appends and replaces, and
 * -unionSet:, -minusSet:, -intersectSet: and -setSet: compute a new membership and replace. So the owned
 * class answers that door and inherits a complete mutable set; the only thing it cannot inherit is the
 * fast-enumeration word, which is an address.
 *
 * -unionSet: IS DRIVEN HERE ON PURPOSE: it is a DERIVED operation, so it only works if the single door is
 * answered over Core Foundation's storage -- a class that answered the door but read Foundation's members
 * anywhere else would pass the direct checks and fail this one. A set is a CFBasicHash like a dictionary,
 * so the class is chosen by the category its mutable creator passes. */
static void arg_mutable_cfset(void)
{
	CFMutableSetRef s = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
	CFSetRef immutable = CFSetCreate(NULL, NULL, 0, &kCFTypeSetCallBacks);
	NSUInteger seen = 0;

	check([(id)s isKindOfClass:[NSMutableSet class]], "a CFMutableSetRef is not an NSMutableSet");
	check(![(id)immutable isKindOfClass:[NSMutableSet class]], "an immutable CFSet claims to be mutable");
	check(![(id)immutable respondsToSelector:@selector(addObject:)],
	      "an immutable CFSet responds to -addObject:");

	[(NSMutableSet *)s addObject:@"a"];
	[(NSMutableSet *)s addObject:@"b"];
	check([(id)s count] == 2 && CFSetGetCount(s) == 2,
	      "after two -addObject:, Foundation sees %ld and Core Foundation %ld", (long)[(id)s count], (long)CFSetGetCount(s));
	check(CFSetContainsValue(s, CFSTR("a")), "Core Foundation cannot see a member Foundation added");

	CFSetAddValue(s, CFSTR("c"));
	check([(id)s containsObject:@"c"], "Foundation cannot see a member Core Foundation added");

	[(NSMutableSet *)s removeObject:@"a"];
	check(CFSetGetCount(s) == 2 && ![(id)s containsObject:@"a"],
	      "-removeObject: did not reach Core Foundation");

	/* THE DERIVED DOOR: it computes a membership and hands it to -fnReplaceMembers:. */
	[(NSMutableSet *)s unionSet:[NSSet setWithObject:@"z"]];
	check([(id)s containsObject:@"z"] && CFSetContainsValue(s, CFSTR("z")),
	      "-unionSet: did not reach Core Foundation through the storage door");

	for (id member in (id)s) {
		(void)member;
		seen++;
	}
	check(seen == 3, "fast enumeration over a mutable Core Foundation set saw %lu", (unsigned long)seen);

	[(NSMutableSet *)s removeAllObjects];
	check(CFSetGetCount(s) == 0 && [(id)s count] == 0, "-removeAllObjects did not reach Core Foundation");
}

/* AND THE FOURTH MUTABLE TYPE, WHICH FOUND A BUG IN THIS LIBRARY RATHER THAN IN THE BRIDGE.
 * libagora-base's mutable string keeps its characters behind two doors -- -setString: and
 * -appendUTF8String: -- and every other mutation is derived from one of them (-appendString: calls
 * -appendUTF8String:; -replaceCharactersInRange:withString: builds a string and calls -setString:). So
 * the owned class answers those two plus the three accessor doors, and libagora-base needed no routing.
 *
 * WHAT IT DID NEED WAS A FIX. NSString.h promises that a subclass answering -length, -characterAtIndex:
 * and -UTF8String "is correct through the derived doors without any storage of its own" -- and MEASURED,
 * that was FALSE: NSOwnedString's -lengthOfBytesUsingEncoding: returned its own _utf8size field, so a
 * subclass with no such field read foreign memory and answered 32 for "ab". Every Core Foundation mutable
 * string then compared UNEQUAL TO ITSELF (compare: 1, isEqual: NO, a different hash), and the assertions
 * below are what caught it. The count now comes from the accessor the contract names.
 *
 * EVERY PUBLIC MUTABLE DOOR IS DRIVEN AND CORE FOUNDATION IS CHECKED AFTER EACH, and the VALUE SEMANTICS
 * ARE ASSERTED TOO -- equality and hash -- because a string that reads correctly and compares wrongly is
 * the failure this case exists for. */
static void arg_mutable_cfstring(void)
{
	CFMutableStringRef s = CFStringCreateMutable(NULL, 0);
	CFStringRef immutable = CFStringCreateWithCString(NULL, "immutable", kCFStringEncodingUTF8);
	NSUInteger replaced;

	check([(id)s isKindOfClass:[NSMutableString class]], "a CFMutableStringRef is not an NSMutableString");
	check(![(id)immutable isKindOfClass:[NSMutableString class]], "an immutable CFString claims to be mutable");
	check(![(id)immutable respondsToSelector:@selector(appendString:)],
	      "an immutable CFString responds to -appendString:");

	/* -appendString: IS THE DERIVED DOOR OVER -appendUTF8String:, AND EQUALITY IS THE CHECK THAT MATTERS. */
	[(NSMutableString *)s appendString:@"ab"];
	check(CFStringGetLength(s) == 2, "-appendString: left Core Foundation holding %ld units", (long)CFStringGetLength(s));
	check([(id)s isEqualToString:@"ab"], "a Core Foundation mutable string holding ab is not equal to ab");
	check([(id)s hash] == [@"ab" hash], "a Core Foundation mutable string hashes differently from an equal string");

	CFStringAppend(s, CFSTR("cd"));
	check([(id)s length] == 4 && [(id)s isEqualToString:@"abcd"],
	      "CFStringAppend left Foundation holding %s", [(id)s UTF8String]);

	/* -setString: IS THE DOOR ITSELF. */
	[(NSMutableString *)s setString:@"xyz"];
	check(CFStringGetLength(s) == 3 && [(id)s isEqualToString:@"xyz"],
	      "-setString: left Core Foundation holding %s", [(id)s UTF8String]);

	[(NSMutableString *)s replaceCharactersInRange:NSMakeRange(0, 1) withString:@"Q"];
	check([(id)s isEqualToString:@"Qyz"], "-replaceCharactersInRange:withString: gave %s", [(id)s UTF8String]);

	[(NSMutableString *)s appendFormat:@"-%d", 7];
	check([(id)s isEqualToString:@"Qyz-7"], "-appendFormat: gave %s", [(id)s UTF8String]);

	replaced = [(NSMutableString *)s replaceOccurrencesOfString:@"Q" withString:@"Z" options:0
							   range:NSMakeRange(0, [(id)s length])];
	check(replaced == 1 && [(id)s isEqualToString:@"Zyz-7"],
	      "-replaceOccurrencesOfString: replaced %lu and gave %s", (unsigned long)replaced, [(id)s UTF8String]);

	check(![[(id)s copy] isKindOfClass:[NSMutableString class]],
	      "a copy of a mutable Core Foundation string is itself mutable");
}

/* AND THE FIFTH MUTABLE TYPE, WHICH TOOK THE STRING'S LESSON AND NEEDED NO SECOND ATTEMPT. The class was
 * READ before a door was chosen: libagora-base's NSData.h names the two buffer accessors (-bytes and
 * -mutableBytes), and measured, the mutable class writes storage in exactly seven methods -- -mutableBytes,
 * -setLength:, -appendBytes:length:, -replaceBytesInRange:withBytes:length:, -resetBytesInRange:,
 * -increaseLengthBy: and -setData:. All seven are ANSWERED rather than left to Foundation's implementation,
 * because a method here that Foundation still runs writes ITS storage into a Core Foundation object.
 *
 * A CFData's variety -- immutable, fixed-mutable, mutable -- shares one type id, so the class is chosen by
 * the category its initialiser passes, the same road the array took.
 *
 * AND THE VALUE SEMANTICS ARE ASSERTED, which is what the mutable string's turn taught: a data that reads
 * back correctly and compares or hashes wrongly would pass every byte check here. */
static void arg_mutable_cfdata(void)
{
	CFMutableDataRef d = CFDataCreateMutable(NULL, 0);
	CFDataRef immutable = CFDataCreate(NULL, (const UInt8 *)"imm", 3);
	const unsigned char reference[4] = { 1, 2, 3, 4 };
	const unsigned char *got;
	NSData *equal;

	check([(id)d isKindOfClass:[NSMutableData class]], "a CFMutableDataRef is not an NSMutableData");
	check(![(id)immutable isKindOfClass:[NSMutableData class]], "an immutable CFData claims to be mutable");

	[(NSMutableData *)d appendBytes:reference length:4];
	check(CFDataGetLength(d) == 4, "-appendBytes:length: left Core Foundation holding %ld bytes",
	      (long)CFDataGetLength(d));
	CFDataAppendBytes(d, (const UInt8 *)"\x05\x06", 2);
	check([(id)d length] == 6, "CFDataAppendBytes left Foundation holding %lu bytes", (unsigned long)[(id)d length]);
	got = (const unsigned char *)[(NSData *)d bytes];
	check(got[0] == 1 && got[3] == 4 && got[4] == 5 && got[5] == 6,
	      "Foundation read %d %d %d %d %d %d from Core Foundation's bytes",
	      got[0], got[1], got[2], got[3], got[4], got[5]);

	[(NSMutableData *)d setLength:3];
	check(CFDataGetLength(d) == 3, "-setLength: left Core Foundation holding %ld bytes", (long)CFDataGetLength(d));

	[(NSMutableData *)d increaseLengthBy:2];
	got = (const unsigned char *)[(NSData *)d bytes];
	check(CFDataGetLength(d) == 5 && got[4] == 0, "-increaseLengthBy: left Core Foundation holding %ld bytes and a final byte of %d",
	      (long)CFDataGetLength(d), got[4]);

	[(NSMutableData *)d replaceBytesInRange:NSMakeRange(0, 1) withBytes:"\xff" length:1];
	check(((const unsigned char *)[(NSData *)d bytes])[0] == 0xFF,
	      "-replaceBytesInRange:withBytes:length: did not reach Core Foundation");

	[(NSMutableData *)d resetBytesInRange:NSMakeRange(0, 2)];
	got = (const unsigned char *)[(NSData *)d bytes];
	check(got[0] == 0 && got[1] == 0, "-resetBytesInRange: left %d %d", got[0], got[1]);

	/* THE WRITE ACCESSOR ITSELF, and then Foundation's view of the byte it changed. */
	((unsigned char *)[(NSMutableData *)d mutableBytes])[2] = 0x41;
	check(((const unsigned char *)[(NSData *)d bytes])[2] == 0x41,
	      "a write through -mutableBytes is not visible through -bytes");

	[(NSMutableData *)d setData:[NSData dataWithBytes:"zz" length:2]];
	check(CFDataGetLength(d) == 2, "-setData: left Core Foundation holding %ld bytes", (long)CFDataGetLength(d));

	/* AND THE VALUE SEMANTICS, not just the bytes. */
	equal = [NSData dataWithBytes:"zz" length:2];
	check([(id)d isEqual:equal], "a Core Foundation mutable data is not equal to an equal NSData");
	check([(id)d hash] == [equal hash], "a Core Foundation mutable data hashes differently from an equal NSData");
}

/* AND THE SIXTH MUTABLE TYPE, WHICH NEEDED TWO SCANS TO FIND ITS DOORS. libagora-base keeps a character
 * set as a RANGE LIST whose only storage WRITER is a static helper, fn_add_range -- so a scan by FIELD NAME
 * found five methods and missed -addCharactersInString: entirely, because no method body mentions _ranges
 * there. The union of a field-name scan and a HELPER-CALLER scan is the six doors answered here, and the
 * crash that came of missing one is why the rule is written down: follow the storage writes to their
 * helper, not just to the methods that spell the fields.
 *
 * THE SHARED BITMAP IS THE GROUND TRUTH. Both sides already use Core Foundation's bare 8192-byte plane-0
 * form (a decision this bridge made earlier), so membership can be checked from Foundation and from Core
 * Foundation after every mutation, and a Foundation set arriving as an argument is converted through that
 * bitmap rather than cast -- casting it is what segfaulted.
 *
 * AND EQUALITY IS ASSERTED, WHICH IS A CORRECTION TO WHAT THIS COMMENT FIRST SAID. It claimed the gap was
 * still owed, on the reasoning that base's -isEqual: is symmetric over -isSupersetOfSet: and the second
 * direction would read Core Foundation's storage through Foundation's offsets. MEASURED, THAT REASONING
 * WAS WRONG: base's implementation asks its argument through the accessors, so once -isSupersetOfSet: was
 * answered on BOTH rows -- which is what fixed this -- equality works in both directions, and -hash agrees.
 * A claim of what cannot work is as much a measurement as a claim of what can. */
static void arg_mutable_cfcharset(void)
{
	CFMutableCharacterSetRef cs = CFCharacterSetCreateMutable(NULL);
	CFCharacterSetRef immutable = CFCharacterSetCreateWithCharactersInString(NULL, CFSTR("abc"));
	NSData *bitmap;

	check([(id)cs isKindOfClass:[NSMutableCharacterSet class]],
	      "a CFMutableCharacterSetRef is not an NSMutableCharacterSet");
	check(![(id)immutable isKindOfClass:[NSMutableCharacterSet class]],
	      "an immutable CFCharacterSet claims to be mutable");

	[(NSMutableCharacterSet *)cs addCharactersInString:@"abc"];
	check(CFCharacterSetIsCharacterMember(cs, 'a') && !CFCharacterSetIsCharacterMember(cs, 'z'),
	      "-addCharactersInString: did not reach Core Foundation");

	[(NSMutableCharacterSet *)cs addCharactersInRange:NSMakeRange('x', 2)];
	check(CFCharacterSetIsCharacterMember(cs, 'x'),
	      "-addCharactersInRange: did not reach Core Foundation (it is derived through union)");

	[(NSMutableCharacterSet *)cs removeCharactersInString:@"b"];
	check(![(id)cs characterIsMember:'b'], "-removeCharactersInString: did not reach Core Foundation");
	[(NSMutableCharacterSet *)cs removeCharactersInRange:NSMakeRange('x', 1)];
	check(![(id)cs characterIsMember:'x'], "-removeCharactersInRange: did not reach Core Foundation");

	bitmap = [(id)cs bitmapRepresentation];
	check([bitmap length] == 8192, "the shared bitmap is %lu bytes, want 8192", (unsigned long)[bitmap length]);
	if ([bitmap length] == 8192) {
		const unsigned char *bytes = (const unsigned char *)[bitmap bytes];

		check((bytes['a' / 8] & (1u << ('a' % 8))) != 0, "the bitmap does not carry 'a'");
		check((bytes['y' / 8] & (1u << ('y' % 8))) != 0, "the bitmap does not carry 'y'");
	}

	[(NSMutableCharacterSet *)cs formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"Q"]];
	check(CFCharacterSetIsCharacterMember(cs, 'Q'), "-formUnionWithCharacterSet: did not reach Core Foundation");

	[(NSMutableCharacterSet *)cs formIntersectionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@"aQ"]];
	check(CFCharacterSetIsCharacterMember(cs, 'a') && !CFCharacterSetIsCharacterMember(cs, 'y'),
	      "-formIntersectionWithCharacterSet: did not reach Core Foundation");

	/* THE VALUE SEMANTICS, BOTH WAYS -- WHICH THIS COMMENT ONCE CLAIMED WERE IMPOSSIBLE, AND THEY WORK.
	 * The comparison is made HERE, while the set is still the two characters that can be written out as an
	 * equal one; measured, equality, superset-ness and -hash all agree in both directions. */
	{
		NSCharacterSet *same = [NSCharacterSet characterSetWithCharactersInString:@"aQ"];

		check([(id)cs isSupersetOfSet:same] && [same isSupersetOfSet:(id)cs],
		      "a Core Foundation character set and an equal one are not supersets of each other");
		check([(id)cs isEqual:same] && [same isEqual:(id)cs],
		      "a Core Foundation character set is not equal to an equal one, in one direction or the other");
		check([(id)cs hash] == [same hash],
		      "a Core Foundation character set hashes differently from an equal one");
	}

	/* THE ROUND TRIP AFTER -invert IS NOT THE SAME QUESTION, AND MEASURING IT FOUND WHY. An earlier version
	 * of this comment said the bitmap round trip was broken -- it is not: a BMP-only set round-trips
	 * BYTE-IDENTICALLY through +characterSetWithBitmapRepresentation:. What the inverted set shows is this
	 * library's own limitation: its character sets are BMP-ONLY (-longCharacterIsMember: refuses above
	 * 0xFFFF, -hasMemberInPlane: answers plane 0 only), while Core Foundation's bitmap for a set spanning
	 * planes is 139280 bytes -- SEVENTEEN planes -- so rebuilding a Foundation set from it drops everything
	 * above plane 0 and the rebuilt set is a SUBSET, not an equal. Recorded at the decoder in
	 * NSCharacterSet.m, and not asserted here because asserting a subset relationship as if it were
	 * equality would be the mistake this comment exists to stop. */
	[(NSMutableCharacterSet *)cs invert];
	check(!CFCharacterSetIsCharacterMember(cs, 'a') && CFCharacterSetIsCharacterMember(cs, 'z'),
	      "-invert did not reach Core Foundation");

	check([[(id)cs description] length] > 0, "a mutable Core Foundation character set answered no description");


}

/* AND THE SEVENTH AND LAST MUTABLE TYPE, WHICH FOUND A MISSING DOOR IN FOUNDATION. An attributed string is
 * a string plus a RUN ARRAY, and MEASURED, libagora-base's only storage-writing method is
 * -replaceCharactersInRange:withString: -- the run helper -fnShiftRunsAfter:by: has exactly one caller, the
 * same method. So the row answers every mutation door over Core Foundation rather than leaving Foundation's
 * implementations to write their runs into a Core Foundation object.
 *
 * A FOUNDATION ATTRIBUTED STRING ARRIVING AS AN ARGUMENT IS RECONSTRUCTED, NOT CAST: unlike the character
 * sets there is no shared wire form, so the conversion walks the immutable primitive pair this class already
 * answers (-string and -attributesAtIndex:effectiveRange:) and rebuilds a Core Foundation one run by run.
 *
 * AND CFAttributedStringSetAttributes ASKED THE DICTIONARY FOR -_cfMutableCopy, WHICH libagora-base DID NOT
 * IMPLEMENT. MEASURED: '-[AGDictionaryItems _cfMutableCopy] is not implemented', an uncaught exception and
 * a terminal abort -- so a Foundation dictionary could not reach Core Foundation's attributed-string code at
 * all. That door is now on NSDictionary, and it is the third gap this bridging work has found in this
 * library rather than in the bridge.
 *
 * AND -mutableString IS DRIVEN THROUGH BOTH ROADS, WHICH TOOK THREE CORRECTIONS TO GET TO. (1) This comment
 * said Core Foundation exposes no mutable string view -- its HEADER DECLARES ONE
 * (CFAttributedStringGetMutableString), and the function DISPATCHES to -mutableString for a Foundation
 * attributed string. (2) The inherited proxy then turned out to read as EMPTY on a Core Foundation owner,
 * because -length was missing from the attributed rows. (3) And even with that fixed, -appendString: through
 * the proxy wrote the PROXY's storage instead of the owner's, because this library's mutable string writes
 * with -appendUTF8String: and reads with its own -UTF8String, so a subclass answering only the Cocoa
 * primitives gets its own storage used. All three are fixed, and this case now holds the result. */
static void arg_mutable_cfattributed(void)
{
	CFMutableAttributedStringRef a = CFAttributedStringCreateMutable(NULL, 0);
	NSRange effective = NSMakeRange(0, 0);
	id value;

	check([(id)a isKindOfClass:[NSMutableAttributedString class]],
	      "a CFMutableAttributedStringRef is not an NSMutableAttributedString");

	[(NSMutableAttributedString *)a replaceCharactersInRange:NSMakeRange(0, 0) withString:@"hello"];
	check(CFAttributedStringGetLength(a) == 5 && [[(id)a string] isEqualToString:@"hello"],
	      "-replaceCharactersInRange:withString: left Core Foundation holding %s", [[(id)a string] UTF8String]);

	[(NSMutableAttributedString *)a addAttribute:@"mark" value:@"X" range:NSMakeRange(0, 2)];
	value = (id)CFAttributedStringGetAttribute(a, 0, CFSTR("mark"), NULL);
	check(value != nil && [[value description] isEqualToString:@"X"],
	      "-addAttribute:value:range: did not reach Core Foundation");

	[(NSMutableAttributedString *)a addAttributes:@{ @"weight": @3 } range:NSMakeRange(1, 3)];
	value = (id)CFAttributedStringGetAttribute(a, 2, CFSTR("weight"), NULL);
	check(value != nil, "-addAttributes:range: did not reach Core Foundation");

	[(NSMutableAttributedString *)a removeAttribute:@"mark" range:NSMakeRange(0, 5)];
	check([(id)a attribute:@"mark" atIndex:0 effectiveRange:&effective] == nil,
	      "-removeAttribute:range: did not reach Core Foundation");

	/* THE DOOR THAT NEEDED -_cfMutableCopy, AND THE CLEARING IS TESTED WHERE IT CAN BE SEEN. weight was
	 * set on range (1,3); setting attributes on (1,2) with clearOtherAttributes OVERLAPS it, so the weight
	 * must be gone at index 1 -- my first version of this check cleared range (0,1), which does not overlap
	 * the weight at all and therefore clears nothing, and the check failed while the bridge was right. */
	[(NSMutableAttributedString *)a setAttributes:@{ @"only": @1 } range:NSMakeRange(1, 1)];
	check((id)CFAttributedStringGetAttribute(a, 1, CFSTR("weight"), NULL) == NULL,
	      "-setAttributes:range: did not clear the attribute it replaced");
	check([(id)a attribute:@"only" atIndex:1 effectiveRange:&effective] != nil,
	      "-setAttributes:range: did not reach Core Foundation");
	check([(id)a attribute:@"weight" atIndex:2 effectiveRange:&effective] != nil,
	      "-setAttributes:range: cleared an attribute outside the range it was given");

	[(NSMutableAttributedString *)a appendAttributedString:[[NSAttributedString alloc] initWithString:@"!"]];
	check(CFAttributedStringGetLength(a) == 6, "-appendAttributedString: left Core Foundation holding %ld units",
	      (long)CFAttributedStringGetLength(a));

	[(NSMutableAttributedString *)a insertAttributedString:[[NSAttributedString alloc] initWithString:@"N"] atIndex:0];
	check([[(id)a string] isEqualToString:@"Nhello!"], "-insertAttributedString:atIndex: gave %s",
	      [[(id)a string] UTF8String]);

	[(NSMutableAttributedString *)a deleteCharactersInRange:NSMakeRange(0, 1)];
	check(CFAttributedStringGetLength(a) == 6 && [[(id)a string] isEqualToString:@"hello!"],
	      "-deleteCharactersInRange: gave %s", [[(id)a string] UTF8String]);

	/* AND CORE FOUNDATION MUTATING, READ BACK THROUGH FOUNDATION. */
	CFAttributedStringReplaceString(a, CFRangeMake(0, CFAttributedStringGetLength(a)), CFSTR("zz"));
	check([(id)a length] == 2 && [[(id)a string] isEqualToString:@"zz"],
	      "CFAttributedStringReplaceString left Foundation holding %s", [[(id)a string] UTF8String]);
	check([(id)a attributesAtIndex:0 effectiveRange:&effective] != nil,
	      "the attributes are not readable through the immutable primitive");

	/* CORE FOUNDATION'S OWN MUTABLE-STRING DOOR, WHICH THE FIRST RECORD OF THIS TYPE SAID DID NOT EXIST:
	 * a Foundation attributed string answers it with a view, and Core Foundation's own object -- this one --
	 * answers NULL, because CF's native path for it is commented out. */
	{
		NSMutableAttributedString *foundation = [[NSMutableAttributedString alloc] initWithString:@"hi"];

		check(CFAttributedStringGetMutableString((CFMutableAttributedStringRef)foundation) != NULL,
		      "Core Foundation's mutable-string door did not answer for a Foundation attributed string");
		check(CFAttributedStringGetMutableString(a) == NULL,
		      "Core Foundation's mutable-string door answered for a Core Foundation object, whose native path is commented out");

		/* AND THE ROAD THAT USED TO BE RUINED: an ATTRIBUTED STRING'S OWN -mutableString, which Core
		 * Foundation's door cannot reach for its own object but a caller can. It must read the receiver's
		 * characters and WRITE THROUGH to it, in both directions. */
		/* LITERALS, NOT A COMPARISON AGAINST THE RECEIVER: an earlier version compared the view's length
		 * with [(id)a length], which can be 0 == 0 and pass for the wrong reason. The attributed string
		 * holds "zz" at this point. */
		check([[(NSMutableAttributedString *)a mutableString] length] == 2
		      && [[[(NSMutableAttributedString *)a mutableString] description] isEqualToString:@"zz"],
		      "a mutable-string view of a Core Foundation attributed string reads %s at length %lu, want zz at 2",
		      [[[(NSMutableAttributedString *)a mutableString] description] UTF8String],
		      (unsigned long)[[(NSMutableAttributedString *)a mutableString] length]);
		{
			NSMutableString *view = [(NSMutableAttributedString *)a mutableString];

			check([[[view description] substringToIndex:1] isEqualToString:@"z"],
			      "a mutable-string view of a Core Foundation attributed string does not read its characters back");
			[view appendString:@"!"];
			check(CFAttributedStringGetLength(a) == 3 && [[(id)a string] isEqualToString:@"zz!"],
			      "a write through the mutable-string view did not reach the attributed string (CF holds %s)",
			      [[(id)a string] UTF8String]);
			[view replaceCharactersInRange:NSMakeRange(0, 1) withString:@"Q"];
			check([[view description] isEqualToString:[(id)a string]],
			      "the view and its attributed string disagree: view %s, string %s",
			      [[view description] UTF8String], [[(id)a string] UTF8String]);
		}
	}
}

/* AND THE DOORS A SURFACE SURVEY FOUND MISSING, ALL EIGHT NOW ANSWERED. Core Foundation's own functions
 * were applied to FOUNDATION objects -- one child per type, each door named before it was called -- and
 * eight raised where a Foundation implementation simply was not there. Each is now answered, WITH ITS
 * SIGNATURE TAKEN FROM CORE FOUNDATION'S CALL SITE rather than guessed: -containsKey: returns a CHAR there
 * (not a BOOL, which is a different encoding in this tree), a SET's value door is -__getValue:forObj: while
 * a dictionary's is -__getValue:forKey:, and CFDictionarySetValue asks -__setObject:forKey:
 * (CFDictionary.c:397), which the survey's first pass never reached because it held only an immutable
 * dictionary.
 *
 * THE ASSERTIONS ARE THE ANSWERS, NOT THE ABSENCE OF A RAISE: a door that returns the wrong thing is as
 * broken as one that raises.
 *
 * AN EARLIER VERSION OF THIS CASE WAS REMOVED BECAUSE IT CRASHED, AND THAT WAS A MISTAKE OF MINE RATHER
 * THAN A FINDING: the probe I had been bisecting with passed @"x" to -stringWithUTF8String:, which wants a
 * C string, so it died wherever it ran and printed nothing when it failed to link. Retested properly the
 * doors answer in the parent and in a child, and the case below is the same battery. One death in the
 * original survey was never reproduced in four variations, so a "DIED" line there is an UNEXPLAINED death
 * and not an attribution -- which is why the eight doors are held by assertions rather than by that list. */
static void arg_cf_surface_doors(void)
{
	NSString *str = [NSString stringWithUTF8String:"hello"];
	NSDictionary *dict = @{ @"k": @"v" };
	NSMutableDictionary *mdict = [NSMutableDictionary dictionary];
	NSSet *set = [NSSet setWithObject:@"a"];
	NSMutableArray *array = [NSMutableArray arrayWithObject:@"a"];
	NSTimer *timer = [NSTimer timerWithTimeInterval:2.0 target:nil selector:@selector(description)
					       userInfo:nil repeats:NO];
	NSAttributedString *as = [[NSAttributedString alloc] initWithString:@"hi" attributes:@{ @"a": @1 }];
	const void *values[4];
	id out = nil;

	/* THE TWO ENCODING DOORS, which lived only on the constant-string class. */
	check(CFStringGetFastestEncoding((CFStringRef)str) != 0,
	      "CFStringGetFastestEncoding answered nothing for an ordinary Foundation string");
	check(CFStringGetSmallestEncoding((CFStringRef)str) != 0,
	      "CFStringGetSmallestEncoding answered nothing for an ordinary Foundation string");

	/* THE DICTIONARY'S, INCLUDING THE CHAR RETURN AND THE OUT-PARAMETER. */
	check(CFDictionaryContainsKey((CFDictionaryRef)dict, CFSTR("k")) != 0,
	      "CFDictionaryContainsKey did not find a key that is there");
	check(CFDictionaryContainsKey((CFDictionaryRef)dict, CFSTR("nope")) == 0,
	      "CFDictionaryContainsKey found a key that is not there");
	check(CFDictionaryGetValueIfPresent((CFDictionaryRef)dict, CFSTR("k"), (const void **)&out) && out != nil,
	      "CFDictionaryGetValueIfPresent did not report the value it was asked for");
	check(CFDictionaryCreateCopy(NULL, (CFDictionaryRef)dict) != NULL,
	      "CFDictionaryCreateCopy did not copy a Foundation dictionary");
	CFDictionarySetValue((CFMutableDictionaryRef)mdict, CFSTR("a"), CFSTR("1"));
	check(CFDictionaryGetCount((CFMutableDictionaryRef)mdict) == 1,
	      "CFDictionarySetValue did not reach a Foundation mutable dictionary");
	CFDictionaryRemoveValue((CFMutableDictionaryRef)mdict, CFSTR("a"));
	check(CFDictionaryGetCount((CFMutableDictionaryRef)mdict) == 0,
	      "CFDictionaryRemoveValue did not reach a Foundation mutable dictionary");

	/* THE SET'S, INCLUDING -__getValue:forObj:. */
	CFSetGetValues((CFSetRef)set, values);
	check(values[0] != NULL, "CFSetGetValues filled nothing");
	check(CFSetGetValue((CFSetRef)set, CFSTR("a")) != NULL,
	      "CFSetGetValue did not find a member that is there -- a set's value door is -__getValue:forObj:");
	check(CFSetCreateCopy(NULL, (CFSetRef)set) != NULL, "CFSetCreateCopy did not copy a Foundation set");

	/* AND THE ARRAY, THE TIMER AND THE ATTRIBUTED DOOR, WHOSE ANSWERS ARE THE CHANGE ITSELF. */
	CFArraySetValueAtIndex((CFMutableArrayRef)array, 0, CFSTR("z"));
	check([[(id)CFArrayGetValueAtIndex((CFArrayRef)array, 0) description] isEqualToString:@"z"],
	      "CFArraySetValueAtIndex did not replace the element");
	check(CFRunLoopTimerGetNextFireDate((CFRunLoopTimerRef)timer) != 0.0,
	      "CFRunLoopTimerGetNextFireDate answered nothing for a Foundation timer");
	check(CFAttributedStringGetAttributes((CFAttributedStringRef)as, 0, NULL) != NULL,
	      "CFAttributedStringGetAttributes answered nothing for a NULL effective range");
}

/* AND THE ANNEX PLANES, WHICH THIS TYPE USED TO DROP ENTIRELY. It was BMP-only: -longCharacterIsMember:
 * refused anything above 0xFFFF, -hasMemberInPlane: answered plane 0 only, and a set rebuilt from a Core
 * Foundation bitmap that spans planes kept nothing above plane 0 -- measured as
 * [cfSet isSupersetOf:rebuilt] yes, [rebuilt isSupersetOf:cfSet] NO. The type now reads Core Foundation's
 * FULL FORM: 8192 bytes of plane 0, then one index byte and 8192 bytes for each annex plane in ascending
 * order, which is exactly the length CFCharacterSetCreateBitmapRepresentation computes for itself. */
static void arg_cfcharset_annex(void)
{
	CFMutableCharacterSetRef cf = CFCharacterSetCreateMutable(NULL);
	CFDataRef cfBits;
	NSCharacterSet *rebuilt;
	NSCharacterSet *empty = [NSCharacterSet characterSetWithCharactersInString:@""];
	CFCharacterSetRef back;
	CFDataRef backBits;
	CFCharacterSetRef plain;
	CFDataRef plainBits;

	check(cf != NULL, "the mutable character set could not be made");
	if (cf == NULL) {
		return;
	}
	CFCharacterSetAddCharactersInRange(cf, CFRangeMake('a', 1));
	CFCharacterSetAddCharactersInRange(cf, CFRangeMake(0x1F600, 1));

	/* THE FORMAT'S SHAPE, ASSERTED SO A CHANGE TO IT CANNOT BE SILENT: two planes, so 8192 + 8193 = 16385. */
	cfBits = CFCharacterSetCreateBitmapRepresentation(NULL, cf);
	check(CFDataGetLength(cfBits) == 16385, "Core Foundation's two-plane bitmap is %ld bytes, want 16385",
	      (long)CFDataGetLength(cfBits));
	if (CFDataGetLength(cfBits) != 16385) {
		return;
	}

	/* REBUILT INTO A FOUNDATION-OWNED SET, WHICH IS WHERE THE CHARACTER USED TO BE LOST. */
	rebuilt = [NSCharacterSet characterSetWithBitmapRepresentation:(NSData *)cfBits];
	check([rebuilt longCharacterIsMember:0x1F600], "a set rebuilt from Core Foundation's bytes lost U+1F600");
	check([rebuilt hasMemberInPlane:1], "a set rebuilt from Core Foundation's bytes claims nothing in plane 1");
	check([rebuilt hasMemberInPlane:0], "a set rebuilt from Core Foundation's bytes claims nothing in plane 0");

	/* AND THE DOOR IS A CONTAINMENT TEST RATHER THAN A STATEMENT ABOUT PLANE 0, WHICH IT WAS: a set holding
	 * ONLY an annex character has ranges and no plane-0 members, and the old answer -- plane == 0 &&
	 * _rangeCount > 0 -- answered YES for plane 0 and NO for plane 1. THIS IS THE ASSERTION THAT FAILS
	 * AGAINST THE OLD CODE, which is why it is here. */
	{
		CFMutableCharacterSetRef only = CFCharacterSetCreateMutable(NULL);
		NSCharacterSet *rebuiltOnly;

		CFCharacterSetAddCharactersInRange(only, CFRangeMake(0x1F600, 1));
		rebuiltOnly = [NSCharacterSet characterSetWithBitmapRepresentation:
			       (NSData *)CFCharacterSetCreateBitmapRepresentation(NULL, only)];
		check([rebuiltOnly longCharacterIsMember:0x1F600],
		      "a set holding ONLY U+1F600 lost it on the way in");
		check([rebuiltOnly hasMemberInPlane:1], "a set holding ONLY U+1F600 claims nothing in plane 1");
		check(![rebuiltOnly hasMemberInPlane:0],
		      "a set holding ONLY U+1F600 claims plane 0 has members, so -hasMemberInPlane: is still not a "
		      "containment test");
	}
	check(![empty hasMemberInPlane:0], "an empty set claims plane 0 has members");

	/* BOTH WAYS, AND THEN THE BYTES: Core Foundation's bitmap for the result must be the one it produced. */
	check([rebuilt isSupersetOfSet:(id)cf] && [(id)cf isSupersetOfSet:rebuilt],
	      "the rebuilt set and Core Foundation's are not equal as supersets (rebuilt covers: %s)",
	      [rebuilt isSupersetOfSet:(id)cf] ? "yes" : "NO");
	back = CFCharacterSetCreateWithBitmapRepresentation(NULL, (CFDataRef)[rebuilt bitmapRepresentation]);
	backBits = CFCharacterSetCreateBitmapRepresentation(NULL, back);
	check(CFEqual(cfBits, backBits), "the bitmap round trip is not byte-identical (%ld bytes back, want %ld)",
	      (long)CFDataGetLength(backBits), (long)CFDataGetLength(cfBits));

	/* AND A BMP-ONLY SET STILL ANSWERS THE BARE PREFIX, so nothing that worked before changed shape. */
	plain = CFCharacterSetCreateWithCharactersInString(NULL, CFSTR("a"));
	plainBits = CFCharacterSetCreateBitmapRepresentation(NULL, plain);
	check(CFDataGetLength(plainBits) == 8192, "a BMP-only Core Foundation set answers %ld bytes, want 8192",
	      (long)CFDataGetLength(plainBits));
	check([[(id)plain bitmapRepresentation] length] == 8192,
	      "a BMP-only set through the Foundation door answers %lu bytes, want 8192",
	      (unsigned long)[[(id)plain bitmapRepresentation] length]);
}

/* AND THE TWO DOORS CORE FOUNDATION SENDS TO A FOUNDATION ARRAY, ONE OF WHICH DID NOT EXIST. CFArray.c
 * dispatches to ten selectors; nine of them this Foundation answered and the tenth -- Apple's own
 * -replaceObjectsInRange:withObjects:count:, sent by CFArrayReplaceValues -- it did not, so a range
 * replacement over a Foundation array raised NSInvalidArgumentException and took the process with it. The
 * immutability test in CFArraySortValues needed the mutable class FOUND BY NAME rather than as a class
 * reference, which is what had made Core Foundation unloadable on its own. */
static CFComparisonResult arg_compare_strings(const void *a, const void *b, void *context)
{
	(void)context;
	return (CFComparisonResult)CFStringCompare((CFStringRef)a, (CFStringRef)b, 0);
}

static void arg_cf_array_doors(void)
{
	NSMutableArray *m = [NSMutableArray arrayWithObjects:@"a", @"b", @"c", @"d", nil];
	NSArray *source = [NSArray arrayWithObjects:@"x", @"y", @"z", nil];
	NSMutableArray *sortable = [NSMutableArray arrayWithObjects:@"cherry", @"apple", @"banana", nil];
	NSArray *fixed = [NSArray arrayWithObjects:@"cherry", @"apple", nil];
	id items[3];
	id own[4];

	check([m respondsToSelector:@selector(replaceObjectsInRange:withObjects:count:)],
	      "NSMutableArray does not answer -replaceObjectsInRange:withObjects:count:, the door "
	      "CFArrayReplaceValues dispatches to");

	/* A REAL C ARRAY OUT OF A FOUNDATION ARRAY, not the array object cast to one. */
	[source getObjects:items range:NSMakeRange(0, 3)];
	[m replaceObjectsInRange:NSMakeRange(1, 2) withObjects:(const id *)items count:3];
	check([[m componentsJoinedByString:@" "] isEqualToString:@"a x y z d"],
	      "replaceObjectsInRange:{1,2} with x y z gave '%s', want 'a x y z d'",
	      [[m componentsJoinedByString:@" "] UTF8String]);

	/* THE ALIASING CASE APPLE'S CONTRACT ALLOWS: the receiver's OWN objects passed back in. This is why the
	 * implementation takes them first -- without that, removing the range releases them before they are read. */
	[m getObjects:own range:NSMakeRange(0, 4)];
	[m replaceObjectsInRange:NSMakeRange(0, 1) withObjects:(const id *)own count:4];
	check([[m componentsJoinedByString:@" "] isEqualToString:@"a x y z x y z d"],
	      "replacing {0,1} with the receiver's own four gave '%s', want 'a x y z x y z d'",
	      [[m componentsJoinedByString:@" "] UTF8String]);

	[m replaceObjectsInRange:NSMakeRange(1, 3) withObjects:NULL count:0];
	check([[m componentsJoinedByString:@" "] isEqualToString:@"a x y z d"],
	      "replacing {1,3} with nothing gave '%s', want 'a x y z d'",
	      [[m componentsJoinedByString:@" "] UTF8String]);

	/* AND THE SORT, WHOSE IMMUTABILITY TEST IS THE DOOR THAT HAD TO FIND ITS CLASS BY NAME: a mutable
	 * Foundation array is sorted IN PLACE, and an immutable one is left alone. Both halves matter -- the
	 * second is what the isKindOfClass: test exists for. */
	CFArraySortValues((CFMutableArrayRef)sortable, CFRangeMake(0, (CFIndex)[sortable count]),
			  arg_compare_strings, NULL);
	check([[sortable componentsJoinedByString:@" "] isEqualToString:@"apple banana cherry"],
	      "CFArraySortValues gave '%s' for a Foundation NSMutableArray, want 'apple banana cherry'",
	      [[sortable componentsJoinedByString:@" "] UTF8String]);
	CFArraySortValues((CFMutableArrayRef)fixed, CFRangeMake(0, (CFIndex)[fixed count]),
			  arg_compare_strings, NULL);
	check([[fixed componentsJoinedByString:@" "] isEqualToString:@"cherry apple"],
	      "CFArraySortValues REORDERED an NSArray: '%s', want 'cherry apple'",
	      [[fixed componentsJoinedByString:@" "] UTF8String]);
}

/* ---------------------------------------------------------------------------------------------------- */
/* AND THE TYPE ENCODINGS THE BRIDGE PUBLISHES, WHICH ARE PART OF A SELECTOR'S IDENTITY.                */
/* ---------------------------------------------------------------------------------------------------- */
/* THIS CASE EXISTS BECAUSE NINETEEN OF THEM WERE WRONG AND NOTHING HERE COULD SEE IT. libobjc2 keys typed
 * dispatch on (selector, encoding), so a row that publishes one encoding where the compiler publishes
 * another gets NO SEND at all: the message takes the superclass's implementation instead. For
 * -[__NSCFURL isFileURL] that was NSURL's own, over an ivar a Core Foundation object never had, so an
 * HTTP URL answered that it WAS a file URL. The rows said `c` for BOOL on every architecture and the
 * compiler says `B` on arm64, where BOOL is _Bool -- measured there as three Foundation cases gone from
 * 77/77 to 74/77 (CFURL, CFCharacterSet, CFRunLoopTimer). On x86_64 both answer `c`, which is why the
 * suite ran green here while the bridge was broken there.
 *
 * TWO CHECKS, AND THE FIRST IS THE ONE THAT CAN FAIL ON THE MACHINE RUNNING THE SUITE: that the runtime
 * header's OBJC_BOOL_TYPE_ENCODING agrees with the compiler's own @encode(BOOL) for this target. The
 * second walks every class Core Foundation owns and compares the return type of each method it REGISTERS
 * with the return type of the method it REPLACES -- the compiler's own encoding of the same selector on
 * the Foundation class below it. A row that disagrees with the protocol it stands in for is a send that
 * goes somewhere else, whatever the reason and whichever type is involved. */
static void arg_bridge_encodings(void)
{
	int compared = 0, wrong = 0, walked = 0;
	int seen_url = 0, seen_charset = 0, seen_timer = 0;
	int count, i;
	Class *classes;

	/* THE OWNED CLASSES ARE REGISTERED LAZILY, on the first object of the type -- and the object has to be
	 * CORE FOUNDATION's. A Foundation date or string does not register __NSCFDate or __NSCFString, so
	 * g_cases is no good here: every type below is built at its own C door, which is what makes the
	 * registration happen. */
	{
		const UInt8 bytes[] = { 'a', 'b', 'c' };
		CFRunLoopTimerContext context = { 0, NULL, NULL, NULL, NULL };
		int one = 1;
		CFTypeRef made[] = {
			CFStringCreateWithCString(NULL, "abc", kCFStringEncodingUTF8),
			CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks),
			CFDataCreate(NULL, bytes, (CFIndex)sizeof bytes),
			CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks,
					   &kCFTypeDictionaryValueCallBacks),
			CFSetCreate(NULL, NULL, 0, &kCFTypeSetCallBacks),
			CFNumberCreate(NULL, kCFNumberIntType, &one),
			CFDateCreate(NULL, 0.0),
			CFURLCreateWithString(NULL, CFSTR("http://example.com/"), NULL),
			CFTimeZoneCreateWithName(NULL, CFSTR("UTC"), false),
			CFLocaleCopyCurrent(),
			CFErrorCreate(NULL, CFSTR("d"), 1, NULL),
			CFAttributedStringCreate(NULL, CFSTR("x"), NULL),
			CFCharacterSetCreateWithCharactersInString(NULL, CFSTR("abc")),
			CFReadStreamCreateWithBytesNoCopy(NULL, bytes, (CFIndex)sizeof bytes, kCFAllocatorNull),
			CFWriteStreamCreateWithAllocatedBuffers(NULL, kCFAllocatorSystemDefault),
			CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + 100.0, 5.0, 0, 0, NULL, &context),
			CFCalendarCreateWithIdentifier(NULL, CFSTR("gregorian")),
			/* AND THE MUTABLE HALF, which has its own classes and its own rows. */
			CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks),
			CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
						  &kCFTypeDictionaryValueCallBacks),
			CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks),
			CFStringCreateMutable(NULL, 0),
			CFDataCreateMutable(NULL, 0),
			CFCharacterSetCreateMutable(NULL),
			CFAttributedStringCreateMutable(NULL, 0),
		};

		for (size_t m = 0; m < sizeof made / sizeof made[0]; m++) {
			if (made[m] != NULL) {
				CFRelease(made[m]);
			}
		}
	}

	/* THE HEADER AND THE COMPILER HAVE TO AGREE, on whatever this target's BOOL is. */
	check(@encode(BOOL)[0] == OBJC_BOOL_TYPE_ENCODING[0],
	      "OBJC_BOOL_TYPE_ENCODING is '%s' but the compiler encodes BOOL as '%s'",
	      OBJC_BOOL_TYPE_ENCODING, @encode(BOOL));

	count = objc_getClassList(NULL, 0);
	classes = malloc(sizeof(Class) * (size_t)(count > 0 ? count : 1));
	if (classes == NULL) {
		check(0, "no room for the class list");
		return;
	}
	count = objc_getClassList(classes, count);
	for (i = 0; i < count; i++) {
		const char *name = class_getName(classes[i]);
		Method *methods;
		unsigned int n = 0, j;

		if (name == NULL || strncmp(name, "__NSCF", 6) != 0) {
			continue;
		}
		walked++;
		seen_url |= strcmp(name, "__NSCFURL") == 0;
		seen_charset |= strcmp(name, "__NSCFCharacterSet") == 0;
		seen_timer |= strcmp(name, "__NSCFRunLoopTimer") == 0;
		methods = class_copyMethodList(classes[i], &n);
		if (methods == NULL) {
			continue;
		}
		for (j = 0; j < n; j++) {
			SEL sel = method_getName(methods[j]);
			const char *mine = method_getTypeEncoding(methods[j]);
			Method replaced;
			const char *theirs;

			if (sel == NULL || mine == NULL || mine[0] == '\0') {
				continue;
			}
			/* THE CLASS BELOW IS FOUNDATION'S, which is where the encoding the compiler would publish
			 * for this selector lives -- including for selectors that only a superclass implements, since
			 * class_getInstanceMethod walks upwards. */
			replaced = class_getInstanceMethod(class_getSuperclass(classes[i]), sel);
			if (replaced == NULL) {
				continue;	/* a door Foundation has no counterpart for: nothing to compare with */
			}
			theirs = method_getTypeEncoding(replaced);
			if (theirs == NULL || theirs[0] == '\0') {
				continue;
			}
			compared++;
			if (mine[0] != theirs[0]) {
				wrong++;
				fprintf(stderr, "  %s -%s publishes '%s', Foundation's method is '%s'\n",
					name, sel_getName(sel), mine, theirs);
			}
		}
		free(methods);
	}
	free(classes);
	check(walked >= 15, "only %d Core Foundation-owned classes were found, want the table's worth", walked);
	check(seen_url && seen_charset && seen_timer,
	      "the three classes the arm64 BOOL regression hit were not all walked (url %d, charset %d, timer %d)",
	      seen_url, seen_charset, seen_timer);
	check(compared > 20, "only %d bridge method encodings could be compared, want the table's worth", compared);
	check(wrong == 0, "%d bridge methods publish a return type Foundation's own method does not", wrong);
}

static const struct { const char *name; void (*fn)(void); } g_arguments[] = {
	{ "Foundation receives a native CFString",  arg_cfstring },
	{ "Foundation receives a native CFArray",   arg_cfarray },
	{ "Foundation receives a native CFData",    arg_cfdata },
	{ "Foundation receives a native CFDictionary", arg_cfdict },
	{ "Foundation receives a native CFSet",     arg_cfset },
	{ "Foundation receives a native CFNumber",  arg_cfnumber },
	{ "Foundation receives a native CFDate",    arg_cfdate },
	{ "Foundation receives a native CFNull",    arg_cfnull },
	{ "Foundation receives a native CFURL",     arg_cfurl },
	{ "Foundation receives a native CFTimeZone", arg_cftz },
	{ "Foundation receives a native CFLocale",  arg_cflocale },
	{ "Foundation receives a native CFError",   arg_cferror },
	{ "Foundation receives a native CFAttributedString", arg_cfattributed },
	{ "Foundation receives a native CFCharacterSet", arg_cfcharset },
	{ "Core Foundation's bitmap annex planes survive a round trip", arg_cfcharset_annex },
	{ "The array doors CFArrayReplaceValues and CFArraySortValues send", arg_cf_array_doors },
	{ "Foundation receives a native CFReadStream", arg_cfreadstream },
	{ "Core Foundation asks a Foundation stream for its error", arg_forward_cfstreamerror },
	{ "Core Foundation asks a Foundation calendar to compute", arg_forward_cfcalendar },
	{ "NSNumber's Booleans are Core Foundation's CFBoolean", arg_cfboolean },
	{ "A mutable array answers from storage of its own", arg_mutable_array_primitives },
	{ "Core Foundation's mutable array, from both sides", arg_mutable_cfarray },
	{ "Core Foundation's mutable dictionary, from both sides", arg_mutable_cfdictionary },
	{ "Core Foundation's mutable set, through its one storage door", arg_mutable_cfset },
	{ "Core Foundation's mutable string, from both sides", arg_mutable_cfstring },
	{ "Core Foundation's mutable data, from both sides", arg_mutable_cfdata },
	{ "Core Foundation's mutable character set, from both sides", arg_mutable_cfcharset },
	{ "Core Foundation's mutable attributed string, from both sides", arg_mutable_cfattributed },
	{ "The Core Foundation doors a surface survey found missing", arg_cf_surface_doors },
	{ "Foundation receives a native CFWriteStream", arg_cfwrite_stream },
	{ "Foundation receives a native CFRunLoopTimer", arg_cftimer },
	{ "Foundation receives a native CFCalendar", arg_cfcalendar },
	{ "The bridge publishes the encodings its protocol does", arg_bridge_encodings },
};

static void (*g_trampoline_group)(void);

static int group_trampoline(void)
{
	int before = g_fail;

	@try {
		g_trampoline_group();
	} @catch (NSException *e) {
		check(0, "raised %s: %s", [[e name] UTF8String], [[e reason] UTF8String]);
	}
	return g_fail - before;
}

/* the case a forked child was asked to run */
static const bridge_case *g_trampoline_case;

static int case_trampoline(void)
{
	return run_one_case(g_trampoline_case);
}

int main(void)
{
	int cases_ok = 0, cases_bad = 0;

	setvbuf(stdout, NULL, _IONBF, 0);

	for (size_t i = 0; i < sizeof g_cases / sizeof g_cases[0]; i++) {
		g_trampoline_case = &g_cases[i];
		if (run_in_child(g_cases[i].name, case_trampoline) == 0) {
			cases_ok++;
		} else {
			cases_bad++;
		}
	}
	for (size_t i = 0; i < sizeof g_extra_doors / sizeof g_extra_doors[0]; i++) {
		g_trampoline_group = g_extra_doors[i].fn;
		if (run_in_child(g_extra_doors[i].name, group_trampoline) == 0) {
			cases_ok++;
		} else {
			cases_bad++;
		}
	}

	for (size_t i = 0; i < sizeof g_arguments / sizeof g_arguments[0]; i++) {
		g_trampoline_group = g_arguments[i].fn;
		if (run_in_child(g_arguments[i].name, group_trampoline) == 0) {
			cases_ok++;
		} else {
			cases_bad++;
		}
	}

	for (size_t i = 0; i < sizeof g_regressions / sizeof g_regressions[0]; i++) {
		g_trampoline_group = g_regressions[i].fn;
		if (run_in_child(g_regressions[i].name, group_trampoline) == 0) {
			cases_ok++;
		} else {
			cases_bad++;
		}
	}

	printf("\nbridges: %d of %d cases passed, %d failed\n",
	       cases_ok, cases_ok + cases_bad, cases_bad);
	return cases_bad == 0 ? 0 : 1;
}
