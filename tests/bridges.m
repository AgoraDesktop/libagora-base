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
	check(object_getClass((id)native) == nil, "a Core Foundation object has a class: %s",
	      class_getName(object_getClass((id)native)));
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

static const struct { const char *name; void (*fn)(void); } g_regressions[] = {
	{ "regression: the class cluster",        reg_cluster },
	{ "regression: tagged pointers",          reg_tagged },
	{ "regression: CFSTR",                    reg_cfstr },
	{ "regression: the singletons",           reg_singletons },
	{ "regression: a native Core Foundation object", reg_native },
	{ "regression: Foundation through CF",    reg_foundation },
	{ "regression: equality across the bridge", reg_equality },
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
static void arg_cfstring(void) { CFStringRef s = CFStringCreateWithCString(NULL, "same", kCFStringEncodingUTF8); printf("    [@\"same\" isEqual:it] = %d (want 1)\n", (int)[@"same" isEqual:(id)s]); }
static void arg_cfarray(void) { CFArrayRef a = CFArrayCreate(NULL, NULL, 0, &kCFTypeArrayCallBacks); printf("    [it count] = %ld (want 0)\n", (long)[(id)a count]); }
static void arg_cfdata(void) { CFDataRef d = CFDataCreate(NULL, (const UInt8 *)"x", 1); printf("    [it length] = %ld (want 1)\n", (long)[(id)d length]); }
static void arg_cfdict(void) { CFDictionaryRef d = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); printf("    [it count] = %ld (want 0)\n", (long)[(id)d count]); }
static void arg_cfset(void) { CFSetRef x = CFSetCreate(NULL, NULL, 0, &kCFTypeSetCallBacks); printf("    [it count] = %ld (want 0)\n", (long)[(id)x count]); }
static void arg_cfnumber(void) { CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, (int[]){ 7 }); printf("    [it intValue] = %d (want 7)\n", (int)[(id)n intValue]); }
static void arg_cfdate(void) { CFDateRef d = CFDateCreate(NULL, 0.0); printf("    [it timeIntervalSinceReferenceDate] = %g (want 0)\n", (double)[(id)d timeIntervalSinceReferenceDate]); }
static void arg_cfnull(void) { printf("    [kCFNull description] = %s\n", [(id)kCFNull description] == nil ? "(nil)" : "ok"); }
static void arg_cfurl(void) { CFURLRef u = CFURLCreateWithString(NULL, CFSTR("http://example.com/a"), NULL); printf("    [it path] = %s (want /a)\n", (const char *)[[(id)u path] UTF8String]); }
static void arg_cftz(void) { CFTimeZoneRef z = CFTimeZoneCreateWithName(NULL, CFSTR("UTC"), true); printf("    [it name] = %s (want UTC)\n", (const char *)[[(id)z name] UTF8String]); }

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
