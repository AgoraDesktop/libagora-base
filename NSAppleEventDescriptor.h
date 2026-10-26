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
#import <Foundation/NSDate.h>		/* NSTimeInterval, the send timeout's type */
#include <sys/types.h>		/* pid_t, the process descriptor's identifier */

@class NSData;
@class NSError;
@class NSArray;
@class NSString;
@class NSURL;
@class NSMutableArray;
@class NSMutableDictionary;

NS_ASSUME_NONNULL_BEGIN

typedef FourCharCode DescType;
typedef FourCharCode AEEventClass;
typedef FourCharCode AEEventID;
typedef FourCharCode AEKeyword;
typedef FourCharCode AEReturnID;
typedef FourCharCode AETransactionID;

/* THE SEND OPTIONS APPLE NAMES (10.11). They are `AESendMode`'s bits under the Foundation spelling. NOTHING HERE SENDS
 * (see `-sendEventWithOptions:timeout:error:` below), so the type exists for the declaration's sake — a caller compiling
 * against this header must find the same names. `NSAppleEventSendDefaultOptions` is Apple's own combination, not a new
 * policy. */
typedef NS_OPTIONS(NSUInteger, NSAppleEventSendOptions) {
	NSAppleEventSendNoReply = 1,
	NSAppleEventSendQueueReply = 2,
	NSAppleEventSendWaitForReply = 3,
	NSAppleEventSendCanInterrupt = 4,
	NSAppleEventSendAlwaysInteract = 0x10,
	NSAppleEventSendNeverInteract = 0x20,
	NSAppleEventSendDontRecord = 0x1000,
	NSAppleEventSendDontExecute = 0x2000,
	NSAppleEventSendDontAnnotate = 0x10000,
	NSAppleEventSendDefaultOptions = NSAppleEventSendWaitForReply | NSAppleEventSendCanInterrupt
};

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
	typeUnicodeText = 'utxt',
	/* THE 10.11 DOORS' PAYLOADS. Each names a real Apple type code rather than a private one, so a descriptor built
	 * here is readable by the same rules a Carbon peer would use. */
	typeIEEE64BitFloatingPoint = 'doub',
	typeDate = 'ldtn',
	typeFileURL = 'furl',
	typeProcessSerialNumber = 'psn ',
	typeApplicationBundleID = 'bund',
	typeApplicationURL = 'aprl'
};

/* THE KEYWORD A PROCESS DESCRIPTOR'S ENTRY IS KEYED BY. Apple's AppleEvents headers spell it `keyProcessSerialNumber`;
 * this system has no Carbon ProcessSerialNumber, so the entry is a SInt32 process id (see the factory's comment). */
enum {
	keyProcessSerialNumber = 'psn '
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
+ (NSAppleEventDescriptor *)descriptorWithDouble:(double)value NS_AVAILABLE_MAC(10_11);
+ (NSAppleEventDescriptor *)descriptorWithTypeCode:(OSType)value;
+ (NSAppleEventDescriptor *)descriptorWithString:(NSString *)value;
+ (NSAppleEventDescriptor *)descriptorWithDate:(NSDate *)value NS_AVAILABLE_MAC(10_11);
+ (NSAppleEventDescriptor *)descriptorWithFileURL:(NSURL *)value NS_AVAILABLE_MAC(10_11);
+ (NSAppleEventDescriptor *)descriptorWithProcessIdentifier:(pid_t)value NS_AVAILABLE_MAC(10_11);
+ (NSAppleEventDescriptor *)descriptorWithBundleIdentifier:(NSString *)value NS_AVAILABLE_MAC(10_11);
+ (NSAppleEventDescriptor *)descriptorWithApplicationURL:(NSURL *)value NS_AVAILABLE_MAC(10_11);

/* THE PROCESS DESCRIPTOR FOR THIS PROCESS. Apple's is a ProcessSerialNumber in a record; this system has no PSN, so the
 * record carries the process id under `keyProcessSerialNumber` — the identifier the operating system actually has. */
+ (NSAppleEventDescriptor *)currentProcessDescriptor NS_AVAILABLE_MAC(10_11);
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
@property (readonly) double doubleValue NS_AVAILABLE_MAC(10_11);
@property (readonly) OSType typeCodeValue;
@property (nullable, readonly, copy) NSString *stringValue;
@property (nullable, readonly, copy) NSDate *dateValue NS_AVAILABLE_MAC(10_11);
@property (nullable, readonly, copy) NSURL *fileURLValue NS_AVAILABLE_MAC(10_11);

/* TRUE FOR A RECORD DESCRIPTOR — including an Apple event, which IS a record with an event class and id. Apple's answer
 * is about the descriptor's kind; so is this one, and it does not depend on the record holding anything yet. */
@property (readonly) BOOL isRecordDescriptor NS_AVAILABLE_MAC(10_11);

@property (readonly) AEEventClass eventClass;
@property (readonly) AEEventID eventID;
@property (readonly) AEReturnID returnID;
@property (readonly) AETransactionID transactionID;

/* THE CARBON HANDLE, WHICH THIS LIBRARY DOES NOT HAVE. The descriptor is not an AEDesc, so the door answers NULL and
 * says so; a caller that needs the Carbon struct is on the other side of a transport this library does not ship. */
- (nullable const void *)aeDesc NS_RETURNS_INNER_POINTER;

/* SENDING REFUSES BY NAME. This library has no AppleEvents transport and no Apple Event Manager to hand an event to, so
 * the door answers nil, fills in an `NSFeatureUnsupportedError`, and says on stderr what is missing. A descriptor is
 * DATA here; a caller that wants an event delivered is on the other side of a transport this system does not have. */
- (nullable NSAppleEventDescriptor *)sendEventWithOptions:(NSAppleEventSendOptions)sendOptions
						  timeout:(NSTimeInterval)timeoutInSeconds
						    error:(NSError **)error NS_AVAILABLE_MAC(10_11);

@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSAPPLEEVENTDESCRIPTOR_H */
