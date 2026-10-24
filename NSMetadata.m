/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <Foundation/NSMetadata.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSPredicate.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSSortDescriptor.h>
#include <dirent.h>
#include <sys/stat.h>

/* THE ATTRIBUTE NAMES ARE APPLE'S SPELLINGS, because a predicate is written against them. */
static NSString *const NSMetadataItemFSNameKey = @"kMDItemFSName";
static NSString *const NSMetadataItemPathKey = @"kMDItemPath";
static NSString *const NSMetadataItemFSSizeKey = @"kMDItemFSSize";
static NSString *const NSMetadataItemContentModificationDateKey = @"kMDItemContentModificationDate";
static NSString *const NSMetadataItemContentCreationDateKey = @"kMDItemContentCreationDate";
static NSString *const NSMetadataItemContentTypeKey = @"kMDItemContentType";
static NSString *const NSMetadataItemKindKey = @"kMDItemKind";

@implementation NSMetadataItem

- (instancetype)initWithAttributes:(NSDictionary *)attributes
{
	self = [super init];
	if (self != nil) {
		_attributes = [attributes copy];
	}
	return self;
}

- (void)dealloc { [_attributes release]; [super dealloc]; }
- (NSDictionary *)attributes { return _attributes; }

- (id)valueForAttribute:(NSString *)key
{
	id value = [_attributes objectForKey:key];

	if (value == nil && [key isEqualToString:NSMetadataItemPathKey]) {
		value = [_attributes objectForKey:@"kMDItemPath"];
	}
	return value;
}

- (id)valueForKey:(NSString *)key
{
	id value = [_attributes objectForKey:key];

	return value != nil ? value : [super valueForKey:key];
}

- (NSDictionary *)valuesForAttributes:(NSArray *)keys
{
	NSMutableDictionary *values = [NSMutableDictionary dictionaryWithCapacity:[keys count]];
	NSUInteger i;

	for (i = 0; i < [keys count]; i++) {
		id key = [keys objectAtIndex:i];
		id value = [self valueForAttribute:key];

		if (value != nil) {
			[values setObject:value forKey:key];
		}
	}
	return values;
}

@end

@implementation NSMetadataQueryAttributeValueTuple

- (instancetype)initWithAttribute:(NSString *)attribute value:(id)value count:(NSUInteger)count
{
	self = [super init];
	if (self != nil) {
		_attribute = [attribute copy];
		_value = [value retain];
		_count = count;
	}
	return self;
}

- (void)dealloc { [_attribute release]; [_value release]; [super dealloc]; }
- (NSString *)attribute { return _attribute; }
- (id)value { return _value; }
- (NSUInteger)count { return _count; }

@end

@implementation NSMetadataQueryResultGroup

- (instancetype)initWithAttribute:(NSString *)attribute value:(id)value results:(NSArray *)results
{
	self = [super init];
	if (self != nil) {
		_attribute = [attribute copy];
		_value = [value retain];
		_results = [results copy];
	}
	return self;
}

- (void)dealloc
{
	[_attribute release];
	[_value release];
	[_results release];
	[_subgroups release];
	[super dealloc];
}

- (NSString *)attribute { return _attribute; }
- (id)value { return _value; }
- (NSArray *)results { return _results; }
- (NSArray *)subgroups { return _subgroups; }
- (NSUInteger)resultCount { return [_results count]; }

- (id)resultAtIndex:(NSUInteger)index
{
	return index < [_results count] ? [_results objectAtIndex:index] : nil;
}

@end

@implementation NSMetadataQuery

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_notificationBatchingInterval = 0.0;
	}
	return self;
}

