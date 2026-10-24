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
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#include <string.h>

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

@end
