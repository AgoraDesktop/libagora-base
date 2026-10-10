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
