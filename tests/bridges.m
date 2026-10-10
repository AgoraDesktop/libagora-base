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
static int door_date(id o) { return CFDateGetAbsoluteTime((CFDateRef)o) == 0.0; }
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

static void regressions(void)
{
	/* THE CLUSTER. Foundation answers CFArrayGetTypeID() with five classes, and every one of them
	 * has to be recognised -- an equality test against the cluster root would match none. */
	id arrays[] = { @[], @[ @1 ], @[ @1, @2 ], @[ @1, @2, @3, @4, @5, @6, @7, @8, @9 ],
			[NSMutableArray array], [NSMutableArray arrayWithObject:@1] };
	for (size_t i = 0; i < sizeof arrays / sizeof arrays[0]; i++) {
		CFMutableArrayRef m = (CFMutableArrayRef)arrays[i];
		if ([arrays[i] isKindOfClass:[NSMutableArray class]]) {
			CFArrayAppendValue(m, CFSTR("appended"));
		}
		check(CFArrayGetCount((CFArrayRef)arrays[i]) == (CFIndex)[arrays[i] count],
		      "cluster member %s: CF count %ld vs ObjC count %ld",
		      class_getName([arrays[i] class]),
		      (long)CFArrayGetCount((CFArrayRef)arrays[i]), (long)[arrays[i] count]);
	}

	/* TAGGED POINTERS. A short @"..." literal has no isa: the pointer's tag bits hold the class.
	 * Reading offset 0 of one dereferences 0xd19766cde000002c. */
	NSString *tagged[] = { @"x", @"ab", @"hello", @"tagged", @"a somewhat longer literal string" };
	for (size_t i = 0; i < sizeof tagged / sizeof tagged[0]; i++) {
		check(CFStringGetLength((CFStringRef)tagged[i]) == (CFIndex)[tagged[i] length],
		      "tagged pointer %s: CF length %ld vs ObjC length %ld (%s)",
		      [tagged[i] UTF8String], (long)CFStringGetLength((CFStringRef)tagged[i]),
		      (long)[tagged[i] length], class_getName(object_getClass(tagged[i])));
	}

	/* CFSTR. clang's constant, whose isa is a BARE SYMBOL that libagora-base's NSCFConstantString is
	 * aliased to; its layout is clang's and not the runtime's, which is why it is a second class. */
	check(CFStringGetLength(CFSTR("x")) == 1, "CFSTR(\"x\") length %ld", (long)CFStringGetLength(CFSTR("x")));
	check([(NSString *)CFSTR("x") length] == 1, "[CFSTR(\"x\") length] %ld", (long)[(NSString *)CFSTR("x") length]);
	check(CFStringGetLength(CFSTR("")) == 0, "CFSTR(\"\") length %ld", (long)CFStringGetLength(CFSTR("")));
	check(CFEqual(CFSTR("x"), (CFStringRef)@"x"), "CFEqual(CFSTR(\"x\"), @\"x\") is false");

	/* SINGLETONS. Core Foundation's own statics have no isa at all -- 0 -- and must survive both the
	 * CF doors and CFRetain/CFRelease without being mistaken for objects. */
	CFTypeRef singles[] = { kCFBooleanTrue, kCFBooleanFalse, kCFNull, kCFAllocatorDefault };
	for (size_t i = 0; i < sizeof singles / sizeof singles[0]; i++) {
		CFRetain(singles[i]);
		CFRelease(singles[i]);
		check(CFGetTypeID(singles[i]) != 0, "singleton %zu has no type id", i);
	}
	check(CFBooleanGetValue(kCFBooleanTrue) == true, "kCFBooleanTrue is not true");

	/* A CORE FOUNDATION OBJECT WEARS NO CLASS. Registering NSString/NSArray made CF's own objects
	 * wear Foundation's classes, so CFArrayAppendValue dispatched into an immutable NSArray. */
	CFMutableArrayRef native = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
	CFArrayAppendValue(native, CFSTR("a"));
	CFArrayAppendValue(native, CFSTR("b"));
	check(CFArrayGetCount(native) == 2, "native mutable array count %ld", (long)CFArrayGetCount(native));
	check(CFArrayGetValueAtIndex(native, 0) != NULL, "native mutable array element is NULL");
	check(object_getClass((id)native) == nil, "a Core Foundation object has a class: %s",
	      class_getName(object_getClass((id)native)));
	CFRelease(native);

	/* AND THE OTHER DIRECTION, which is what toll-free means: a FOUNDATION object driven through the
	 * Core Foundation C API. */
	NSMutableArray *host = [NSMutableArray array];
	CFArrayAppendValue((CFMutableArrayRef)host, @"one");
	CFArrayAppendValue((CFMutableArrayRef)host, @"two");
	check([host count] == 2, "Foundation array after CF appends: %ld", (long)[host count]);
	check(CFArrayGetCount((CFArrayRef)host) == 2, "CF count after CF appends: %ld",
	      (long)CFArrayGetCount((CFArrayRef)host));

	/* IDENTITY, NOT CONVERSION: the CF door and the ObjC method are the same object, so a mutation
	 * through one is visible through the other. */
	check(CFArrayGetValueAtIndex((CFArrayRef)host, 0) == [host objectAtIndex:0],
	      "the same element is not the same object");

	/* MUTABLE STRINGS, because NSString's cluster is reached through NSMutableString too. */
	NSMutableString *ms = [NSMutableString stringWithString:@"abc"];
	[ms appendString:@"de"];
	check(CFStringGetLength((CFStringRef)ms) == 5, "mutable string length via CF: %ld",
	      (long)CFStringGetLength((CFStringRef)ms));

	/* CROSS-TYPE EQUALITY, which is the bridge at its most dangerous: a CF-native and a Foundation
	 * object compared by CFEqual must agree when their content does. */
	CFStringRef c1 = CFStringCreateWithCString(NULL, "same", kCFStringEncodingUTF8);
	check(CFEqual(c1, (CFStringRef)@"same"), "CFEqual(CFString, NSString) is false");
	check(CFHash(c1) == CFHash((CFStringRef)@"same"), "CFHash disagrees across the bridge");
	CFRelease(c1);
}

int main(void)
{
	setvbuf(stdout, NULL, _IONBF, 0);

	for (size_t i = 0; i < sizeof g_cases / sizeof g_cases[0]; i++) {
		const bridge_case *c = &g_cases[i];
		id obj = c->make();

		if (obj == nil) {
			check(0, "%s: the Foundation object could not be made", c->name);
			continue;
		}
		check(CFGetTypeID((CFTypeRef)obj) == c->typeID(),
		      "%s: CFGetTypeID is %lu, want %lu", c->name,
		      (unsigned long)CFGetTypeID((CFTypeRef)obj), (unsigned long)c->typeID());
		check(c->door(obj) != 0, "%s: the Core Foundation door did not answer", c->name);
		CFRetain((CFTypeRef)obj);
		CFRelease((CFTypeRef)obj);
		check(CFCopyDescription((CFTypeRef)obj) != NULL, "%s: CFCopyDescription is NULL", c->name);
	}

	regressions();

	fprintf(stderr, "\nbridges: %d passed, %d failed\n", g_pass, g_fail);
	return g_fail == 0 ? 0 : 1;
}
