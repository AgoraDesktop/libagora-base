/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSMetadata.h — the metadata query, over a provider this library owns.
 *
 * Spotlight is a system service this library does not have, and a query that silently returned nothing would be a fake.
 * The provider here is the FILE SYSTEM: `-searchItems` (10.9) or `-searchScopes` names the items (home when neither is
 * given), `-startQuery` walks them and builds one NSMetadataItem per file with the kMDItem attributes this library can
 * observe, applies the predicate, sorts, groups and calls `-queryDidFinishGathering:` on the delegate. The GATHERING is
 * SYNCHRONOUS; live updates are a POLL at `-notificationBatchingInterval`, and a changed path set is announced with
 * `NSMetadataQueryDidUpdateNotification`. `-operationQueue` is stored and reported — this provider gathers on the
 * caller's thread, so there is no second queue for a notification to be posted to.
 */
#ifndef FOUNDATION_NSMETADATA_H
#define FOUNDATION_NSMETADATA_H

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>	/* NSTimeInterval */
#import <Foundation/NSMetadataAttributes.h>
#import <Foundation/NSIndexSet.h>	/* NSEnumerationOptions */

@class NSArray;
@class NSTimer;
@class NSDictionary;
@class NSPredicate;
@class NSOperationQueue;
@class NSURL;
@class NSMetadataQuery;
@class NSMetadataItem;

/* THE FOUR NOTIFICATIONS (10.4). Names are Apple's; the update one is posted by this provider's poll. */
extern NSString * _Nonnull const NSMetadataQueryDidStartGatheringNotification;
extern NSString * _Nonnull const NSMetadataQueryGatheringProgressNotification;
extern NSString * _Nonnull const NSMetadataQueryDidFinishGatheringNotification;
extern NSString * _Nonnull const NSMetadataQueryDidUpdateNotification;

NS_ASSUME_NONNULL_BEGIN

@protocol NSMetadataQueryDelegate <NSObject>
@optional
- (nullable id)metadataQuery:(NSMetadataQuery *)query
     replacementValueForAttribute:(NSString *)attribute
			     value:(id)attributeValue;
@end

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSMetadataItem : NSObject
{
@private
	NSDictionary *_attributes;
}
/* THE ITEM FOR ONE ITEM ON DISK (10.9). Apple's door names a URL rather than a query, so an item can be read without
 * gathering anything; the attributes are the same kMDItem set `-startQuery` observes, and a path that is not there
 * leaves them empty rather than inventing file facts. */
- (instancetype)initWithURL:(NSURL *)url NS_DESIGNATED_INITIALIZER NS_AVAILABLE_MAC(10_9);
- (nullable id)valueForAttribute:(NSString *)key;
/* KVC READS THE ATTRIBUTES: a predicate is written against kMDItem keys, and NSPredicate evaluates a key path through
 * `-valueForKey:`. Without this the filter would report every item as non-compliant. */
- (nullable id)valueForKey:(NSString *)key;
- (nullable NSDictionary *)valuesForAttributes:(NSArray *)keys;
@property (readonly, copy) NSDictionary *attributes;
@end

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSMetadataQueryAttributeValueTuple : NSObject
{
@private
	NSString *_attribute;
	id _value;
	NSUInteger _count;
}
@property (readonly, copy) NSString *attribute;
@property (nullable, readonly, strong) id value;
@property (readonly) NSUInteger count;
@end

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSMetadataQueryResultGroup : NSObject
{
@private
	NSString *_attribute;
	id _value;
	NSArray *_results;
	NSArray *_subgroups;
}
@property (readonly, copy) NSString *attribute;
@property (nullable, readonly, strong) id value;
- (nullable id)resultAtIndex:(NSUInteger)index;
@property (readonly) NSUInteger resultCount;
@property (readonly, copy) NSArray *results;
@property (nullable, readonly, copy) NSArray *subgroups;
@end

NS_CLASS_AVAILABLE_MAC(10_4)
@interface NSMetadataQuery : NSObject
{
@private
	id _delegate;
	NSPredicate *_predicate;
	NSArray *_sortDescriptors;
	NSArray *_searchScopes;
	NSArray *_searchItems;
	NSOperationQueue *_operationQueue;
	NSArray *_valueListAttributes;
	NSArray *_groupingAttributes;
	NSTimeInterval _notificationBatchingInterval;
	NSArray *_results;
	NSArray *_groupedResults;
	NSDictionary *_valueLists;
	BOOL _started;
	BOOL _gathering;
	BOOL _updatesDisabled;
	NSTimer *_updateTimer;		/* the provider's poll, when updates are enabled */
}

- (instancetype)init;

@property (nullable, assign) id <NSMetadataQueryDelegate> delegate;
@property (nullable, strong) NSPredicate *predicate;
@property (nullable, copy) NSArray *sortDescriptors;
@property (nullable, copy) NSArray *searchScopes;	/* NSURLs or path strings */
/* THE 10.9 WAY TO NAME WHAT TO SEARCH: file URLs, files or directories. When it is set it IS the scope — a non-empty
 * `searchItems` wins over `searchScopes`, which is Apple's direction of travel for the two properties. */
@property (nullable, copy) NSArray *searchItems NS_AVAILABLE_MAC(10_9);
/* "The operation queue to which the query's notifications are posted." This provider notifies on the thread that
 * gathers, so the queue is stored and reported rather than used; a caller that sets one is not lied to about what it
 * holds. */
@property (nullable, strong) NSOperationQueue *operationQueue NS_AVAILABLE_MAC(10_9);
@property (nullable, copy) NSArray *valueListAttributes;
@property (nullable, copy) NSArray *groupingAttributes;
@property NSTimeInterval notificationBatchingInterval;

@property (readonly) BOOL isStarted;
@property (readonly) BOOL isStopped;
@property (readonly) BOOL isGathering;
@property (readonly, copy) NSArray *results;
@property (readonly) NSUInteger resultCount;
- (nullable id)resultAtIndex:(NSUInteger)index;
- (NSUInteger)indexOfResult:(id)result;
@property (nullable, readonly, copy) NSArray *groupedResults;
@property (nullable, readonly, copy) NSDictionary *valueLists;

- (void)startQuery;
- (void)stopQuery;
- (void)disableUpdates;
- (void)enableUpdates;

- (nullable id)valueOfAttribute:(NSString *)attribute forResultAtIndex:(NSUInteger)index;

/* THE BLOCK WALKS (10.9). The options are the two every enumeration door here takes: `NSEnumerationReverse` walks from
 * the last result, `NSEnumerationConcurrent` is a hint this library does not take. The index is the result's index, so a
 * reverse walk still answers the number `-resultAtIndex:` expects. */
- (void)enumerateResultsUsingBlock:(void (^)(id result, NSUInteger index, BOOL *stop))block NS_AVAILABLE_MAC(10_9);
- (void)enumerateResultsWithOptions:(NSEnumerationOptions)options
			 usingBlock:(void (^)(id result, NSUInteger index, BOOL *stop))block NS_AVAILABLE_MAC(10_9);
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSMETADATA_H */
