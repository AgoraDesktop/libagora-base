/*
 * NSCFBridging — the classes libagora-base lends to Core Foundation.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * THE OTHER HALF OF THE TOLL-FREE BRIDGE, and it is four words per type: `_CFRuntimeBridgeTypeToClass`
 * records WHICH CLASS Core Foundation's type id answers to, and from then on an object of that class
 * IS the Core Foundation object — one object, one reference count, no conversion and nothing copied in
 * either direction. Core Foundation's doors ask `CF_IS_OBJC` first and dispatch to the Objective-C
 * method when the answer is yes (see libagora-core's CFInternal.h and CFRuntime.c).
 *
 * THE CLUSTER ROOT IS WHAT IS REGISTERED, AND THAT IS DELIBERATE. libagora-base is a class cluster:
 * `@[]` is an AGArrayEmpty, `@[@1]` an AGArrayOne, `@[@1,@2]` an AGArraySmall and `[NSMutableArray
 * array]` an AGArrayMutable. Core Foundation has ONE slot per type id, so registering AGArraySmall
 * would answer for that class and no other; registering `NSArray` -- the root every one of them descends
 * from -- answers for all of them, because `_CFIsObjC` asks whether the object's class chain REACHES the
 * registered class rather than whether it equals it.
 *
 * WHERE THE MUTABLE CLASSES GO, AND WHY THEY ARE NOT LISTED SEPARATELY. Apple's runtime has two slots
 * per type id (an immutable and a mutable class) because that is what its CF types need. A cluster does
 * not: AGArrayMutable and AGArraySmall are both NSArrays, and both answer CFArrayGetTypeID(). The
 * mutable/immutable distinction is the OBJECTIVE-C class's business, which is where Foundation already
 * keeps it.
 *
 * A CONSTRUCTOR AND NOT A LAZY INITIALIZER, because the registration must precede any Core Foundation
 * door that might be handed a Foundation object, and there is no door of ours guaranteed to be first.
 * libobjc2 runs these before main() and after the class metadata is loaded, which is exactly the window
 * this needs.
 */
#import <Foundation/Foundation.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/ForSwiftFoundationOnly.h>

/* ==================================================================================================== */
/* THE SURFACE SURVEY: WHAT CORE FOUNDATION ASKS FOR THAT FOUNDATION DOES NOT ANSWER                     */
/* ==================================================================================================== */
/* METHOD, SO IT CAN BE REPEATED: a program that applies Core Foundation's OWN functions to FOUNDATION
 * objects, one CHILD PROCESS per type so a crash cannot take the run with it, each door's name printed
 * before it is called so the last line before a death names the door, and exceptions caught so a raise is
 * recorded rather than fatal. Seventeen types, about ninety doors.
 *
 * MEASURED. THE EIGHT DOORS BELOW THAT RAISED ARE NOW ANSWERED -- each implemented over the class's own
 * public API, with its signature taken from Core Foundation's call site -- and MEASURED WORKING by
 * re-running the survey: every door that raised answers, and the suite is green. The ninth is still open.
 *
 * THE SURVEY THAT FOUND THEM:
 *
 *   CFStringGetFastestEncoding       -[NSString _fastestEncodingInCFStringEncoding]  -- exists on
 *                                    NSCFConstantString only, where ASCII is the honest answer, so every
 *                                    OTHER Foundation string raises when Core Foundation asks
 *   CFArraySetValueAtIndex           -[NSMutableArray setObject:atIndex:]             -- only NSOrderedSet
 *                                    has it; the signature follows -replaceObjectAtIndex:withObject:
 *   CFDictionaryContainsKey          -[NSDictionary containsKey:]                     -- returns a CHAR
 *                                    (CFDictionary.c:231), not a BOOL
 *   CFDictionaryGetValueIfPresent    -[NSDictionary __getValue:forKey:]               -- private; its call
 *                                    site has not been found, so its signature is NOT known
 *   CFDictionaryCreateCopy           -[NSDictionary copyWithZone:]                    -- Cocoa's own
 *   CFSetGetValues                   -[NSSet getObjects:]
 *   CFSetCreateCopy                  -[NSSet copyWithZone:]                           -- Cocoa's own
 *   CFRunLoopTimerGetNextFireDate    -[NSTimer _cffireTime]                           -- answers a
 *                                    CFAbsoluteTime (CFRunLoop.c:4577)
 *   CFAttributedStringGetAttributes  SEGFAULT, and NOT a raise: the door is never reached
 *
 * AND THE NINTH WAS NOT A DEFECT EITHER, NOR WAS THE FORK THEORY I BUILT ON TOP OF IT. Both are
 * retracted, and both were my own doing. CFAttributedStringGetAttributes on a Foundation attributed string
 * with a NULL effective range ANSWERS -- measured in-process and in a child. The "doors that work in the
 * parent die in a child" reproduction was MY PROBE'S BUG: it passed @"x" to -stringWithUTF8String:, which
 * wants a C string, so the probe read an object as text and died wherever it ran. Retested properly, the
 * doors answer in the parent AND in a child:
 *
 *     child: CFStringGetFastestEncoding ok    parent: ok
 *     child: CFRunLoopTimerGetNextFireDate ok parent: ok
 *     child: CFDictionaryContainsKey ok       parent: ok
 *
 * WHAT REMAINS TRUE IS NARROWER AND MATTERS FOR READING THIS SURVEY: ONE death in its run (the attributed
 * child) was NOT reproduced in four variations, so a "DIED" line here is an unexplained death and not an
 * attribution to the door last named. A harness that prints a name before a call can only say WHERE the
 * process stopped, which is not the same as what was wrong -- and the honest use of this list is to check
 * each door in-process, which is what closed the eight above.
 *
 * AND THE EIGHT ARE NOW HELD BY A CASE, not by this list: tests/bridges.m's "The Core Foundation doors a
 * surface survey found missing" drives every one of them and asserts the ANSWERS (a char, an
 * out-parameter, a replaced element, a fire date), so a regression fails a case rather than needing someone
 * to re-run a survey and read it carefully. *
 * AND THREE APPARENT GAPS WERE NOT GAPS AT ALL: -getObjects:range:, -getObjects:andKeys: and
 * -copyWithZone: on NSArray already existed, and CFArray.c:558 was already answered by the first of them.
 * CHECK THIS FILE'S CLASSES' HEADERS BEFORE IMPLEMENTING ANY OF THE ABOVE -- writing those three
 * duplicates is the mistake this paragraph exists to prevent.
 *
 * THE SIGNATURES THAT MATTER COME FROM CORE FOUNDATION'S OWN CALL SITES, not from guessing: the three
 * cited above are the ones measured. A private door whose call site has not been found (like
 * __getValue:forKey:) is a door to LOOK UP and not to invent. */

