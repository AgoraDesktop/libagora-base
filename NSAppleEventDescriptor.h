/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSAppleEventDescriptor.h — Apple events as a DATA TYPE.
 *
 * This library has no AppleEvents transport and no OSA, so nothing here SENDS an event. The descriptor itself is data:
 * a type code and either a byte payload, a list of descriptors, or a record keyed by a four-character keyword. That is
 * enough to build, inspect and pass around the values a script command deals with, and it is the plan's F10
 * disposition ("data types implemented where useful; execution refuses").
 */
#ifndef FOUNDATION_NSAPPLEEVENTDESCRIPTOR_H
#define FOUNDATION_NSAPPLEEVENTDESCRIPTOR_H

#import <CoreFoundation/CFBase.h>
#import <Foundation/NSObject.h>

@class NSData;
@class NSArray;
@class NSString;
@class NSMutableArray;
@class NSMutableDictionary;

NS_ASSUME_NONNULL_BEGIN

typedef FourCharCode DescType;
typedef FourCharCode AEEventClass;
typedef FourCharCode AEEventID;
typedef FourCharCode AEKeyword;
typedef FourCharCode AEReturnID;
typedef FourCharCode AETransactionID;

/* THE TYPE CODES THIS CLASS PRODUCES AND READS. Apple publishes the same four-character values in its AppleEvents
 * headers; only the ones this class can actually box are here. */
enum {
	typeBoolean = 'bool',
	typeEnumerated = 'enum',
	typeSInt32 = 'long',
	typeType = 'type',
	typeObjectSpecifier = 'obj ',
	typeNull = 'null',
	typeAERecord = 'reco',
	typeAEList = 'list',
	typeUTF8Text = 'utf8',
	typeUnicodeText = 'utxt'
};

@interface NSAppleEventDescriptor : NSObject <NSCopying>
{
@private
	DescType _descriptorType;
	NSData *_data;
	NSMutableArray *_items;		/* a list */
	NSMutableDictionary *_record;	/* params, keyed by NSNumber(keyword) */
	NSMutableDictionary *_attributes;
	NSMutableArray *_keywords;	/* record order, so keywordForDescriptorAtIndex: is stable */
	AEEventClass _eventClass;
	AEEventID _eventID;
	AEReturnID _returnID;
	AETransactionID _transactionID;
	BOOL _isEvent;
}

/* THE FACTORIES. `+nullDescriptor` is Apple's name for the one descriptor that exists as a value in every list. */
+ (NSAppleEventDescriptor *)nullDescriptor;
+ (nullable NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type
							    bytes:(nullable const void *)bytes
							   length:(NSUInteger)length;
+ (nullable NSAppleEventDescriptor *)descriptorWithDescriptorType:(DescType)type data:(nullable NSData *)data;
+ (NSAppleEventDescriptor *)descriptorWithBoolean:(Boolean)value;
+ (NSAppleEventDescriptor *)descriptorWithEnumCode:(OSType)value;
+ (NSAppleEventDescriptor *)descriptorWithInt32:(SInt32)value;
+ (NSAppleEventDescriptor *)descriptorWithTypeCode:(OSType)value;
+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)value;
+ (nullable NSAppleEventDescriptor *)appleEventWithEventClass:(AEEventClass)eventClass
						      eventID:(AEEventID)eventID
					     targetDescriptor:(nullable NSAppleEventDescriptor *)target
						     returnID:(AEReturnID)returnID
						transactionID:(AETransactionID)transactionID;

/* THE TREE-LOCAL DOOR, RESTATED. Apple marks `-initWithAEDescNoCopy:` designated; that door can only REFUSE here
 * (this library has no Carbon AEDesc), so the initializer that actually defines this class's state is `-init`,
 * which Apple inherits from NSObject and does not mark. Stating it is what lets every other door on the class route
 * through a designated one; the refusal below keeps its own mark and its nil answer. */
- (instancetype)init NS_DESIGNATED_INITIALIZER;
- (instancetype)initListDescriptor;
- (instancetype)initRecordDescriptor;
- (nullable instancetype)initWithDescriptorType:(DescType)type bytes:(nullable const void *)bytes length:(NSUInteger)length;
- (nullable instancetype)initWithDescriptorType:(DescType)type data:(nullable NSData *)data;
- (nullable instancetype)initWithEventClass:(AEEventClass)eventClass
				    eventID:(AEEventID)eventID
			   targetDescriptor:(nullable NSAppleEventDescriptor *)target
				   returnID:(AEReturnID)returnID
			      transactionID:(AETransactionID)transactionID;
- (nullable instancetype)initWithAEDescNoCopy:(const void *)desc NS_DESIGNATED_INITIALIZER;

@property (readonly) DescType descriptorType;
@property (nullable, readonly, copy) NSData *data;
@property (readonly) NSInteger numberOfItems;
@property (nullable, readonly, copy) NSAppleEventDescriptor *listDescriptor;
@property (nullable, readonly, copy) NSAppleEventDescriptor *recordDescriptor;

- (nullable NSAppleEventDescriptor *)descriptorAtIndex:(NSInteger)index;
- (void)insertDescriptor:(NSAppleEventDescriptor *)descriptor atIndex:(NSInteger)index;
- (void)removeDescriptorAtIndex:(NSInteger)index;
- (void)removeDecriptorAtIndex:(NSInteger)index;	/* APPLE'S SPELLING, TYPO AND ALL */
- (AEKeyword)keywordForDescriptorAtIndex:(NSInteger)index;

- (nullable NSAppleEventDescriptor *)descriptorForKeyword:(AEKeyword)keyword;
- (nullable NSAppleEventDescriptor *)paramDescriptorForKeyword:(AEKeyword)keyword;
- (void)setDescriptor:(nullable NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (void)setParamDescriptor:(NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;
- (void)removeDescriptorWithKeyword:(AEKeyword)keyword;
- (void)removeParamDescriptorWithKeyword:(AEKeyword)keyword;
- (nullable NSAppleEventDescriptor *)attributeDescriptorForKeyword:(AEKeyword)keyword;
- (void)setAttributeDescriptor:(nullable NSAppleEventDescriptor *)descriptor forKeyword:(AEKeyword)keyword;

- (nullable NSAppleEventDescriptor *)coerceToDescriptorType:(DescType)type;

@property (readonly) Boolean booleanValue;
@property (readonly) OSType enumCodeValue;
@property (readonly) SInt32 int32Value;
@property (readonly) OSType typeCodeValue;
@property (nullable, readonly, copy) NSString *stringValue;

@property (readonly) AEEventClass eventClass;
@property (readonly) AEEventID eventID;
@property (readonly) AEReturnID returnID;
@property (readonly) AETransactionID transactionID;

/* THE CARBON HANDLE, WHICH THIS LIBRARY DOES NOT HAVE. The descriptor is not an AEDesc, so the door answers NULL and
 * says so; a caller that needs the Carbon struct is on the other side of a transport this library does not ship. */
- (nullable const void *)aeDesc NS_RETURNS_INNER_POINTER;

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSAPPLEEVENTDESCRIPTOR_H */