- (void)dealloc
{
	[_predicate release];
	[_sortDescriptors release];
	[_searchScopes release];
	[_valueListAttributes release];
	[_groupingAttributes release];
	[_results release];
	[_groupedResults release];
	[_valueLists release];
	[super dealloc];
}

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSPredicate *)predicate { return _predicate; }
- (void)setPredicate:(NSPredicate *)predicate { [predicate retain]; [_predicate release]; _predicate = predicate; }
- (NSArray *)sortDescriptors { return _sortDescriptors; }
- (void)setSortDescriptors:(NSArray *)descriptors
{
	[descriptors retain];
	[_sortDescriptors release];
	_sortDescriptors = descriptors;
}
- (NSArray *)searchScopes { return _searchScopes; }
- (void)setSearchScopes:(NSArray *)scopes
{
	[scopes retain];
	[_searchScopes release];
	_searchScopes = scopes;
}
- (NSArray *)valueListAttributes { return _valueListAttributes; }
- (void)setValueListAttributes:(NSArray *)attributes
{
	[attributes retain];
	[_valueListAttributes release];
	_valueListAttributes = attributes;
}
- (NSArray *)groupingAttributes { return _groupingAttributes; }
- (void)setGroupingAttributes:(NSArray *)attributes
{
	[attributes retain];
	[_groupingAttributes release];
	_groupingAttributes = attributes;
}
- (NSTimeInterval)notificationBatchingInterval { return _notificationBatchingInterval; }
- (void)setNotificationBatchingInterval:(NSTimeInterval)interval { _notificationBatchingInterval = interval; }

- (BOOL)isStarted { return _started; }
- (BOOL)isStopped { return !_started; }
- (BOOL)isGathering { return _gathering; }
- (NSArray *)results { return _results != nil ? _results : [NSArray array]; }
- (NSUInteger)resultCount { return [_results count]; }
- (NSArray *)groupedResults { return _groupedResults; }
- (NSDictionary *)valueLists { return _valueLists; }

- (id)resultAtIndex:(NSUInteger)index
{
	return index < [_results count] ? [_results objectAtIndex:index] : nil;
}

- (NSUInteger)indexOfResult:(id)result
{
	NSUInteger index = [_results indexOfObject:result];

	return index;
}

- (id)valueOfAttribute:(NSString *)attribute forResultAtIndex:(NSUInteger)index
{
	return [[self resultAtIndex:index] valueForAttribute:attribute];
}

- (void)disableUpdates { _updatesDisabled = YES; }
- (void)enableUpdates { _updatesDisabled = NO; }

/* THE WALK. `-fnGatherAtPath:` recurses; a file becomes an item with the attributes this library can observe. A
 * directory is walked but is not itself a result, which matches what a content query returns for a file system. */
- (void)fnGatherAtPath:(NSString *)path into:(NSMutableArray *)items
{
	DIR *dir = opendir([path fileSystemRepresentation]);
	struct dirent *entry;

	if (dir == NULL) {
		return;
	}
	while ((entry = readdir(dir)) != NULL) {
		NSString *name = [NSString stringWithUTF8String:entry->d_name];
		NSString *child;
		struct stat info;

		if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
			continue;
		}
		child = [path stringByAppendingPathComponent:name];
		if (lstat([child fileSystemRepresentation], &info) != 0) {
			continue;
		}
		if (S_ISDIR(info.st_mode)) {
			[self fnGatherAtPath:child into:items];
			continue;
		}
		{
			NSMutableDictionary *attributes = [NSMutableDictionary dictionary];

			[attributes setObject:name forKey:NSMetadataItemFSNameKey];
			[attributes setObject:child forKey:NSMetadataItemPathKey];
			[attributes setObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)info.st_size]
				      forKey:NSMetadataItemFSSizeKey];
			[attributes setObject:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)info.st_mtime]
				      forKey:NSMetadataItemContentModificationDateKey];
			[attributes setObject:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)info.st_ctime]
				      forKey:NSMetadataItemContentCreationDateKey];
			[attributes setObject:([name pathExtension].length > 0 ? [name pathExtension] : @"public.data")
				      forKey:NSMetadataItemContentTypeKey];
			[attributes setObject:([name pathExtension].length > 0 ? [name pathExtension] : @"File")
				      forKey:NSMetadataItemKindKey];
			[items addObject:[[[NSMetadataItem alloc] initWithAttributes:attributes] autorelease]];
		}
	}
	closedir(dir);
}

- (NSString *)fnPathForScope:(id)scope
{
	if ([scope isKindOfClass:[NSURL class]]) {
		return [scope path];
	}
	return [scope isKindOfClass:[NSString class]] ? scope : nil;
}

