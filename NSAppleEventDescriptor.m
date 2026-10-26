/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAppleEventDescriptor.m — the descriptor as data: bytes, a list, or a keyword record.
 */
#import <Foundation/NSAppleEventDescriptor.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSError.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSURL.h>
#include <stdint.h>
#include <stdio.h>		/* stdio, for the refusal line's fprintf */
#include <string.h>
#include <unistd.h>		/* getpid(2), for +currentProcessDescriptor */

/* THE LONG DATETIME, WHICH IS WHAT `typeDate` CARRIES. Apple's AppleEvents type is a 64-bit float of seconds since
 * 1904-01-01 00:00:00 UTC, so the conversion is a CONSTANT rather than a calendar: the two reference dates do not move.
 * 1904 -> 1970 is 24,107 days; 1970 -> 2001 (NSDate's reference date) is 978,307,200 seconds. */
#define FN_SECONDS_1904_TO_1970	2082844800.0
#define FN_SECONDS_1904_TO_2001	3061152000.0

static DescType fn_four_char_code(OSType value)
{
	return (DescType)value;
}

static OSType fn_code_from_data(NSData *data)
{
	unsigned char bytes[4] = { 0, 0, 0, 0 };

	if (data != nil) {
		[data getBytes:bytes length:([data length] < 4 ? [data length] : 4)];
	}
	return ((OSType)bytes[0] << 24) | ((OSType)bytes[1] << 16) | ((OSType)bytes[2] << 8) | bytes[3];
}

static NSData *fn_data_from_code(OSType code)
{
	unsigned char bytes[4];

	bytes[0] = (unsigned char)((code >> 24) & 0xFF);
	bytes[1] = (unsigned char)((code >> 16) & 0xFF);
	bytes[2] = (unsigned char)((code >> 8) & 0xFF);
	bytes[3] = (unsigned char)(code & 0xFF);
	return [NSData dataWithBytes:bytes length:4];
}

/* A DOUBLE IS EIGHT BYTES BIG-ENDIAN, because that is what an AppleEvents 64-bit float is. The bits are moved through
 * a `uint64_t` rather than by casting a pointer, so the conversion is the same on either endianness of host. */
static NSData *fn_data_from_double(double value)
{
	unsigned char bytes[8];
	uint64_t bits = 0;
	int i;

	memcpy(&bits, &value, sizeof bits);
	for (i = 0; i < 8; i++) {
		bytes[i] = (unsigned char)((bits >> (56 - 8 * i)) & 0xFF);
	}
	return [NSData dataWithBytes:bytes length:8];
}

static double fn_double_from_data(NSData *data)
{
	unsigned char bytes[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
	uint64_t bits = 0;
	double value = 0.0;
	NSUInteger length;
	int i;

	if (data == nil) {
		return 0.0;
	}
	length = [data length] < 8 ? [data length] : 8;
	[data getBytes:bytes length:length];
	for (i = 0; i < 8; i++) {
		bits = (bits << 8) | bytes[i];
	}
	memcpy(&value, &bits, sizeof value);
	return value;
}

@implementation NSAppleEventDescriptor

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_descriptorType = typeNull;
	}
	return self;
}

- (instancetype)initListDescriptor
{
	self = [self init];
	if (self != nil) {
		_descriptorType = typeAEList;
		_items = [[NSMutableArray alloc] init];
	}
	return self;
}

- (instancetype)initRecordDescriptor
{
	self = [self init];
	if (self != nil) {
		_descriptorType = typeAERecord;
		_record = [[NSMutableDictionary alloc] init];
		_attributes = [[NSMutableDictionary alloc] init];
		_keywords = [[NSMutableArray alloc] init];
	}
	return self;
}

- (instancetype)initWithDescriptorType:(DescType)type bytes:(const void *)bytes length:(NSUInteger)length
{
	NSData *data = bytes != NULL ? [NSData dataWithBytes:bytes length:length] : nil;

	return [self initWithDescriptorType:type data:data];
}