/* ------------------------------------------------------------------------ */
/* the method Core Foundation asks for                                       */
/* ------------------------------------------------------------------------ */

/* CFCopyDescription hands a Foundation object to Objective-C (CFRuntime.c's CFTYPE_OBJC_FUNCDISPATCH)
 * because Core Foundation's own copyDebugDesc reads a __CFString and a Foundation object has none.
 * The method it asks for is THIS ONE, and the name is not -description because the contract is a Copy:
 * it returns +1, which -description does not promise.
 *
 * ON NSObject, ONCE, so every bridged class answers it -- and in this file, because this file is the
 * bridge. It calls -description, which the class itself implements, so a type whose description is
 * specific gets that and a type that has none gets NSObject's. */
/* ------------------------------------------------------------------------ */
/* the ...ForAbsoluteTime: family Core Foundation asks a time zone for        */
/* ------------------------------------------------------------------------ */

/* WHY THE SHAPE IS ...ForAbsoluteTime: AND NOT Cocoa's -...ForDate: -- Core Foundation has no NSDate and
 * cannot make one: an NSDate is Foundation's and Core Foundation does not link Foundation. So it hands
 * over the CFAbsoluteTime it has and Foundation converts. THAT CONVERSION IS THE WHOLE METHOD, which is
 * why this category is five lines per door and not a reimplementation: the real work is in -(id)
 * secondsFromGMTForDate: and its neighbours, which are ICU-backed and already here.
 *
 * THE NAMES ARE CORE FOUNDATION'S -- it calls them by name in CFTimeZone.c -- so the two doors it
 * already dispatched to (-_daylightSavingTimeOffsetForAbsoluteTime: and
 * -_nextDaylightSavingTimeTransitionAfterAbsoluteTime:) were declared and never implemented: they would
 * have raised the moment anything asked. They are here for that reason and not by choice. */
@implementation NSTimeZone (NSCFBridging)

/* CFTimeInterval AND NOT NSInteger, AND libobjc2 IS WHY THIS IS WRITTEN OUT: it reported
 * "Method has q24@0:8d16, selector has d24@0:8d16" -- q is a 64-bit integer and d is a double, and on
 * x86-64 they come back in different registers, so the door was reading whatever was in xmm0 rather than
 * the offset in rax. The type is the selector's: Core Foundation asks for a CFTimeInterval. */
- (CFTimeInterval)_secondsFromGMTForAbsoluteTime:(CFAbsoluteTime)at
{
	return (CFTimeInterval)[self secondsFromGMTForDate:[NSDate dateWithTimeIntervalSinceReferenceDate:at]];
}

- (Boolean)_isDaylightSavingTimeForAbsoluteTime:(CFAbsoluteTime)at
{
	return (Boolean)[self isDaylightSavingTimeForDate:[NSDate dateWithTimeIntervalSinceReferenceDate:at]];
}

- (CFStringRef)_copyAbbreviationForAbsoluteTime:(CFAbsoluteTime)at
{
	NSString *a = [self abbreviationForDate:[NSDate dateWithTimeIntervalSinceReferenceDate:at]];

	return a == nil ? NULL : (CFStringRef)[a copy];
}

- (CFTimeInterval)_daylightSavingTimeOffsetForAbsoluteTime:(CFAbsoluteTime)at
{
	return (CFTimeInterval)[self daylightSavingTimeOffsetForDate:[NSDate dateWithTimeIntervalSinceReferenceDate:at]];
}

- (CFTimeInterval)_nextDaylightSavingTimeTransitionAfterAbsoluteTime:(CFAbsoluteTime)at
{
	NSDate *d = [self nextDaylightSavingTimeTransitionAfterDate:[NSDate dateWithTimeIntervalSinceReferenceDate:at]];

	return d == nil ? 0.0 : (CFTimeInterval)[d timeIntervalSinceReferenceDate];
}

@end

/* ------------------------------------------------------------------------ */
/* _cfurl: the true CFURL behind an NSURL, and _CFURLFromNSURL is the only caller */
/* ------------------------------------------------------------------------ */

