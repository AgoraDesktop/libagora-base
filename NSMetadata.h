/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSMetadata.h — the metadata query, over a provider this library owns.
 *
 * Spotlight is a system service this library does not have, and a query that silently returned nothing would be a fake.
 * The provider here is the FILE SYSTEM: `-searchScopes` names directories (home when none is given), `-startQuery`
 * walks them and builds one NSMetadataItem per file with the kMDItem attributes this library can observe, applies the
 * predicate, sorts, groups and calls `-queryDidFinishGathering:` on the delegate. The gathering is SYNCHRONOUS and there
 * are no live updates — `-disableUpdates`/`-enableUpdates` are stored and reported, and the delegate's update
 * notification is never sent, because nothing is watching the file system.
 */
#ifndef FOUNDATION_NSMETADATA_H
#define FOUNDATION_NSMETADATA_H

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>	/* NSTimeInterval */

@class NSArray;
@class NSTimer;
@class NSDictionary;
@class NSPredicate;
@class NSURL;
@class NSMetadataQuery;
@class NSMetadataItem;

/* THE FOUR NOTIFICATIONS (10.4). Names are Apple's; the update one is posted by this provider's poll. */
extern NSString *const NSMetadataQueryDidStartGatheringNotification;
extern NSString *const NSMetadataQueryGatheringProgressNotification;
extern NSString *const NSMetadataQueryDidFinishGatheringNotification;
extern NSString *const NSMetadataQueryDidUpdateNotification;

NS_ASSUME_NONNULL_BEGIN

@protocol NSMetadataQueryDelegate <NSObject>
@optional
- (nullable id)metadataQuery:(NSMetadataQuery *)query
     replacementValueForAttribute:(NSString *)attribute
			     value:(id)attributeValue;
@end

@interface NSMetadataItem : NSObject
{
@private
	NSDictionary *_attributes;
}
- (nullable id)valueForAttribute:(NSString *)key;
/* KVC READS THE ATTRIBUTES: a predicate is written against kMDItem keys, and NSPredicate evaluates a key path through
 * `-valueForKey:`. Without this the filter would report every item as non-compliant. */
- (nullable id)valueForKey:(NSString *)key;
- (nullable NSDictionary *)valuesForAttributes:(NSArray *)keys;
@property (readonly, copy) NSDictionary *attributes;
@end

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

@interface NSMetadataQuery : NSObject
{
@private
	id _delegate;
	NSPredicate *_predicate;
	NSArray *_sortDescriptors;
	NSArray *_searchScopes;
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
@end

NS_ASSUME_NONNULL_END

#endif /* FOUNDATION_NSMETADATA_H */
