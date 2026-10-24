/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
#import <Foundation/NSNetServices.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSData.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSInputStream.h>
#import <Foundation/NSOutputStream.h>
#import <Foundation/NSNull.h>

NSString *const NSNetServicesErrorCode = @"NSNetServicesErrorCode";
NSString *const NSNetServicesErrorDomain = @"NSNetServicesErrorDomain";

static void fn_call_delegate(id delegate, SEL selector, id argument)
{
	if (delegate != nil && [delegate respondsToSelector:selector]) {
		typedef void (*fn_delegate)(id, SEL, id);
		fn_delegate call = (fn_delegate)[delegate methodForSelector:selector];

		call(delegate, selector, argument);
	}
}

@implementation NSNetService

- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name port:(NSInteger)port
{
	self = [super init];
	if (self != nil) {
		_domain = [domain copy];
		_type = [type copy];
		_name = [name copy];
		_port = port;
		_schedules = [[NSMutableArray alloc] init];
	}
	return self;
}

- (instancetype)initWithDomain:(NSString *)domain type:(NSString *)type name:(NSString *)name
{
	return [self initWithDomain:domain type:type name:name port:-1];
}

- (void)dealloc
{
	[_domain release];
	[_type release];
	[_name release];
	[_txtRecord release];
	[_protocolSpecificInformation release];
	[_schedules release];
	[super dealloc];
}

- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (NSString *)domain { return _domain; }
- (NSString *)type { return _type; }
- (NSString *)name { return _name; }
- (NSInteger)port { return _port; }
- (NSArray *)addresses { return [NSArray array]; }
- (NSString *)hostName { return nil; }

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	[_schedules addObject:[NSArray arrayWithObjects:aRunLoop != nil ? (id)aRunLoop : (id)[NSNull null],
			       mode != nil ? (id)mode : (id)NSDefaultRunLoopMode, nil]];
}

- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	(void)aRunLoop;
	(void)mode;
	[_schedules removeAllObjects];
}

/* THE THREE NETWORK OPERATIONS, EACH REPORTING THE ABSENT SUBSYSTEM TO THE DELEGATE. A publication that "succeeded"
 * here would be a name nothing can resolve; the delegate is told, and `-stop` answers the stop callback. */
- (void)publish
{
	[self publishWithOptions:0];
}

- (void)publishWithOptions:(NSNetServiceOptions)options
{
	(void)options;
	fn_call_delegate(_delegate, @selector(netServiceWillPublish:), self);
	fn_call_delegate(_delegate, @selector(netService:didNotPublish:), self);
}

- (void)resolve
{
	[self resolveWithTimeout:5.0];
}

- (void)resolveWithTimeout:(NSTimeInterval)timeout
{
	(void)timeout;
	fn_call_delegate(_delegate, @selector(netServiceWillResolve:), self);
	fn_call_delegate(_delegate, @selector(netService:didNotResolve:), self);
}

- (void)stop
{
	_published = NO;
	_resolving = NO;
	fn_call_delegate(_delegate, @selector(netServiceDidStop:), self);
}

- (void)startMonitoring { }
- (void)stopMonitoring { }

/* THE TXT RECORD IS A REAL WIRE FORMAT: one length byte, then `key=value` bytes, repeated. It is the one part of
 * Bonjour that needs no network at all, so it is implemented rather than refused. */
+ (NSDictionary *)dictionaryFromTXTRecordData:(NSData *)txtData
{
	const unsigned char *bytes;
	NSUInteger length, at = 0;
	NSMutableDictionary *record;

	if (txtData == nil) {
		[NSException raise:NSInvalidArgumentException format:@"+dictionaryFromTXTRecordData: needs data"];
	}
	bytes = [txtData bytes];
	length = [txtData length];
	record = [NSMutableDictionary dictionary];
	while (at < length) {
		NSUInteger itemLength = bytes[at++];
		NSString *text;
		NSRange equals;

		if (at + itemLength > length) {
			return nil;		/* a length that runs past the data is a malformed record */
		}
		text = [[[NSString alloc] initWithBytes:bytes + at length:itemLength encoding:NSUTF8StringEncoding]
			autorelease];
		at += itemLength;
		if (text == nil) {
			return nil;
		}
		equals = [text rangeOfString:@"="];
		if (equals.location == NSNotFound) {
			[record setObject:[NSData data] forKey:text];
		} else {
			NSString *value = [text substringFromIndex:equals.location + 1];

			/* APPLE'S CONTRACT IS NSData VALUES, and a caller decodes them as the type its key promises. */
			[record setObject:[value dataUsingEncoding:NSUTF8StringEncoding]
				   forKey:[text substringToIndex:equals.location]];
		}
	}
	return record;
}