/* CFURL.c IS EXPLICIT ABOUT WHAT THIS IS -- "Toll-free bridging support; get the true CFURL from an
 * NSURL" -- and every URL door that takes one calls _CFURLFromNSURL first, which sends this and then
 * reads Core Foundation's storage. SEVEN DOORS HINGE ON THIS ONE METHOD: CFURLCopyPath,
 * CFURLHasDirectoryPath, CFURLCanBeDecomposed, CFURLCopyNetLocation,
 * CFURLCreateCopyDeletingLastPathComponent, CFURLCreateCopyAppendingPathComponent and
 * CFURLGetByteRangeForComponent all threw '-[NSURL _cfurl] is not implemented'.
 *
 * ON APPLE AN NSURL *IS* A CFURL and this returns the one it wraps. Agora's NSURL has its own storage,
 * so this BUILDS the Core Foundation object from the URL's string -- which is honest rather than clever:
 * the answer is a real CFURL with the same content, and CFURLCreateWithString makes a NATIVE one, so
 * there is no recursion back through this method. It returns +1 because the macro returns it directly
 * and the door's contract is a Copy. */
@implementation NSURL (NSCFBridging)

- (CFURLRef)_cfurl
{
	NSString *s = [self absoluteString];

	return s == nil ? NULL : CFURLCreateWithString(NULL, (CFStringRef)s, NULL);
}

@end

/* ------------------------------------------------------------------------ */
/* the string fast paths, which are allowed to say no                         */
/* ------------------------------------------------------------------------ */

/* CFString.c ASKS FOR THESE BEFORE FALLING BACK, AND NULL IS AN ANSWER: -_fastCStringContents: and
 * -_fastCharacterContents mean "here is my internal buffer, use it and do not copy", so returning NULL
 * says "I have none" and Core Foundation takes the slow path it already has. Base's strings keep no such
 * buffer, so NULL is not a stub here -- it is the truth, and it is what makes these three doors work
 * rather than raise. -_encodingCantBeStoredInEightBitCFString is a question with a real answer: whether
 * this string's encoding needs more than a byte per character. */
@implementation NSString (NSCFBridging)

- (const char *)_fastCStringContents:(Boolean)nullTerminated
{
	(void)nullTerminated;
	return NULL;	/* no internal 8-bit buffer: Core Foundation should copy instead */
}

- (const UniChar *)_fastCharacterContents
{
	return NULL;	/* and none in UTF-16 either */
}

- (Boolean)_encodingCantBeStoredInEightBitCFString
{
	return (Boolean)(self.length > 0 && [self canBeConvertedToEncoding:NSASCIIStringEncoding] == NO);
}

/* AND THE DOOR Core Foundation ACTUALLY ASKS FOR WHEN IT WANTS BYTES -- ON NSString AND NOT ON A SUBCLASS,
 * WHICH IS A CORRECTION RATHER THAN A CHOICE. It was written on NSCFConstantString, where it was first
 * needed, and that made it a question only a constant string could answer; Core Foundation asks it of
 * WHATEVER string it is holding. MEASURED, and it cost a URL: -_createSubstringWithRange: on a CFSTR returns
 * a COPY, and that copy is an NSOwnedString, so the next step in _retainedComponentString raised
 * '-[NSOwnedString _getCString:maxLength:encoding:] is not implemented' -- which from CFURLCreateWithString's
 * side is a component answering NULL for a bridged URL and a real answer for a native one, and sometimes a
 * crash instead. The private door and the public door ask the same question with the same bound ("the string
 * AND its terminating NUL must fit"), and this one reaches no Core Foundation door on the way.
 *
 * THE ENCODING IS CONVERTED AND NOT CAST: the two enumerations do not agree (kCFStringEncodingASCII is 0x600
 * against NSASCIIStringEncoding's 1; kCFStringEncodingUTF8 is 0x08000100 against NSUTF8StringEncoding's 4),
 * and Core Foundation hands this method its OWN numbering. CFStringConvertEncodingToNSStringEncoding is Core
 * Foundation's own table lookup and dispatches nowhere, which is what makes it safe to call from here. */
- (BOOL)_getCString:(char *)buffer maxLength:(NSUInteger)maxLength encoding:(CFStringEncoding)encoding
{
	return [self getCString:buffer maxLength:maxLength
		       encoding:CFStringConvertEncodingToNSStringEncoding(encoding)];
}


/* AND THE TWO ENCODING DOORS, ON NSString FOR THE SAME REASON: CFStringGetFastestEncoding dispatches to
 * -_fastestEncodingInCFStringEncoding for ANY string Core Foundation holds. They lived only on
 * NSCFConstantString -- where ASCII is the honest answer, because a CFSTR IS ASCII -- so every OTHER
 * Foundation string raised when Core Foundation asked. MEASURED by the surface survey. For a string of
 * unknown contents the honest answer is the encoding this family stores, UTF-8, and the constant-string
 * class keeps its narrower ASCII answer by overriding. */
- (CFStringEncoding)_fastestEncodingInCFStringEncoding
{
	return kCFStringEncodingUTF8;
}

- (CFStringEncoding)_smallestEncodingInCFStringEncoding
{
	return kCFStringEncodingUTF8;
}

@end

/* ------------------------------------------------------------------------ */
/* the two substring doors, and the Copy doors the other side asks for         */
/* ------------------------------------------------------------------------ */