- (void)startQuery
{
	NSMutableArray *items = [NSMutableArray array];
	NSArray *scopes = _searchScopes;
	NSUInteger i;

	_started = YES;
	_gathering = YES;
	if (scopes == nil || [scopes count] == 0) {
		scopes = [NSArray arrayWithObject:NSHomeDirectory()];
	}
	for (i = 0; i < [scopes count]; i++) {
		NSString *path = [self fnPathForScope:[scopes objectAtIndex:i]];

		if (path != nil) {
			[self fnGatherAtPath:path into:items];
		}
	}
	if (_predicate != nil) {
		NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:[items count]];

		for (i = 0; i < [items count]; i++) {
			id item = [items objectAtIndex:i];

			if ([_predicate evaluateWithObject:item]) {
				[filtered addObject:item];
			}
		}
		items = filtered;
	}
	if (_sortDescriptors != nil && [_sortDescriptors count] > 0) {
		[items sortUsingDescriptors:_sortDescriptors];
	}
	[_results release];
	_results = [items copy];
	[_groupedResults release];
	_groupedResults = nil;
	[_valueLists release];
	_valueLists = nil;
	if (_groupingAttributes != nil && [_groupingAttributes count] > 0) {
		NSMutableArray *groups = [NSMutableArray array];
		NSString *attribute = [_groupingAttributes objectAtIndex:0];
		NSMutableDictionary *byValue = [NSMutableDictionary dictionary];

		for (i = 0; i < [items count]; i++) {
			id value = [[items objectAtIndex:i] valueForAttribute:attribute];

			if (value != nil) {
				NSMutableArray *bucket = [byValue objectForKey:value];

				if (bucket == nil) {
					bucket = [NSMutableArray array];
					[byValue setObject:bucket forKey:value];
				}
				[bucket addObject:[items objectAtIndex:i]];
			}
		}
		{
			NSEnumerator *values = [byValue keyEnumerator];
			id value;

			while ((value = [values nextObject]) != nil) {
				[groups addObject:[[[NSMetadataQueryResultGroup alloc] initWithAttribute:attribute
											      value:value
											    results:[byValue objectForKey:value]]
						   autorelease]];
			}
		}
		_groupedResults = [groups copy];
	}
	if (_valueListAttributes != nil && [_valueListAttributes count] > 0) {
		NSMutableDictionary *lists = [NSMutableDictionary dictionary];

		for (i = 0; i < [_valueListAttributes count]; i++) {
			NSString *attribute = [_valueListAttributes objectAtIndex:i];
			NSMutableDictionary *counts = [NSMutableDictionary dictionary];
			NSMutableArray *tuples = [NSMutableArray array];
			NSEnumerator *values;
			id value;
			NSUInteger j;

			for (j = 0; j < [items count]; j++) {
				id candidate = [[items objectAtIndex:j] valueForAttribute:attribute];

				if (candidate != nil) {
					[counts setObject:[NSNumber numberWithUnsignedInteger:
							   [[counts objectForKey:candidate] unsignedIntegerValue] + 1]
						   forKey:candidate];
				}
			}
			values = [counts keyEnumerator];
			while ((value = [values nextObject]) != nil) {
				[tuples addObject:[[[NSMetadataQueryAttributeValueTuple alloc]
						    initWithAttribute:attribute
								value:value
								count:[[counts objectForKey:value] unsignedIntegerValue]]
						   autorelease]];
			}
			[lists setObject:tuples forKey:attribute];
		}
		_valueLists = [lists copy];
	}
	_gathering = NO;
	if ([_delegate respondsToSelector:@selector(metadataQueryDidFinishGathering:)]) {
		typedef void (*fn_delegate)(id, SEL, id);
		fn_delegate call = (fn_delegate)[(id)_delegate methodForSelector:
						 @selector(metadataQueryDidFinishGathering:)];

		call(_delegate, @selector(metadataQueryDidFinishGathering:), self);
	}
}

- (void)stopQuery
{
	_started = NO;
	_gathering = NO;
}

@end