+ (NSData *)dataFromTXTRecordDictionary:(NSDictionary *)txtDictionary
{
	NSMutableData *data;
	NSEnumerator *keys;

	if (txtDictionary == nil) {
		[NSException raise:NSInvalidArgumentException format:@"+dataFromTXTRecordDictionary: needs a dictionary"];
	}
	data = [NSMutableData data];
	keys = [txtDictionary keyEnumerator];
	{
		id key;

		while ((key = [keys nextObject]) != nil) {
			id value = [txtDictionary objectForKey:key];
			NSString *text = [value isKindOfClass:[NSData class]]
				? [[[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding] autorelease]
				: [value description];
			NSString *item = [NSString stringWithFormat:@"%@=%@", key, (text != nil ? text : @"")];
			NSData *itemData = [item dataUsingEncoding:NSUTF8StringEncoding];
			unsigned char length = (unsigned char)([itemData length] > 255 ? 255 : [itemData length]);

			if ([itemData length] > 255) {
				return nil;		/* one item cannot exceed 255 bytes */
			}
			[data appendBytes:&length length:1];
			[data appendData:itemData];
		}
	}
	return data;
}

- (BOOL)setTXTRecordData:(NSData *)recordData
{
	[recordData retain];
	[_txtRecord release];
	_txtRecord = recordData;
	return YES;
}

- (NSData *)TXTRecordData { return _txtRecord; }
- (NSString *)protocolSpecificInformation { return _protocolSpecificInformation; }
- (void)setProtocolSpecificInformation:(NSString *)information
{
	[information copy];
	[_protocolSpecificInformation release];
	_protocolSpecificInformation = [information copy];
}

- (BOOL)getInputStream:(NSInputStream **)inputStream outputStream:(NSOutputStream **)outputStream
{
	if (inputStream != NULL) {
		*inputStream = nil;
	}
	if (outputStream != NULL) {
		*outputStream = nil;
	}
	return NO;
}

@end

@implementation NSNetServiceBrowser

- (instancetype)init
{
	self = [super init];
	if (self != nil) {
		_schedules = [[NSMutableArray alloc] init];
	}
	return self;
}

- (void)dealloc { [_schedules release]; [super dealloc]; }
- (id)delegate { return _delegate; }
- (void)setDelegate:(id)delegate { _delegate = delegate; }
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	[_schedules addObject:[NSArray arrayWithObjects:aRunLoop != nil ? (id)aRunLoop : (id)[NSNull null],
			       mode != nil ? (id)mode : (id)NSDefaultRunLoopMode, nil]];
}
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode
{
	(void)aRunLoop;
	(void)mode;
	[_schedules removeAllObjects];
}

/* EVERY SEARCH REFUSES THE SAME WAY: the delegate is told that no search could start, so a caller learns it from the
 * callback rather than from an empty result that looks like "nothing is published". */
- (void)fn_reportSearchFailure
{
	fn_call_delegate(_delegate, @selector(netServiceBrowser:didNotSearch:), self);
}

- (void)searchForBrowsableDomains { [self fn_reportSearchFailure]; }
- (void)searchForRegistrationDomains { [self fn_reportSearchFailure]; }
- (void)searchForAllDomains { [self fn_reportSearchFailure]; }
- (void)searchForServicesOfType:(NSString *)serviceType inDomain:(NSString *)domainString
{
	(void)serviceType;
	(void)domainString;
	[self fn_reportSearchFailure];
}

- (void)stop
{
	if (_searching) {
		_searching = NO;
		fn_call_delegate(_delegate, @selector(netServiceBrowserDidStopSearch:), self);
	}
}

@end