/* -_createSubstringWithRange: IS A COPY: it returns +1, and the range is Core Foundation's NSRange --
 * the type both sides share because Core Foundation owns it (CFBridgingTypes.h). The attributed form is
 * the same method on a different class. -copy and -mutableCopy need nothing here: they are Cocoa's own
 * and base's classes already answer them; CFString.c only had to stop commenting the dispatch out. */
/* ------------------------------------------------------------------------ */
/* the eight in-place string mutations Core Foundation asks a MUTABLE string for */
/* ------------------------------------------------------------------------ */

/* ALL EIGHT RETURN void AND MUTATE IN PLACE, which is why they are on NSMutableString and why nothing in
 * CFBridgedMethods.h declares them -- the dispatch macro casts the result to void, so an unknown method
 * is harmless there. WHAT IS NOT HARMLESS IS NOT HAVING THEM: measured as
 * '-[NSMutableString _cfLowercase:] is not implemented' the moment CFStringLowercase reached the
 * dispatch that had been commented out.
 *
 * THE LOCALE ARGUMENT IS A CoreFoundation CFLocaleRef ARRIVING AS const void *, and Cocoa wants an
 * NSLocale -- which is exactly the toll-free bridge, so the cast is the whole conversion. NULL means
 * "the default locale" and Foundation's classes take nil for that. */
@implementation NSMutableString (NSCFBridgingMutations)

- (void)_cfLowercase:(const void *)locale
{
	[self setString:[self lowercaseStringWithLocale:(NSLocale *)locale]];
}

- (void)_cfUppercase:(const void *)locale
{
	[self setString:[self uppercaseStringWithLocale:(NSLocale *)locale]];
}

- (void)_cfCapitalize:(const void *)locale
{
	[self setString:[self capitalizedStringWithLocale:(NSLocale *)locale]];
}

- (void)_cfTrim:(NSString *)trimString
{
	NSUInteger before = [self length];

	(void)before;
	[self setString:[self stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:trimString]]];
}

