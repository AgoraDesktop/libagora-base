/*
 * bridges — the toll-free bridge, exhaustively.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
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
	check([[(id)a copy] isEqualToAttributedString:a],
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
	inv = [(id)w invertedSet];
	check(inv != NULL && [(id)inv characterIsMember:'z'], "the inverted set does not hold 'z'");
	mut = [(id)w mutableCopy];
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
	{ "Foundation receives a native CFReadStream", arg_cfreadstream },
	{ "Core Foundation asks a Foundation stream for its error", arg_forward_cfstreamerror },
	{ "Core Foundation asks a Foundation calendar to compute", arg_forward_cfcalendar },
	{ "NSNumber's Booleans are Core Foundation's CFBoolean", arg_cfboolean },
	{ "A mutable array answers from storage of its own", arg_mutable_array_primitives },
	{ "Foundation receives a native CFWriteStream", arg_cfwrite_stream },
	{ "Foundation receives a native CFRunLoopTimer", arg_cftimer },
	{ "Foundation receives a native CFCalendar", arg_cfcalendar },
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
