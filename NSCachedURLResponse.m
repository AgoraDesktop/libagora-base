/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSCachedURLResponse.m — the value's machinery. The design and the reasoning are in
 * NSCachedURLResponse.h.
 */
#import <Foundation/NSCachedURLResponse.h>
#import <Foundation/NSURLResponse.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>

@implementation NSCachedURLResponse

/* THE CONVENIENCE DOOR DELEGATES rather than repeating the assignment: with three stored facts and a
 * default policy, one code path is the only way the two initializers cannot drift apart. */
- (instancetype)initWithResponse:(NSURLResponse *)response data:(NSData *)data
{
	return [self initWithResponse:response
				 data:data
			     userInfo:nil
			storagePolicy:NSURLCacheStorageAllowed];
}

- (instancetype)initWithResponse:(NSURLResponse *)response
			    data:(NSData *)data
			userInfo:(NSDictionary *)userInfo
		   storagePolicy:(NSURLCacheStoragePolicy)storagePolicy
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_response = [response copy];
	_data = [data copy];
	_userInfo = [userInfo copy];
	_storagePolicy = storagePolicy;
	return self;
}

- (NSURLResponse *)response
{
	return _response;
}

- (NSData *)data
{
	return _data;
}

- (NSDictionary *)userInfo
{
	return _userInfo;
}

- (NSURLCacheStoragePolicy)storagePolicy
{
	return _storagePolicy;
}

- (void)dealloc
{
	[_response release];
	[_data release];
	[_userInfo release];
	[super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
	return [self retain];	/* immutable: the copy IS the receiver (plan §15.2) */
}

@end