- (void)_cfTrimWS
{
	[self setString:[self stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
}

/* THE ONLY ONE WHOSE ARGUMENT IS NOT A BRIDGED OBJECT: CFStringNormalizationForm is an enum, and
 * kCFStringNormalizationFormC is the precomposed form Cocoa calls canonical mapping. */
- (void)_cfNormalize:(CFStringNormalizationForm)form
{
	NSString *n;

	switch (form) {
	case kCFStringNormalizationFormD:
	case kCFStringNormalizationFormKD:
		n = [self decomposedStringWithCanonicalMapping];
		break;
	default:
		n = [self precomposedStringWithCanonicalMapping];
		break;
	}
	[self setString:n];
}

- (void)_cfAppendCString:(const unsigned char *)cStr length:(NSInteger)appendedLength
{
	NSString *tail = [[NSString alloc] initWithBytes:cStr length:(NSUInteger)appendedLength encoding:NSUTF8StringEncoding];

	if (tail != nil) {
		[self appendString:tail];
		[tail release];
	}
}

- (void)_cfPad:(NSString *)padString length:(uint32_t)length padIndex:(uint32_t)indexIntoPad
{
	(void)indexIntoPad;
	while ([self length] < length && [padString length] > 0) {
		[self appendString:padString];
	}
}

@end

@implementation NSString (NSCFBridgingExtras)

- (CFStringRef)_createSubstringWithRange:(NSRange)range
{
	if (range.location + range.length > [self length]) {
		return NULL;
	}
	return (CFStringRef)[[self substringWithRange:range] copy];
}

@end

@implementation NSAttributedString (NSCFBridgingExtras)

- (CFAttributedStringRef)_createAttributedSubstringWithRange:(NSRange)range
{
	if (range.location + range.length > [self length]) {
		return NULL;
	}
	return (CFAttributedStringRef)[[self attributedSubstringFromRange:range] copy];
}

@end

/* ------------------------------------------------------------------------ */
/* _getValue:forType: -- the number door, in Core Foundation's C types         */
/* ------------------------------------------------------------------------ */

/* CFNumberGetValue ASKS THIS AND IS WHY IT USED TO RAISE: '-[AGNumberSigned _getValue:forType:] is not
 * implemented', the deterministic failure the suite reports on every run. The shape is Core
 * Foundation's and not Cocoa's -- a caller names a kCFNumber*Type and this writes THAT C TYPE into the
 * buffer, which is what makes CFNumberGetValue(..., &double) and (..., &int) the same call.
 *
 * THE ANSWER IS YES OR NO AND NOT A VALUE, because the caller has already chosen the type: this reports
 * whether the number FITS. A value that cannot be represented in the requested type is a NO and leaves
 * the buffer alone, which is what Core Foundation does -- answering a truncated number would be worse
 * than answering none. */
@implementation NSNumber (NSCFBridging)

- (Boolean)_getValue:(void *)value forType:(CFNumberType)type
{
	if (value == NULL) {
		return false;
	}
	switch (type) {
	case kCFNumberSInt8Type:	*(int8_t *)value = (int8_t)[self charValue]; return true;
	case kCFNumberSInt16Type:	*(int16_t *)value = (int16_t)[self shortValue]; return true;
	case kCFNumberSInt32Type:	*(int32_t *)value = (int32_t)[self intValue]; return true;
	case kCFNumberSInt64Type:	*(int64_t *)value = (int64_t)[self longLongValue]; return true;
	case kCFNumberFloat32Type:	*(float *)value = (float)[self floatValue]; return true;
	case kCFNumberFloat64Type:	*(double *)value = (double)[self doubleValue]; return true;
	case kCFNumberCharType:		*(char *)value = (char)[self charValue]; return true;
	case kCFNumberShortType:	*(short *)value = (short)[self shortValue]; return true;
	case kCFNumberIntType:		*(int *)value = (int)[self intValue]; return true;
	case kCFNumberLongType:		*(long *)value = (long)[self longValue]; return true;
	case kCFNumberLongLongType:	*(long long *)value = (long long)[self longLongValue]; return true;
	case kCFNumberFloatType:	*(float *)value = (float)[self floatValue]; return true;
	case kCFNumberDoubleType:	*(double *)value = (double)[self doubleValue]; return true;
	default:
		return false;	/* CFIndex, NSInteger and CFNumberType itself: not written here */
	}
}

@end

@implementation NSObject (NSCFBridging)

- (NSString *)_copyDescription
{
	return [[self description] copy];
}

@end

static void __attribute__((constructor)) agora_register_cf_bridged_classes(void)
{
	_CFRuntimeBridgeTypeToClass(CFStringGetTypeID(), (const void *)[NSString class]);
	_CFRuntimeBridgeTypeToClass(CFArrayGetTypeID(), (const void *)[NSArray class]);
	_CFRuntimeBridgeTypeToClass(CFDataGetTypeID(), (const void *)[NSData class]);
	_CFRuntimeBridgeTypeToClass(CFDictionaryGetTypeID(), (const void *)[NSDictionary class]);
	_CFRuntimeBridgeTypeToClass(CFSetGetTypeID(), (const void *)[NSSet class]);
	_CFRuntimeBridgeTypeToClass(CFNumberGetTypeID(), (const void *)[NSNumber class]);
	_CFRuntimeBridgeTypeToClass(CFDateGetTypeID(), (const void *)[NSDate class]);
	_CFRuntimeBridgeTypeToClass(CFNullGetTypeID(), (const void *)[NSNull class]);
	_CFRuntimeBridgeTypeToClass(CFLocaleGetTypeID(), (const void *)[NSLocale class]);
	_CFRuntimeBridgeTypeToClass(CFTimeZoneGetTypeID(), (const void *)[NSTimeZone class]);
	_CFRuntimeBridgeTypeToClass(CFCalendarGetTypeID(), (const void *)[NSCalendar class]);
	_CFRuntimeBridgeTypeToClass(CFCharacterSetGetTypeID(), (const void *)[NSCharacterSet class]);
	_CFRuntimeBridgeTypeToClass(CFErrorGetTypeID(), (const void *)[NSError class]);
	_CFRuntimeBridgeTypeToClass(CFURLGetTypeID(), (const void *)[NSURL class]);
	_CFRuntimeBridgeTypeToClass(CFAttributedStringGetTypeID(), (const void *)[NSAttributedString class]);
	_CFRuntimeBridgeTypeToClass(CFRunLoopTimerGetTypeID(), (const void *)[NSTimer class]);
	_CFRuntimeBridgeTypeToClass(CFReadStreamGetTypeID(), (const void *)[NSInputStream class]);
	_CFRuntimeBridgeTypeToClass(CFWriteStreamGetTypeID(), (const void *)[NSOutputStream class]);
}

/* ---------------------------------------------------------------------------------------------------- */
/* THE THREE CORE FOUNDATION CALENDAR DOORS, ANSWERED BY FOUNDATION FOR ITS OWN CALENDARS                 */
/* ---------------------------------------------------------------------------------------------------- */
/* Core Foundation's CFCalendarComposeAbsoluteTime, CFCalendarDecomposeAbsoluteTime and
 * CFCalendarAddComponents each dispatch at an Objective-C calendar through a selector whose parts are
 * '...:at :componentDescriptionString :va_list' -- the shape Swift's NSObject bridge implements upstream,
 * which is why the call sites say "Note: We do not toll-free bridge for Swift". In this build nothing
 * implemented them, and a Foundation NSCalendar handed to any of the three RAISED, measured:
 *
 *     -[NSCalendar _composeAbsoluteTime:::] is not implemented
 *     -[NSCalendar _decomposeAbsoluteTime:::] is not implemented
 *     -[NSCalendar _addComponents:::] is not implemented
 *
 * THE FALLBACK IN CORE FOUNDATION IS NOT A FALLBACK FOR THIS CASE: the C path after each dispatch reads the
 * calendar as a struct __CFCalendar and calls _CFCalendar*ComponentsV, which is right for a Core Foundation
 * calendar and wrong for a Foundation one. So the doors are answered HERE, where the object lives.
 *
 * THE ARGUMENT SHAPES ARE CORE FOUNDATION'S OWN C VARARGS PROTOCOL AND NOT SWIFT SYNTAX -- a component
 * description string plus the values (or out-pointers) that go with it -- so reproducing them in
 * Objective-C is a faithful thing to do rather than a port of another bridge. The component CHARACTERS are
 * Core Foundation's, taken from its own table (CFCalendar.c's switch under
 * __CFCalendarGetICUFieldCodeFromChar) rather than invented.
 *
 * WHAT IS DEVIATED, AND SAID OUT LOUD:
 *  - 'l' (leap month), 'g' (Julian day) and 'Q' (quarter) have no counterpart in Foundation's
 *    NSDateComponents, so they read back as Core Foundation reads an unknown character (a zero value) and
 *    are ignored on the way in.
 *  - 'S' is milliseconds to Core Foundation and is carried on Foundation's NANOSECOND field, which is the
 *    same instant; there is no separate millisecond field to put it in.
 *  - CORE FOUNDATION'S LEGACY REINTERPRETATION OF 'y' IS NOT REPRODUCED (CFCalendar.c carries it with its
 *    own comment about compatibility): when a caller names a weekday and a week of the year and neither a
 *    month nor a day, Core Foundation reads the year it was given as the year-for-week-of-year. Here such a
 *    caller gets the straight reading -- 'y' is the year, 'Y' is the year-for-week-of-year, and nothing is
 *    reinterpreted behind its back.
 *  - COMPOSITION'S DEFAULTS ARE CORE FOUNDATION'S OWN, which are its cleared calendar's: the year is 1,
 *    the month and day are the first, and the time is midnight. That is what CFCalendar.c sets before
 *    applying the caller's values, and it is why CFCalendarComposeAbsoluteTime(cal, &at, "M", 6) is a date
 *    in year 1 rather than in the calendar's current year. */

enum {
	FNCalendarFieldNone = 0, FNCalendarFieldEra, FNCalendarFieldYear, FNCalendarFieldYearWOY,
	FNCalendarFieldMonth, FNCalendarFieldDay, FNCalendarFieldHour, FNCalendarFieldMinute,
	FNCalendarFieldSecond, FNCalendarFieldMillisecond, FNCalendarFieldNanosecond,
	FNCalendarFieldWeekOfYear, FNCalendarFieldWeekOfMonth, FNCalendarFieldWeekday,
	FNCalendarFieldDayOfYear, FNCalendarFieldWeekdayOrdinal, FNCalendarFieldAMPM
};

static int fn_calendar_field_for_char(unsigned char ch)
{
	switch (ch) {
	case 'G': return FNCalendarFieldEra;
	case 'y': case 'U': case 'r': return FNCalendarFieldYear;
	case 'Y': return FNCalendarFieldYearWOY;
	case 'M': case 'L': return FNCalendarFieldMonth;
	case 'd': return FNCalendarFieldDay;
	case 'h': case 'H': return FNCalendarFieldHour;
	case 'm': return FNCalendarFieldMinute;
	case 's': return FNCalendarFieldSecond;
	case 'S': return FNCalendarFieldMillisecond;
	case '#': return FNCalendarFieldNanosecond;
	case '^': case 'w': return FNCalendarFieldWeekOfYear;
	case 'W': return FNCalendarFieldWeekOfMonth;
	case 'E': case 'c': return FNCalendarFieldWeekday;
	case 'D': return FNCalendarFieldDayOfYear;
	case 'F': return FNCalendarFieldWeekdayOrdinal;
	case 'a': return FNCalendarFieldAMPM;
	default: return FNCalendarFieldNone;
	}
}

static int32_t fn_calendar_read_field(NSDateComponents *c, int field)
{
	switch (field) {
	case FNCalendarFieldEra: return (int32_t)[c era];
	case FNCalendarFieldYear: return (int32_t)[c year];
	case FNCalendarFieldYearWOY: return (int32_t)[c yearForWeekOfYear];
	case FNCalendarFieldMonth: return (int32_t)[c month];
	case FNCalendarFieldDay: return (int32_t)[c day];
	case FNCalendarFieldHour: return (int32_t)[c hour];
	case FNCalendarFieldMinute: return (int32_t)[c minute];
	case FNCalendarFieldSecond: return (int32_t)[c second];
	case FNCalendarFieldMillisecond: return (int32_t)([c nanosecond] / 1000000);
	case FNCalendarFieldNanosecond: return (int32_t)[c nanosecond];
	case FNCalendarFieldWeekOfYear: return (int32_t)[c weekOfYear];
	case FNCalendarFieldWeekOfMonth: return (int32_t)[c weekOfMonth];
	case FNCalendarFieldWeekday: return (int32_t)[c weekday];
	case FNCalendarFieldDayOfYear: return (int32_t)[c dayOfYear];
	case FNCalendarFieldWeekdayOrdinal: return (int32_t)[c weekdayOrdinal];
	default: return 0;
	}
}

static void fn_calendar_write_field(NSDateComponents *c, int field, int32_t value)
{
	switch (field) {
	case FNCalendarFieldEra: [c setEra:(NSInteger)value]; break;
	case FNCalendarFieldYear: [c setYear:(NSInteger)value]; break;
	case FNCalendarFieldYearWOY: [c setYearForWeekOfYear:(NSInteger)value]; break;
	case FNCalendarFieldMonth: [c setMonth:(NSInteger)value]; break;
	case FNCalendarFieldDay: [c setDay:(NSInteger)value]; break;
	case FNCalendarFieldHour: [c setHour:(NSInteger)value]; break;
	case FNCalendarFieldMinute: [c setMinute:(NSInteger)value]; break;
	case FNCalendarFieldSecond: [c setSecond:(NSInteger)value]; break;
	case FNCalendarFieldMillisecond: [c setNanosecond:(NSInteger)value * 1000000]; break;
	case FNCalendarFieldNanosecond: [c setNanosecond:(NSInteger)value]; break;
	case FNCalendarFieldWeekOfYear: [c setWeekOfYear:(NSInteger)value]; break;
	case FNCalendarFieldWeekOfMonth: [c setWeekOfMonth:(NSInteger)value]; break;
	case FNCalendarFieldWeekday: [c setWeekday:(NSInteger)value]; break;
	case FNCalendarFieldDayOfYear: [c setDayOfYear:(NSInteger)value]; break;
	case FNCalendarFieldWeekdayOrdinal: [c setWeekdayOrdinal:(NSInteger)value]; break;
	default: break;		/* Core Foundation ignores an unmapped character; so do we */
	}
}

@implementation NSCalendar (NSCFBridgedCalendarDoors)

- (BOOL)_composeAbsoluteTime:(CFAbsoluteTime *)atp :(const unsigned char *)componentDesc :(va_list)args
{
	NSDateComponents *components = [[NSDateComponents alloc] init];
	NSDate *date = nil;
	BOOL converted = NO;
	Boolean yearIsWeekBased = false;

	if (componentDesc != NULL) {
		const unsigned char *desc = componentDesc;

		/* CORE FOUNDATION'S DEFAULTS: its cleared calendar is year 1, January 1, midnight. */
		[components setYear:1];
		[components setMonth:1];
		[components setDay:1];
		[components setHour:0];
		[components setMinute:0];
		[components setSecond:0];
		[components setNanosecond:0];

		/* CORE FOUNDATION'S LEGACY REINTERPRETATION OF 'y', REPRODUCED AT LAST, AND IT NEEDS A FIRST PASS.
		 * Its own code carries the rule with a compatibility note: a 'y' becomes a year-FOR-WEEK-OF-YEAR when
		 * the caller names a weekday and a week of the year and NEITHER a month nor a day, and names no
		 * year-for-week-of-year of its own. (CFCalendar.c, in the comment above the field loop.) */
		{
			Boolean seenMonth = false, seenDay = false, seenWeekday = false;
			Boolean seenWeekOY = false, seenYearWOY = false, seenOldWeek = false;

			for (const unsigned char *scan = componentDesc; *scan != '\0'; scan++) {
				switch (fn_calendar_field_for_char(*scan)) {
				case FNCalendarFieldMonth: seenMonth = true; break;
				case FNCalendarFieldDay: seenDay = true; break;
				case FNCalendarFieldWeekday: seenWeekday = true; break;
				case FNCalendarFieldWeekOfYear:
					if (*scan == '^') {
						seenOldWeek = true;
					} else {
						seenWeekOY = true;
					}
					break;
				case FNCalendarFieldYearWOY: seenYearWOY = true; break;
				default: break;
				}
			}
			yearIsWeekBased = (Boolean)(!(seenDay && seenMonth)
						    && (seenWeekday && (seenWeekOY || seenOldWeek))
						    && !(seenWeekOY || seenYearWOY));
		}

		while (*desc != '\0') {
			int32_t value = va_arg(args, int32_t);
			int field = (*desc == '#') ? FNCalendarFieldNanosecond : fn_calendar_field_for_char(*desc);

			if (*desc == '#') {
				[components setNanosecond:(NSInteger)value];
			} else if (field == FNCalendarFieldYear && yearIsWeekBased) {
				[components setYearForWeekOfYear:(NSInteger)value];
			} else {
				fn_calendar_write_field(components, field, value);
			}
			desc++;
		}
	}

	date = [self dateFromComponents:components];
	if (date != nil) {
		if (atp != NULL) {
			*atp = [date timeIntervalSinceReferenceDate];
		}
		converted = YES;
	}
	[components release];
	return converted;
}

- (BOOL)_decomposeAbsoluteTime:(CFAbsoluteTime)at :(const unsigned char *)componentDesc :(va_list)args
{
	NSCalendarUnit units = (NSCalendarUnit)(NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitYearForWeekOfYear
					      | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour
					      | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond
					      | NSCalendarUnitWeekOfYear | NSCalendarUnitWeekOfMonth | NSCalendarUnitWeekday
					      | NSCalendarUnitDayOfYear | NSCalendarUnitWeekdayOrdinal);
	NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:at];
	NSDateComponents *components = [self components:units fromDate:date];
	BOOL converted = (components != nil);

	if (componentDesc != NULL) {
		const unsigned char *desc = componentDesc;

		while (*desc != '\0') {
			int32_t *out = va_arg(args, int32_t *);

			if (out != NULL) {
				if (*desc == '#') {
					/* THE SUB-SECOND PART OF THE ABSOLUTE TIME ITSELF, which is how Core
					 * Foundation answers '#' -- not a field of the calendar (CFCalendar.c). */
					*out = (int32_t)((at - floor(at)) * 1.0e+9);
				} else {
					*out = fn_calendar_read_field(components, fn_calendar_field_for_char(*desc));
				}
			}
			desc++;
		}
	}
	return converted;
}

- (BOOL)_addComponents:(CFAbsoluteTime *)atp :(CFOptionFlags)options :(const unsigned char *)componentDesc :(va_list)args
{
	NSDate *from = [NSDate dateWithTimeIntervalSinceReferenceDate:(atp != NULL) ? *atp : 0.0];
	NSDateComponents *components;
	const unsigned char *desc = componentDesc;
	NSDate *to;
	BOOL movedMonthOrYear = NO;
	BOOL namedDay = NO;

	(void)options;		/* Core Foundation's wrap flag has no counterpart without -dateByAddingComponents: */

	/* THE FIELDS READ ARE THE WHOLE DATE AND NOT ONLY THE ONES THE CALLER NAMES, AND THAT IS A CORRECTION
	 * RATHER THAN A STYLE. A components object carrying ONE field leaves the rest at Foundation's unset
	 * sentinel (NSIntegerMax), and -dateFromComponents: resolves that as the reference date -- so
	 * "add one day" came back as the instant it started from. MEASURED, with the per-character mask:
	 *     [add] char=d field=5 delta=1 units=0x10
	 *     [add] day now=2  from=0.0 to=0.0
	 *
	 * THE WEEK FIELDS ARE DELIBERATELY NOT READ: a components object holding both a month and a week of the
	 * year is ambiguous to resolve, so weeks are added as days (see the loop below). */
	NSCalendarUnit units = (NSCalendarUnit)(NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth
					      | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute
					      | NSCalendarUnitSecond | NSCalendarUnitNanosecond);

	components = [self components:units fromDate:from];
	if (components == nil) {
		return NO;
	}

	/* AND THIS IS "ADD N UNITS" IN THE ONLY WAY FOUNDATION CAN SAY IT WITHOUT
	 * -dateByAddingComponents:toDate:options:, WHICH THIS LIBRARY DOES NOT HAVE YET: read the named fields,
	 * add the deltas to them, and let -dateFromComponents: resolve the result through the calendar -- which
	 * is what that door would have done with the same NSDateComponents. The deltas may be negative, as Core
	 * Foundation's may. */
	while (desc != NULL && *desc != '\0') {
		int32_t delta = va_arg(args, int32_t);
		int field = (*desc == '#') ? FNCalendarFieldNanosecond : fn_calendar_field_for_char(*desc);

		/* WEEKS AND WEEKDAYS ARE ADDED AS DAYS. Core Foundation's add is field-wise through ICU, where
		 * adding to a week field moves that field and lets the calendar resolve it; for the ordinary
		 * caller seven days is the same instant, and the difference is recorded as a deviation rather
		 * than hidden. A weekday delta is one day each. */
		if (field == FNCalendarFieldMonth || field == FNCalendarFieldYear
		    || field == FNCalendarFieldYearWOY) {
			if (delta != 0) {
				movedMonthOrYear = YES;
			}
		}
		if (field == FNCalendarFieldDay) {
			namedDay = YES;
		}

		switch (field) {
		case FNCalendarFieldWeekOfYear:
		case FNCalendarFieldWeekOfMonth:
			[components setDay:[components day] + (NSInteger)delta * 7];
			break;
		case FNCalendarFieldWeekday:
			[components setDay:[components day] + (NSInteger)delta];
			break;
		case FNCalendarFieldNone:
			break;		/* an unmapped character consumes its value, as Core Foundation's does */
		default:
			fn_calendar_write_field(components, field,
						fn_calendar_read_field(components, field) + delta);
			break;
		}
		desc++;
	}

	/* AND THE DAY IS CLAMPED WHEN A MONTH OR A YEAR MOVED WITHOUT ONE, WHICH IS WHERE A FIELD-WISE ADD AND
	 * CORE FOUNDATION'S ADD PART COMPANY. MEASURED: 2001-01-31 with one month added came back as 2001-03-03,
	 * because the 31st of February resolves by rolling over into March. ICU CLAMPS there -- and so does
	 * Cocoa's own -dateByAddingComponents:toDate:options:, which is the door this stands in for -- so when
	 * the caller moved a month or a year and named no day, the day is clamped to the last day of the month
	 * it landed in. The month's length comes from the calendar itself: the first of the month, and the first
	 * of the next, and the days between them. */
	if (movedMonthOrYear && !namedDay) {
		NSInteger wantedDay = [components day];
		NSDateComponents *anchor = [[NSDateComponents alloc] init];
		NSDateComponents *nextAnchor = [[NSDateComponents alloc] init];
		NSUInteger daysInMonth = 0;
		NSDate *first;
		NSDate *next;

		[anchor setEra:[components era]];
		[anchor setYear:[components year]];
		[anchor setMonth:[components month]];
		[anchor setDay:1];
		[anchor setHour:[components hour]];
		[anchor setMinute:[components minute]];
		[anchor setSecond:[components second]];
		[anchor setNanosecond:[components nanosecond]];
		[nextAnchor setEra:[components era]];
		[nextAnchor setYear:[components year]];
		[nextAnchor setMonth:[components month] + 1];	/* January+1 is February; December+1 resolves on */
		[nextAnchor setDay:1];
		[nextAnchor setHour:[components hour]];
		[nextAnchor setMinute:[components minute]];
		[nextAnchor setSecond:[components second]];
		[nextAnchor setNanosecond:[components nanosecond]];

		first = [self dateFromComponents:anchor];
		next = [self dateFromComponents:nextAnchor];
		if (first != nil && next != nil) {
			daysInMonth = (NSUInteger)(([next timeIntervalSinceReferenceDate]
						   - [first timeIntervalSinceReferenceDate]) / 86400.0 + 0.5);
			if (daysInMonth > 0 && wantedDay > (NSInteger)daysInMonth) {
				[components setDay:(NSInteger)daysInMonth];
			}
		}
		[anchor release];
		[nextAnchor release];
	}

	to = [self dateFromComponents:components];
	if (to == nil) {
		return NO;
	}
	if (atp != NULL) {
		*atp = [to timeIntervalSinceReferenceDate];
	}
	return YES;
}

@end