- (instancetype)initWithDescriptorType:(DescType)type data:(NSData *)data
{
	self = [self init];
	if (self != nil) {
		_descriptorType = type;
		_data = [data copy];
	}
	return self;
}

- (instancetype)initWithEventClass:(AEEventClass)eventClass
			    eventID:(AEEventID)eventID
		   targetDescriptor:(NSAppleEventDescriptor *)target
			   returnID:(AEReturnID)returnID
		      transactionID:(AETransactionID)transactionID
{
	self = [self initRecordDescriptor];
	if (self != nil) {
		_isEvent = YES;
		_eventClass = eventClass;
		_eventID = eventID;
		_returnID = returnID;
		_transactionID = transactionID;
		if (target != nil) {
			[self setParamDescriptor:target forKeyword:'----'];
		}
	}
	return self;
}

- (instancetype)initWithAEDescNoCopy:(const void *)desc
{
	/* NO CARBON AEDesc EXISTS IN THIS LIBRARY: the descriptor is data, so "no copy" of a structure that does not
	 * exist is a nil rather than a half-owner of another library's memory. */
	(void)desc;
	[self release];
	return nil;
}

- (void)dealloc
{
	[_data release];
	[_items release];
	[_record release];
	[_attributes release];
	[_keywords release];
	[super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	NSAppleEventDescriptor *copy = [[[self class] allocWithZone:zone] init];

	copy->_descriptorType = _descriptorType;
	copy->_data = [_data copy];
	copy->_items = [_items mutableCopy];
	copy->_record = [_record mutableCopy];
	copy->_attributes = [_attributes mutableCopy];
	copy->_keywords = [_keywords mutableCopy];
	copy->_eventClass = _eventClass;
	copy->_eventID = _eventID;
	copy->_returnID = _returnID;
	copy->_transactionID = _transactionID;
	copy->_isEvent = _isEvent;
	return copy;
}

+ (NSAppleEventDescriptor *)nullDescriptor
{
	return [[[self alloc] initWithDescriptorType:typeNull data:nil] autorelease];
}

+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type bytes:(const void *)bytes length:(NSUInteger)length
{
	return [[[self alloc] initWithDescriptorType:type bytes:bytes length:length] autorelease];
}

+ (NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type data:(NSData *)data
{
	return [[[self alloc] initWithDescriptorType:type data:data] autorelease];
}

+ (NSAppleEventDescriptor *)descriptorWithBoolean:(Boolean)value
{
	unsigned char byte = value ? 1 : 0;

	return [self descriptorWithDescriptorType:typeBoolean bytes:&byte length:1];
}

+ (NSAppleEventDescriptor *)descriptorWithEnumCode:(OSType)value
{
	return [self descriptorWithDescriptorType:typeEnumerated data:fn_data_from_code(value)];
}

+ (NSAppleEventDescriptor *)descriptorWithInt32:(SInt32)value
{
	unsigned char bytes[4];

	bytes[0] = (unsigned char)((value >> 24) & 0xFF);
	bytes[1] = (unsigned char)((value >> 16) & 0xFF);
	bytes[2] = (unsigned char)((value >> 8) & 0xFF);
	bytes[3] = (unsigned char)(value & 0xFF);
	return [self descriptorWithDescriptorType:typeSInt32 bytes:bytes length:4];
}

+ (NSAppleEventDescriptor *)descriptorWithDouble:(double)value
{
	return [self descriptorWithDescriptorType:typeIEEE64BitFloatingPoint data:fn_data_from_double(value)];
}

/* A DATE IS A LONG DATETIME, so the door converts through the fixed 1904 reference and nothing else. An `NSDate` keeps
 * seconds since 2001; the descriptor keeps seconds since 1904; the difference is 3,061,152,000. */
+ (NSAppleEventDescriptor *)descriptorWithDate:(NSDate *)value
{
	return [self descriptorWithDescriptorType:typeDate
					     data:fn_data_from_double([value timeIntervalSinceReferenceDate] +
							      FN_SECONDS_1904_TO_2001)];
}

/* A FILE URL IS ITS OWN TYPE CODE AND ITS ABSOLUTE STRING, which is the encoding `-fileURLValue` reads back. */
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)value
{
	return [self descriptorWithDescriptorType:typeFileURL
					     data:[[value absoluteString] dataUsingEncoding:NSUTF8StringEncoding]];
}

/* A BUNDLE ID AND AN APPLICATION URL ARE THE TWO 10.11 WAYS TO NAME AN APPLICATION. Each is a string payload under the
 * type code Apple publishes for it, so the descriptor says what it names rather than only holding text. */
+ (NSAppleEventDescriptor *)descriptorWithBundleIdentifier:(NSString *)value
{
	return [self descriptorWithDescriptorType:typeApplicationBundleID
					     data:[value dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (NSAppleEventDescriptor *)descriptorWithApplicationURL:(NSURL *)value
{
	return [self descriptorWithDescriptorType:typeApplicationURL
					     data:[[value absoluteString] dataUsingEncoding:NSUTF8StringEncoding]];
}

/* A PROCESS DESCRIPTOR IS A RECORD WITH ONE KEYED ENTRY. Apple keys it `keyProcessSerialNumber` and stores a PSN; this
 * system has no ProcessSerialNumber (no Carbon, no process manager), so the entry is the process ID the operating system
 * does have, as a SInt32. The keyword is Apple's, the payload is this system's, and the header says so at the factory. */
+ (NSAppleEventDescriptor *)descriptorWithProcessIdentifier:(pid_t)value
{
	NSAppleEventDescriptor *record = [[[self alloc] initRecordDescriptor] autorelease];

	[record setDescriptor:[self descriptorWithInt32:(SInt32)value] forKeyword:keyProcessSerialNumber];
	return record;
}

+ (NSAppleEventDescriptor *)currentProcessDescriptor
{
	return [self descriptorWithProcessIdentifier:getpid()];
}

+ (NSAppleEventDescriptor *)descriptorWithTypeCode:(OSType)value
{
	return [self descriptorWithDescriptorType:typeType data:fn_data_from_code(value)];
}

+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)value
{
	NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding];

	return [self descriptorWithDescriptorType:typeUTF8Text data:bytes];
}

+ (NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)eventClass
					      eventID:(AEEventID)eventID
				     targetDescriptor:(NSAppleEventDescriptor *)target
					     returnID:(AEReturnID)returnID
					transactionID:(AETransactionID)transactionID
{
	return [[[self alloc] initWithEventClass:eventClass
					 eventID:eventID
				targetDescriptor:target
					returnID:returnID
				   transactionID:transactionID] autorelease];
}

- (DescType)descriptorType { return _descriptorType; }
- (NSData *)data { return _data; }
- (NSInteger)numberOfItems { return _items != nil ? (NSInteger)[_items count] : (NSInteger)[_record count]; }
- (NSAppleEventDescriptor *)listDescriptor { return _items != nil ? self : nil; }
- (NSAppleEventDescriptor *)recordDescriptor { return _record != nil ? self : nil; }

- (NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)index
{
	if (_items == nil || index < 0 || index >= (NSInteger)[_items count]) {
		return nil;
	}
	return [_items objectAtIndex:(NSUInteger)index];
}

- (void)insertDescriptor:(NSAppleEventDescriptor *)descriptor atIndex:(NSInteger)index
{
	if (_items == nil || descriptor == nil) {
		return;
	}
	if (index < 0 || index > (NSInteger)[_items count]) {
		index = (NSInteger)[_items count];
	}
	[_items insertObject:descriptor atIndex:(NSUInteger)index];
}

- (void)removeDescriptorAtIndex:(NSInteger)index
{
	if (_items != nil && index >= 0 && index < (NSInteger)[_items count]) {
		[_items removeObjectAtIndex:(NSUInteger)index];
	}
}

- (void)removeDecriptorAtIndex:(NSInteger)index
{
	[self removeDescriptorAtIndex:index];
}

- (AEKeyword)keywordForDescriptorAtIndex:(NSInteger)index
{
	if (_keywords == nil || index < 0 || index >= (NSInteger)[_keywords count]) {
		return 0;
	}
	return (AEKeyword)[[_keywords objectAtIndex:(NSUInteger)index] unsignedIntValue];
}

- (NSAppleEventDescriptor *)descriptorForKeyword:(AEKeyword)keyword
{
	NSNumber *key = [NSNumber numberWithUnsignedInt:keyword];
	NSAppleEventDescriptor *found = [_record objectForKey:key];

	return found != nil ? found : [_attributes objectForKey:key];
}

- (NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword
{
	return [_record objectForKey:[NSNumber numberWithUnsignedInt:keyword]];
}

- (void)setDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword
{
	NSNumber *key = [NSNumber numberWithUnsignedInt:keyword];

	if (_record == nil) {
		_record = [[NSMutableDictionary alloc] init];
		_keywords = [[NSMutableArray alloc] init];
	}
	if ([_record objectForKey:key] == nil) {
		[_keywords addObject:key];
	}
	if (descriptor != nil) {
		[_record setObject:descriptor forKey:key];
	} else {
		[_record removeObjectForKey:key];
		[_keywords removeObject:key];
	}
}

- (void)setParamDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword
{
	[self setDescriptor:descriptor forKeyword:keyword];
}

- (void)removeDescriptorWithKeyword:(AEKeyword)keyword
{
	NSNumber *key = [NSNumber numberWithUnsignedInt:keyword];

	[_record removeObjectForKey:key];
	[_keywords removeObject:key];
}

- (void)removeParamDescriptorWithKeyword:(AEKeyword)keyword
{
	[self removeDescriptorWithKeyword:keyword];
}

- (NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword
{
	return [_attributes objectForKey:[NSNumber numberWithUnsignedInt:keyword]];
}

- (void)setAttributeDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword
{
	NSNumber *key = [NSNumber numberWithUnsignedInt:keyword];

	if (_attributes == nil) {
		_attributes = [[NSMutableDictionary alloc] init];
	}
	if (descriptor != nil) {
		[_attributes setObject:descriptor forKey:key];
	} else {
		[_attributes removeObjectForKey:key];
	}
}

- (NSAppleEventDescriptor *)coerceToDescriptorType:(DescType)type
{
	if (type == _descriptorType) {
		return self;
	}
	switch (type) {
	case typeUTF8Text:
	case typeUnicodeText:
		return [NSAppleEventDescriptor descriptorWithString:[self stringValue]];
	case typeSInt32:
		return [NSAppleEventDescriptor descriptorWithInt32:[self int32Value]];
	case typeBoolean:
		return [NSAppleEventDescriptor descriptorWithBoolean:[self booleanValue]];
	case typeType:
		return [NSAppleEventDescriptor descriptorWithTypeCode:[self typeCodeValue]];
	case typeEnumerated:
		return [NSAppleEventDescriptor descriptorWithEnumCode:[self enumCodeValue]];
	case typeNull:
		return [NSAppleEventDescriptor nullDescriptor];
	default:
		return nil;
	}
}

- (Boolean)booleanValue
{
	if (_descriptorType == typeSInt32) {
		return [self int32Value] != 0;
	}
	if (_data != nil && [_data length] > 0) {
		return ((const unsigned char *)[_data bytes])[0] != 0;
	}
	return NO;
}

- (OSType)enumCodeValue { return fn_code_from_data(_data); }
- (OSType)typeCodeValue { return fn_code_from_data(_data); }

/* THE DOUBLE IS READ FROM ITS OWN TYPE, and falls back to the SInt32 door: a caller asking a `'long'` descriptor for
 * its double is asking a question with an answer, while one asking a `'doub'` descriptor is asking for the payload. */
- (double)doubleValue
{
	if (_descriptorType == typeSInt32) {
		return (double)[self int32Value];
	}
	if (_data != nil && [_data length] >= 8) {
		return fn_double_from_data(_data);
	}
	return (double)[self int32Value];
}

/* THE DATE IS A LONG DATETIME READ BACK THE WAY IT WAS WRITTEN. A descriptor that is not a date answers nil rather than
 * interpreting four arbitrary bytes as a timestamp — the same rule `-fileURLValue` states. */
- (NSDate *)dateValue
{
	if (_descriptorType != typeDate || _data == nil || [_data length] < 8) {
		return nil;
	}
	return [NSDate dateWithTimeIntervalSinceReferenceDate:fn_double_from_data(_data) - FN_SECONDS_1904_TO_2001];
}

/* A FILE URL IS ITS ABSOLUTE STRING UNDER `'furl'`, so the door is the string door plus the type check. */
- (NSURL *)fileURLValue
{
	NSString *string;

	if (_descriptorType != typeFileURL) {
		return nil;
	}
	string = [self stringValue];
	return string != nil ? [NSURL URLWithString:string] : nil;
}

- (BOOL)isRecordDescriptor { return _record != nil; }

- (SInt32)int32Value
{
	if (_data == nil || [_data length] < 4) {
		return [self booleanValue] ? 1 : 0;
	}
	return (SInt32)fn_code_from_data(_data);
}

- (NSString *)stringValue
{
	if (_descriptorType == typeUTF8Text || _descriptorType == typeUnicodeText) {
		return _data != nil ? [[[NSString alloc] initWithData:_data encoding:NSUTF8StringEncoding] autorelease] : nil;
	}
	if (_descriptorType == typeSInt32) {
		return [NSString stringWithFormat:@"%d", (int)[self int32Value]];
	}
	return _data != nil ? [[[NSString alloc] initWithData:_data encoding:NSUTF8StringEncoding] autorelease] : nil;
}

- (AEEventClass)eventClass { return _isEvent ? _eventClass : 0; }
- (AEEventID)eventID { return _isEvent ? _eventID : 0; }
- (AEReturnID)returnID { return _isEvent ? _returnID : 0; }
- (AETransactionID)transactionID { return _isEvent ? _transactionID : 0; }

- (const void *)aeDesc { return NULL; }

/* THE SEND DOOR, AND IT REFUSES BY NAME. Nothing in this library can post an Apple event: there is no Apple Event
 * Manager port, no `AESend`, and no target process to address. Answering nil with an `NSFeatureUnsupportedError` and a
 * line on stderr is the honest reply; a caller that ignores the error gets nothing delivered, which is the truth. */
- (NSAppleEventDescriptor *)sendEventWithOptions:(NSAppleEventSendOptions)sendOptions
						  timeout:(NSTimeInterval)timeoutInSeconds
						    error:(NSError **)error
{
	(void)sendOptions;
	(void)timeoutInSeconds;
	if (error != NULL) {
		*error = [NSError errorWithDomain:NSCocoaErrorDomain
					     code:NSFeatureUnsupportedError
					 userInfo:@{ NSLocalizedDescriptionKey :
						     @"NSAppleEventDescriptor: this library has no AppleEvents transport, so an event "
						     @"cannot be sent" }];
	}
	fprintf(stderr, "FOUNDATION-REFUSE: -[NSAppleEventDescriptor sendEventWithOptions:timeout:error:] has no "
			"AppleEvents transport; a descriptor is data here, and nothing can deliver an event\n");
	return nil;
}

@end
